import AppKit

/// A music app driven by AppleScript.
///
/// Every script starts with `if application id … is running`, so Musicfy never
/// launches Music or Spotify on its own (a bare `tell` would).
protocol MediaSource: AnyObject {
    var kind: SourceKind { get }

    /// Runs on the AppleScript queue. `nil` = closed or stopped.
    func fetchState() -> Result<PlayerState?, AppleScriptRunner.Failure>

    /// Runs on the AppleScript queue. Embedded artwork, if the app provides it.
    func fetchEmbeddedArtwork() -> NSImage?

    func playPause()
    func next()
    func previous(currentPosition: Double)
    func seek(to seconds: Double)
    func setVolume(_ volume: Int)
    func setShuffle(_ on: Bool)
    func setRepeat(_ mode: RepeatMode)
    func setFavorite(_ on: Bool)

    /// Runs on the AppleScript queue. `nil` if the app doesn't expose its queue.
    func fetchQueue() -> QueueInfo?
    func playQueueItem(at index: Int)
}

extension MediaSource {
    var runner: AppleScriptRunner { .shared }

    /// Wraps a command so it doesn't launch the app when it's closed.
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

    /// Music renamed `loved` to `favorited`. Use whichever compiles on this Mac.
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
        \tset mfSt to "stopped"
        \tif player state is playing or player state is fast forwarding or player state is rewinding then
        \t\tset mfSt to "playing"
        \telse if player state is paused then
        \t\tset mfSt to "paused"
        \tend if
        \tif mfSt is "stopped" then return {"stopped"}
        \tset mfNm to ""
        \tset mfAr to ""
        \tset mfAl to ""
        \tset mfDu to 0
        \tset mfTid to ""
        \tset mfFav to false
        \ttry
        \t\tset mfT to current track
        \t\tset mfNm to name of mfT
        \t\tset mfAr to artist of mfT
        \t\tset mfAl to album of mfT
        \t\tset mfDu to duration of mfT
        \t\tset mfTid to persistent ID of mfT
        \t\tset mfFav to \(favoriteProperty) of mfT
        \tend try
        \tif mfNm is "" then
        \t\ttry
        \t\t\tset mfNm to current stream title
        \t\tend try
        \tend if
        \tset mfPos to 0
        \ttry
        \t\tset mfPos to player position
        \tend try
        \tset mfRp to "off"
        \tif song repeat is all then
        \t\tset mfRp to "all"
        \telse if song repeat is one then
        \t\tset mfRp to "one"
        \tend if
        \treturn {mfSt, mfNm, mfAr, mfAl, mfDu, mfPos, mfTid, sound volume, shuffle enabled, mfRp, mfFav, ""}
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
    // `back track` does what Music's button does: back to the start, or to the previous song.
    func previous(currentPosition: Double) { runner.fire(command("back track")) }
    func seek(to seconds: Double) {
        runner.fire(command("set player position to \(Self.number(seconds))"), cache: false)
    }
    func setVolume(_ volume: Int) {
        runner.fire(command("set sound volume to \(min(100, max(0, volume)))")) // 101 variants at most: worth caching
    }
    func setShuffle(_ on: Bool) { runner.fire(command("set shuffle enabled to \(on)")) }
    func setRepeat(_ mode: RepeatMode) { runner.fire(command("set song repeat to \(mode.rawValue)")) }
    func setFavorite(_ on: Bool) {
        runner.queue.async {
            _ = self.runner.run(self.command("set \(self.favoriteProperty) of current track to \(on)"))
        }
    }

    /// The next songs in the playlist being played. Music doesn't expose its real
    /// Up Next; this is what follows in the album or playlist.
    private let queueScript = """
        if application id "com.apple.Music" is not running then return {}
        tell application id "com.apple.Music"
        \ttry
        \t\tset mfPl to current playlist
        \t\tset mfPlName to name of mfPl
        \t\tset mfIdx to index of current track
        \t\tset mfTotal to count of tracks of mfPl
        \ton error
        \t\treturn {}
        \tend try
        \tset mfLastIndex to mfIdx + 30
        \tif mfLastIndex > mfTotal then set mfLastIndex to mfTotal
        \tset mfRows to {}
        \trepeat with mfI from (mfIdx + 1) to mfLastIndex
        \t\ttry
        \t\t\tset mfT to track mfI of mfPl
        \t\t\tset end of mfRows to {name of mfT, artist of mfT, album of mfT, persistent ID of mfT, mfI}
        \t\tend try
        \tend repeat
        \treturn {mfPlName, mfRows}
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

    /// AppleScript wants a decimal point, whatever the system's language.
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
        \tset mfSt to "stopped"
        \tif player state is playing then
        \t\tset mfSt to "playing"
        \telse if player state is paused then
        \t\tset mfSt to "paused"
        \tend if
        \tif mfSt is "stopped" then return {"stopped"}
        \tset mfNm to ""
        \tset mfAr to ""
        \tset mfAl to ""
        \tset mfDu to 0
        \tset mfTid to ""
        \tset mfAw to ""
        \ttry
        \t\tset mfT to current track
        \t\tset mfNm to name of mfT
        \t\tset mfAr to artist of mfT
        \t\tset mfAl to album of mfT
        \t\tset mfDu to (duration of mfT) / 1000
        \t\tset mfTid to id of mfT
        \t\tset mfAw to artwork url of mfT
        \tend try
        \tset mfPos to 0
        \ttry
        \t\tset mfPos to player position
        \tend try
        \tset mfRp to "off"
        \tif repeating then set mfRp to "all"
        \treturn {mfSt, mfNm, mfAr, mfAl, mfDu, mfPos, mfTid, sound volume, shuffling, mfRp, false, mfAw}
        end tell
        """

    func fetchState() -> Result<PlayerState?, AppleScriptRunner.Failure> {
        guard kind.isInstalled, kind.isRunning else { return .success(nil) }
        return runner.run(stateScript).map { parse($0) }
    }

    /// Spotify gives a URL, not the image (the controller downloads it).
    func fetchEmbeddedArtwork() -> NSImage? { nil }

    func playPause() { runner.fire(command("playpause")) }
    func next() { runner.fire(command("next track")) }
    // Spotify jumps straight to the previous song; this does what Music does: after 3 s, restart the song.
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
        runner.fire(command("set sound volume to \(min(100, max(0, volume)))")) // 101 variants at most: worth caching
    }
    func setShuffle(_ on: Bool) { runner.fire(command("set shuffling to \(on)")) }
    // Spotify only has repeat on or off (no "one" versus "all").
    func setRepeat(_ mode: RepeatMode) { runner.fire(command("set repeating to \(mode != .off)")) }
    func setFavorite(_ on: Bool) {}

    /// Spotify doesn't expose its queue through AppleScript.
    func fetchQueue() -> QueueInfo? { nil }
    func playQueueItem(at index: Int) {}
}
