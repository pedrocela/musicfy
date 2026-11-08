import AppKit
import Combine

/// El corazón de Musicfy: lee las dos apps, decide cuál mostrar y manda los comandos.
/// La interfaz sólo mira lo que publica esta clase y llama a sus métodos.
@MainActor
final class PlayerController: ObservableObject {
    struct Problem: Equatable {
        let source: SourceKind
        let kind: SourceProblem
    }

    @Published private(set) var state: PlayerState?
    /// Momento en que se leyó `state.position`; la posición en vivo se interpola desde acá.
    @Published private(set) var positionDate = Date()
    @Published private(set) var artwork: NSImage? {
        didSet {
            artworkToken &+= 1
            palette = artwork.map(ArtworkPalette.from) ?? .neutral
        }
    }
    /// Colores de la tapa actual (fondo del compacto, acento de la Isla).
    @Published private(set) var palette = ArtworkPalette.neutral
    /// Cambia con cada tapa nueva: la interfaz lo usa para el fundido cruzado.
    @Published private(set) var artworkToken = 0
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var lyricsLoading = false
    @Published private(set) var problem: Problem?
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
    private var refreshAgain = false
    /// Sube con cada comando: una lectura que empezó antes se descarta (traería el estado viejo).
    private var generation = 0
    private var artworkKey: String?
    private var lyricsKey: String?
    private var pendingVolume: Int?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    init(settings: Settings) {
        self.settings = settings
        settings.$forcedSource
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.chooseActive() } }
            .store(in: &cancellables)
    }

    // MARK: - Lectura

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
            case .success(let fresh):
                if newProblem?.source == kind { newProblem = nil }
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

    /// Automático: la última que empezó a sonar. Si nada suena, se queda con la que estaba.
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
        loadArtwork(for: chosen)
        if lyricsVisible { loadLyrics(for: chosen) }
    }

    /// Posición interpolada: el script se lee cada 1,5 s pero la barra avanza fluida.
    func position(at date: Date = Date()) -> Double {
        guard let state else { return 0 }
        let elapsed = state.isPlaying ? date.timeIntervalSince(positionDate) : 0
        let value = state.position + elapsed
        return state.duration > 0 ? min(value, state.duration) : value
    }

    // MARK: - Tapa y letra

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

    // MARK: - Comandos

    private var activeSource: MediaSource? { state.flatMap { sources[$0.source] } }

    /// Aplica un cambio optimista al estado para que la interfaz responda al instante.
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
        if state?.isPlaying == true, let kind = state?.source { startedAt[kind] = Date() }
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

    /// El slider manda decenas de valores por segundo: se agrupan cada 80 ms.
    func setVolume(_ volume: Int) {
        guard activeSource != nil else { return }
        update { $0.volume = volume }
        let alreadyScheduled = pendingVolume != nil
        pendingVolume = volume
        guard !alreadyScheduled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            Task { @MainActor in
                guard let self, let value = self.pendingVolume else { return }
                self.pendingVolume = nil
                self.activeSource?.setVolume(value)
                self.refreshSoon(0.5)
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
