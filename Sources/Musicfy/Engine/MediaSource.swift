import AppKit

/// Una app de música controlada por AppleScript.
///
/// Todos los scripts arrancan con `if application id … is running`: así Musicfy
/// nunca abre Music o Spotify por su cuenta (un `tell` a secas los lanza).
protocol MediaSource: AnyObject {
    var kind: SourceKind { get }

    /// Corre en la cola de AppleScript. `nil` = cerrada o detenida.
    func fetchState() -> Result<PlayerState?, AppleScriptRunner.Failure>

    /// Corre en la cola de AppleScript. Tapa incrustada, si la app la da.
    func fetchEmbeddedArtwork() -> NSImage?

    func playPause()
    func next()
    func previous(currentPosition: Double)
    func seek(to seconds: Double)
    func setVolume(_ volume: Int)
    func setShuffle(_ on: Bool)
    func setRepeat(_ mode: RepeatMode)
    func setFavorite(_ on: Bool)

    /// Corre en la cola de AppleScript. `nil` si la app no deja leer la cola.
    func fetchQueue() -> QueueInfo?
    func playQueueItem(at index: Int)
}

extension MediaSource {
    var runner: AppleScriptRunner { .shared }

    /// Envuelve un comando para que no abra la app si está cerrada.
    func command(_ body: String) -> String {
        """
        if application id "\(kind.bundleID)" is running then
        \ttell application id "\(kind.bundleID)"
        \t\t\(body)
        \tend tell
        end if
        """
    }

    func parse(_ list: NSAppleEventDescriptor) -> PlayerState? {
        let status = list.string(1)
        guard status == "playing" || status == "paused" else { return nil }
        let repeatMode = RepeatMode(rawValue: list.string(10)) ?? .off
        let artwork = list.string(12)
        return PlayerState(
            source: kind,
            isPlaying: status == "playing",
            title: list.string(2),
            artist: list.string(3),
            album: list.string(4),
            duration: max(0, list.double(5)),
            position: max(0, list.double(6)),
            trackID: list.string(7),
            volume: list.int(8),
            shuffle: list.bool(9),
            repeatMode: repeatMode,
            favorited: list.bool(11),
            artworkURL: artwork.hasPrefix("http") ? URL(string: artwork) : nil
        )
    }
}

// MARK: - Music

final class MusicSource: MediaSource {
    let kind = SourceKind.music

    /// Music cambió `loved` por `favorited`. Se elige la que compile en este Mac.
    private lazy var favoriteProperty: String = {
        let probe = { (name: String) in
            "tell application id \"com.apple.Music\" to get \(name) of current track"
        }
        return self.runner.compiles(probe("favorited")) ? "favorited" : "loved"
    }()

    private var stateScript: String {
        """
        if application id "com.apple.Music" is not running then return {"stopped"}
        tell application id "com.apple.Music"
        \tset st to "stopped"
        \tif player state is playing or player state is fast forwarding or player state is rewinding then
        \t\tset st to "playing"
        \telse if player state is paused then
        \t\tset st to "paused"
        \tend if
        \tif st is "stopped" then return {"stopped"}
        \tset nm to ""
        \tset ar to ""
        \tset al to ""
        \tset du to 0
        \tset tid to ""
        \tset fav to false
        \ttry
        \t\tset t to current track
        \t\tset nm to name of t
        \t\tset ar to artist of t
        \t\tset al to album of t
        \t\tset du to duration of t
        \t\tset tid to persistent ID of t
        \t\tset fav to \(favoriteProperty) of t
        \tend try
        \tif nm is "" then
        \t\ttry
        \t\t\tset nm to current stream title
        \t\tend try
        \tend if
        \tset pos to 0
        \ttry
        \t\tset pos to player position
        \tend try
        \tset rp to "off"
        \tif song repeat is all then
        \t\tset rp to "all"
        \telse if song repeat is one then
        \t\tset rp to "one"
        \tend if
        \treturn {st, nm, ar, al, du, pos, tid, sound volume, shuffle enabled, rp, fav, ""}
        end tell
        """
    }

    private let artworkScript = """
        if application id "com.apple.Music" is not running then return missing value
        tell application id "com.apple.Music"
        \ttry
        \t\treturn raw data of artwork 1 of current track
        \tend try
        \ttry
        \t\treturn data of artwork 1 of current track
        \tend try
        end tell
        return missing value
        """

    func fetchState() -> Result<PlayerState?, AppleScriptRunner.Failure> {
        guard kind.isInstalled, kind.isRunning else { return .success(nil) }
        return runner.run(stateScript).map { parse($0) }
    }

    func fetchEmbeddedArtwork() -> NSImage? {
        guard case .success(let desc) = runner.run(artworkScript) else { return nil }
        let data = desc.data
        guard !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    func playPause() { runner.fire(command("playpause")) }
    func next() { runner.fire(command("next track")) }
    // `back track` hace lo mismo que el botón de Music: vuelve al principio o a la anterior.
    func previous(currentPosition: Double) { runner.fire(command("back track")) }
    func seek(to seconds: Double) {
        runner.fire(command("set player position to \(Self.number(seconds))"), cache: false)
    }
    func setVolume(_ volume: Int) {
        runner.fire(command("set sound volume to \(min(100, max(0, volume)))"), cache: false)
    }
    func setShuffle(_ on: Bool) { runner.fire(command("set shuffle enabled to \(on)")) }
    func setRepeat(_ mode: RepeatMode) { runner.fire(command("set song repeat to \(mode.rawValue)")) }
    func setFavorite(_ on: Bool) {
        runner.queue.async {
            _ = self.runner.run(self.command("set \(self.favoriteProperty) of current track to \(on)"))
        }
    }

    /// Los próximos temas de la lista que está sonando. Music no expone su
    /// "A continuación" real; esto es lo que sigue en el disco o la lista.
    private let queueScript = """
        if application id "com.apple.Music" is not running then return {}
        tell application id "com.apple.Music"
        \ttry
        \t\tset pl to current playlist
        \t\tset plName to name of pl
        \t\tset idx to index of current track
        \t\tset total to count of tracks of pl
        \ton error
        \t\treturn {}
        \tend try
        \tset lastIndex to idx + 30
        \tif lastIndex > total then set lastIndex to total
        \tset rows to {}
        \trepeat with i from (idx + 1) to lastIndex
        \t\ttry
        \t\t\tset t to track i of pl
        \t\t\tset end of rows to {name of t, artist of t, album of t, persistent ID of t, i}
        \t\tend try
        \tend repeat
        \treturn {plName, rows}
        end tell
        """

    func fetchQueue() -> QueueInfo? {
        guard kind.isRunning, case .success(let desc) = runner.run(queueScript), desc.numberOfItems >= 2,
              let rows = desc.item(2) else { return nil }
        var items: [QueueInfo.Item] = []
        if rows.numberOfItems > 0 {
            for row in 1...rows.numberOfItems {
                guard let item = rows.item(row) else { continue }
                items.append(QueueInfo.Item(
                    index: item.int(5),
                    title: item.string(1),
                    artist: item.string(2),
                    album: item.string(3),
                    trackID: item.string(4)
                ))
            }
        }
        return QueueInfo(playlistName: desc.string(1), items: items)
    }

    func playQueueItem(at index: Int) {
        runner.fire(command("play track \(index) of current playlist"), cache: false)
    }

    /// AppleScript espera punto decimal, sin importar el idioma del sistema.
    static func number(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

// MARK: - Spotify

final class SpotifySource: MediaSource {
    let kind = SourceKind.spotify

    private let stateScript = """
        if application id "com.spotify.client" is not running then return {"stopped"}
        tell application id "com.spotify.client"
        \tset st to "stopped"
        \tif player state is playing then
        \t\tset st to "playing"
        \telse if player state is paused then
        \t\tset st to "paused"
        \tend if
        \tif st is "stopped" then return {"stopped"}
        \tset nm to ""
        \tset ar to ""
        \tset al to ""
        \tset du to 0
        \tset tid to ""
        \tset aw to ""
        \ttry
        \t\tset t to current track
        \t\tset nm to name of t
        \t\tset ar to artist of t
        \t\tset al to album of t
        \t\tset du to (duration of t) / 1000
        \t\tset tid to id of t
        \t\tset aw to artwork url of t
        \tend try
        \tset pos to 0
        \ttry
        \t\tset pos to player position
        \tend try
        \tset rp to "off"
        \tif repeating then set rp to "all"
        \treturn {st, nm, ar, al, du, pos, tid, sound volume, shuffling, rp, false, aw}
        end tell
        """

    func fetchState() -> Result<PlayerState?, AppleScriptRunner.Failure> {
        guard kind.isInstalled, kind.isRunning else { return .success(nil) }
        return runner.run(stateScript).map { parse($0) }
    }

    /// Spotify no da la imagen, da una URL (la baja el controlador).
    func fetchEmbeddedArtwork() -> NSImage? { nil }

    func playPause() { runner.fire(command("playpause")) }
    func next() { runner.fire(command("next track")) }
    // Spotify salta directo a la anterior; la app hace lo de Music: pasados 3 s, vuelve al principio.
    func previous(currentPosition: Double) {
        if currentPosition > 3 {
            seek(to: 0)
        } else {
            runner.fire(command("previous track"))
        }
    }
    func seek(to seconds: Double) {
        runner.fire(command("set player position to \(MusicSource.number(seconds))"), cache: false)
    }
    func setVolume(_ volume: Int) {
        runner.fire(command("set sound volume to \(min(100, max(0, volume)))"), cache: false)
    }
    func setShuffle(_ on: Bool) { runner.fire(command("set shuffling to \(on)")) }
    // Spotify sólo tiene repetir sí o no (no distingue "una" de "todas").
    func setRepeat(_ mode: RepeatMode) { runner.fire(command("set repeating to \(mode != .off)")) }
    func setFavorite(_ on: Bool) {}

    /// Spotify no expone la cola por AppleScript.
    func fetchQueue() -> QueueInfo? { nil }
    func playQueueItem(at index: Int) {}
}
