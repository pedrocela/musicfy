import AppKit
import Combine

/// The heart of Musicfy: reads the apps, decides which one to show and sends commands.
/// The UI only watches what this class publishes and calls its methods.
@MainActor
final class PlayerController: ObservableObject {
    struct Problem: Equatable {
        let source: SourceKind
        let kind: SourceProblem
    }

    @Published private(set) var state: PlayerState? {
        didSet { syncClock() }
    }
    /// When `state.position` was read; the live position is interpolated from here.
    @Published private(set) var positionDate = Date() {
        didSet { syncClock() }
    }
    /// Ticks for the time labels and the lyrics, only while it's worth it.
    let clock = PlaybackClock()
    @Published private(set) var artwork: NSImage? {
        didSet {
            artworkToken &+= 1
            makeLook()
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
        didSet {
            if lyricsVisible, let state { loadLyrics(for: state) }
            if lyricsVisible != oldValue { syncClock() }
        }
    }

    let settings: Settings

    private let podcasts = PodcastsSource()
    private lazy var sources: [SourceKind: MediaSource] = [
        .music: MusicSource(),
        .spotify: SpotifySource(),
        .podcasts: podcasts,
    ]
    private var lastStates: [SourceKind: PlayerState] = [:]
    private var startedAt: [SourceKind: Date] = [:]
    private var timer: Timer?
    /// The player window is on screen. Hidden, there's nothing to keep up to date as often.
    var panelVisible = true {
        didSet {
            guard panelVisible != oldValue else { return }
            scheduleTimer()
            syncClock()
            if panelVisible { refresh() }
        }
    }
    private var refreshing = false
    private var lastFullRead = Date.distantPast
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
                SourceKind.forgetInstalled()
                Task { @MainActor in self?.refreshSoon(0.5) }
            })
        }
        // Podcasts has no notification of its own; its Now Playing reader says when it changes.
        podcasts.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        scheduleTimer()
        refresh()
    }

    /// How often the apps are read. Both post a notification when they play, pause or change
    /// song, so reading is only for what they don't announce (the position after a seek,
    /// volume, shuffle). Playing and on screen: every 1.5 s. Paused, closed or hidden:
    /// every 4 s, which saves most of the Apple Events without anyone noticing.
    private var pollInterval: TimeInterval {
        let playing = lastStates.values.contains(where: \.isPlaying)
        return playing && panelVisible ? 1.5 : 4
    }

    private func scheduleTimer() {
        let interval = pollInterval
        if let timer, timer.isValid, timer.timeInterval == interval { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(onlyRelevant: true) }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// `onlyRelevant` (the timer): read just the app on screen and any that's playing. The
    /// other one announces it if it starts playing; it's read in full every 20 s anyway.
    /// Every read is a round trip that also wakes the app being asked.
    func refresh(onlyRelevant: Bool = false) {
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        let startedGeneration = generation
        var sources = self.sources
        if onlyRelevant, Date().timeIntervalSince(lastFullRead) < 20 {
            sources = sources.filter { kind, _ in
                kind == state?.source || lastStates[kind]?.isPlaying == true
            }
        } else {
            lastFullRead = Date()
        }
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
        scheduleTimer()
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
                chosen = lastStates[.music] ?? lastStates[.spotify] ?? lastStates[.podcasts]
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

    private func syncClock() {
        clock.sync(running: panelVisible && state?.isPlaying == true, fine: lyricsVisible, position: position())
    }

    /// Interpolated position: the script is read every 1.5 s but the bar moves smoothly.
    func position(at date: Date = Date()) -> Double {
        guard let state else { return 0 }
        let elapsed = state.isPlaying ? date.timeIntervalSince(positionDate) : 0
        let value = state.position + elapsed
        return state.duration > 0 ? min(value, state.duration) : value
    }

    /// The song's progress (0 to 1) right now.
    func progressFraction(at date: Date = Date()) -> Double {
        guard let duration = state?.duration, duration > 0 else { return 0 }
        return min(1, position(at: date) / duration)
    }

    /// How much of the song goes by per second: 0 when paused. Core Animation moves the
    /// bar and the ring at this speed between readings.
    var progressRate: Double {
        guard let state, state.isPlaying, state.duration > 0 else { return 0 }
        return 1 / state.duration
    }

    // MARK: - Artwork and lyrics

    private func loadArtwork(for state: PlayerState) {
        let key = state.artworkTag.isEmpty ? state.trackKey : "\(state.trackKey)|\(state.artworkTag)"
        guard key != artworkKey else { return }
        artworkKey = key
        if let hit = ArtworkLoader.shared.cached(key) {
            if hit !== artwork { artwork = hit }
            return
        }
        let source = sources[state.source]
        Task {
            var image: NSImage?
            if let source, state.source == .music || state.source == .podcasts {
                image = await withCheckedContinuation { continuation in
                    AppleScriptRunner.shared.queue.async {
                        continuation.resume(returning: source.fetchEmbeddedArtwork())
                    }
                }
            }
            if image == nil, let url = state.artworkURL {
                image = await ArtworkLoader.shared.image(from: url)
            }
            if image == nil, state.source == .podcasts {
                // The artwork usually comes a moment after the episode; until then, the show's.
                image = await ArtworkLoader.shared.searchPodcast(show: state.artist.isEmpty ? state.album : state.artist)
            } else if image == nil {
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
        guard state.source.hasLyrics else {
            lyrics = nil
            lyricsLoading = false
            return
        }
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
        guard activeSource != nil, state?.source.hasAppVolume == true else { return }
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
        guard let source = activeSource, let on = state?.shuffle, state?.source.hasPlayModes == true else { return }
        update { $0.shuffle = !on }
        source.setShuffle(!on)
        refreshSoon()
    }

    func cycleRepeat() {
        guard let source = activeSource, let state, state.source.hasPlayModes else { return }
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

    /// The colors and the glass come from the artwork. Both are worked out off the main
    /// thread (the colors first: they're ready in a millisecond, the glass takes longer).
    private func makeLook() {
        glass = nil
        guard let image = artwork else {
            palette = .neutral
            return
        }
        let token = artworkToken
        DispatchQueue.global(qos: .userInitiated).async {
            let palette = ArtworkPalette.from(image)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.artworkToken == token else { return }
                    if palette != self.palette { self.palette = palette }
                }
            }
            let glass = ArtworkGlass.make(from: image)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.artworkToken == token else { return }
                    self.glass = glass
                }
            }
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
