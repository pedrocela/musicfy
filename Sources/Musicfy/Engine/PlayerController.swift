import AppKit
import Combine

/// The heart of Musicfy: reads both apps, decides which one to show and sends commands.
/// The UI only watches what this class publishes and calls its methods.
@MainActor
final class PlayerController: ObservableObject {
    struct Problem: Equatable {
        let source: SourceKind
        let kind: SourceProblem
    }

    @Published private(set) var state: PlayerState?
    /// When `state.position` was read; the live position is interpolated from here.
    @Published private(set) var positionDate = Date()
    @Published private(set) var artwork: NSImage? {
        didSet {
            artworkToken &+= 1
            palette = artwork.map(ArtworkPalette.from) ?? .neutral
            makeGlass()
        }
    }
    /// Artwork mode's glass, made from the current artwork. `nil` while computing.
    @Published private(set) var glass: ArtworkGlass?
    /// The current artwork's colors (compact background, Island accent).
    @Published private(set) var palette = ArtworkPalette.neutral
    /// Changes with every new artwork: the UI uses it for the crossfade.
    @Published private(set) var artworkToken = 0
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var lyricsLoading = false
    @Published private(set) var problem: Problem?
    /// Music's queue. `nil` with Spotify or if Music doesn't provide it.
    @Published private(set) var queue: QueueInfo?
    @Published private(set) var queueLoading = false
    @Published var queueVisible = false {
        didSet { if queueVisible { loadQueue() } }
    }
    @Published var lyricsVisible = false {
        didSet { if lyricsVisible, let state { loadLyrics(for: state) } }
    }

    let settings: Settings

    private let sources: [SourceKind: MediaSource] = [
        .music: MusicSource(),
        .spotify: SpotifySource(),
    ]
    private var lastStates: [SourceKind: PlayerState] = [:]
    private var startedAt: [SourceKind: Date] = [:]
    private var timer: Timer?
    private var refreshing = false
    /// After play or pause, what the button promised and until when. The apps take a moment
    /// to start or stop (Music buffers), and a read in between still reports the old state:
    /// trusting it made the icon flip back and forth.
    private var promisedPlaying: (source: SourceKind, playing: Bool, until: Date)?
    private var refreshAgain = false
    /// Bumped by every command: a read that started earlier is dropped (it would bring the old state).
    private var generation = 0
    private var artworkKey: String?
    private var lyricsKey: String?
    private var queueKey: String?
    private var pendingVolume: Int?
    private var volumeThrottled = false
    private var volumeRefresh: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    init(settings: Settings) {
        self.settings = settings
        settings.$forcedSource
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.chooseActive() } }
            .store(in: &cancellables)
    }

    // MARK: - Reading

    func start() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshSoon(0.5) }
            })
        }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        let startedGeneration = generation
        let sources = self.sources
        AppleScriptRunner.shared.queue.async {
            var results: [SourceKind: Result<PlayerState?, AppleScriptRunner.Failure>] = [:]
            for (kind, source) in sources {
                results[kind] = source.fetchState()
            }
            Task { @MainActor in
                self.refreshing = false
                if startedGeneration == self.generation {
                    self.apply(results)
                } else {
                    self.refreshAgain = true
                }
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    func refreshSoon(_ delay: TimeInterval = 0.35) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func apply(_ results: [SourceKind: Result<PlayerState?, AppleScriptRunner.Failure>]) {
        var newProblem = problem
        for (kind, result) in results {
            switch result {
            case .success(var fresh):
                if newProblem?.source == kind { newProblem = nil }
                if let promise = promisedPlaying, promise.source == kind, let read = fresh?.isPlaying {
                    if read == promise.playing || Date() > promise.until {
                        promisedPlaying = nil // confirmed, or the app really didn't follow
                    } else {
                        fresh?.isPlaying = promise.playing
                    }
                }
                let wasPlaying = lastStates[kind]?.isPlaying ?? false
                if let fresh, fresh.isPlaying, !wasPlaying { startedAt[kind] = Date() }
                lastStates[kind] = fresh
            case .failure(let failure):
                if failure.isNotAuthorized {
                    newProblem = Problem(source: kind, kind: .notAuthorized)
                }
            }
        }
        if newProblem != problem { problem = newProblem }
        chooseActive()
    }

    /// Automatic: the last one that started playing. If nothing plays, keep the current one.
    private func chooseActive() {
        let chosen: PlayerState?
        if let forced = settings.forcedSource {
            chosen = lastStates[forced]
        } else {
            let playing = lastStates.values.filter(\.isPlaying)
            if let newest = playing.max(by: { (startedAt[$0.source] ?? .distantPast) < (startedAt[$1.source] ?? .distantPast) }) {
                chosen = newest
            } else if let current = state?.source, let same = lastStates[current] {
                chosen = same
            } else {
                chosen = lastStates[.music] ?? lastStates[.spotify]
            }
        }
        if chosen != state {
            state = chosen
            positionDate = Date()
        }
        guard let chosen else {
            if artwork != nil { artwork = nil }
            artworkKey = nil
            lyrics = nil
            lyricsKey = nil
            return
        }
        let trackChanged = chosen.trackKey != queueKey
        loadArtwork(for: chosen)
        if lyricsVisible { loadLyrics(for: chosen) }
        if queueVisible, trackChanged { loadQueue() }
    }

    /// Interpolated position: the script is read every 1.5 s but the bar moves smoothly.
    func position(at date: Date = Date()) -> Double {
        guard let state else { return 0 }
        let elapsed = state.isPlaying ? date.timeIntervalSince(positionDate) : 0
        let value = state.position + elapsed
        return state.duration > 0 ? min(value, state.duration) : value
    }

    // MARK: - Artwork and lyrics

    private func loadArtwork(for state: PlayerState) {
        let key = state.trackKey
        guard key != artworkKey else { return }
        artworkKey = key
        if let hit = ArtworkLoader.shared.cached(key) {
            if hit !== artwork { artwork = hit }
            return
        }
        let source = sources[state.source]
        Task {
            var image: NSImage?
            if let source, state.source == .music {
                image = await withCheckedContinuation { continuation in
                    AppleScriptRunner.shared.queue.async {
                        continuation.resume(returning: source.fetchEmbeddedArtwork())
                    }
                }
            }
            if image == nil, let url = state.artworkURL {
                image = await ArtworkLoader.shared.image(from: url)
            }
            if image == nil {
                image = await ArtworkLoader.shared.searchCatalog(artist: state.artist, album: state.album, title: state.title)
            }
            guard self.artworkKey == key else { return }
            if let image { ArtworkLoader.shared.store(image, for: key) }
            if image !== self.artwork { self.artwork = image }
        }
    }

    private func loadLyrics(for state: PlayerState) {
        let key = state.trackKey
        guard key != lyricsKey else { return }
        lyricsKey = key
        lyrics = nil
        lyricsLoading = true
        Task {
            let found = await LyricsLoader.shared.lyrics(for: state)
            guard self.lyricsKey == key else { return }
            self.lyrics = found
            self.lyricsLoading = false
        }
    }

    func loadQueue() {
        guard let state, let source = sources[state.source] else {
            queue = nil
            return
        }
        queueKey = state.trackKey
        queueLoading = queue == nil
        let key = state.trackKey
        AppleScriptRunner.shared.queue.async {
            let info = source.fetchQueue()
            Task { @MainActor in
                guard self.queueKey == key else { return }
                self.queue = info
                self.queueLoading = false
            }
        }
    }

    func playQueueItem(_ item: QueueInfo.Item) {
        guard let source = activeSource else { return }
        generation += 1
        source.playQueueItem(at: item.index)
        refreshSoon(0.5)
    }

    // MARK: - Commands

    private var activeSource: MediaSource? { state.flatMap { sources[$0.source] } }

    /// Applies an optimistic change to the state so the UI responds instantly.
    private func update(_ change: (inout PlayerState) -> Void) {
        guard var current = state else { return }
        generation += 1
        current.position = position()
        change(&current)
        positionDate = Date()
        state = current
        lastStates[current.source] = current
    }

    func playPause() {
        guard let source = activeSource else { return }
        update { $0.isPlaying.toggle() }
        if let state {
            promisedPlaying = (state.source, state.isPlaying, Date().addingTimeInterval(2))
            if state.isPlaying { startedAt[state.source] = Date() }
        }
        source.playPause()
        refreshSoon()
    }

    func next() {
        guard let source = activeSource else { return }
        generation += 1
        source.next()
        refreshSoon(0.4)
    }

    func previous() {
        guard let source = activeSource else { return }
        generation += 1
        source.previous(currentPosition: position())
        refreshSoon(0.4)
    }

    func seek(toFraction fraction: Double) {
        guard let source = activeSource, let duration = state?.duration, duration > 0 else { return }
        let seconds = max(0, min(1, fraction)) * duration
        update { $0.position = seconds }
        source.seek(to: seconds)
        refreshSoon(0.6)
    }

    /// The slider sends dozens of values a second. The first one goes out right away, then
    /// at most one every 50 ms (always ending on the last value), and the state is read
    /// back only once the slider settles.
    func setVolume(_ volume: Int) {
        guard activeSource != nil else { return }
        update { $0.volume = volume }
        if volumeThrottled {
            pendingVolume = volume
        } else {
            sendVolume(volume)
        }
        volumeRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        volumeRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func sendVolume(_ volume: Int) {
        activeSource?.setVolume(volume)
        volumeThrottled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.volumeThrottled = false
                if let next = self.pendingVolume {
                    self.pendingVolume = nil
                    self.sendVolume(next)
                }
            }
        }
    }

    func toggleShuffle() {
        guard let source = activeSource, let on = state?.shuffle else { return }
        update { $0.shuffle = !on }
        source.setShuffle(!on)
        refreshSoon()
    }

    func cycleRepeat() {
        guard let source = activeSource, let state else { return }
        let next: RepeatMode
        switch (state.source, state.repeatMode) {
        case (.music, .off): next = .all
        case (.music, .all): next = .one
        case (_, .off): next = .all
        default: next = .off
        }
        update { $0.repeatMode = next }
        source.setRepeat(next)
        refreshSoon()
    }

    func toggleFavorite() {
        guard let source = activeSource, let state, state.source.supportsFavorite else { return }
        update { $0.favorited = !state.favorited }
        source.setFavorite(!state.favorited)
        refreshSoon()
    }

    // MARK: - Apps

    private func makeGlass() {
        glass = nil
        guard let image = artwork else { return }
        let token = artworkToken
        Task {
            let glass = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: ArtworkGlass.make(from: image))
                }
            }
            guard self.artworkToken == token else { return }
            self.glass = glass
        }
    }

    func open(_ kind: SourceKind) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kind.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openActiveApp() {
        if let kind = state?.source { open(kind) }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    var installedSources: [SourceKind] { SourceKind.allCases.filter(\.isInstalled) }
}
