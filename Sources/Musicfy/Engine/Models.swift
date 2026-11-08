import AppKit

/// The apps Musicfy can read and control.
enum SourceKind: String, CaseIterable, Identifiable {
    case music
    case spotify
    case podcasts

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .podcasts: return "com.apple.podcasts"
        }
    }

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .podcasts: return "Podcasts"
        }
    }

    /// Asking Launch Services is slow, and views ask on every render: the answer is kept
    /// until an app launches or quits (see `forgetInstalled`).
    var isInstalled: Bool {
        Self.installedLock.lock()
        defer { Self.installedLock.unlock() }
        if let known = Self.installed[self] { return known }
        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        Self.installed[self] = found
        return found
    }

    static func forgetInstalled() {
        installedLock.lock()
        installed = [:]
        installedLock.unlock()
    }

    private static var installed: [SourceKind: Bool] = [:]
    private static let installedLock = NSLock()

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Spotify doesn't expose "like" through AppleScript; Music does (favorite).
    var supportsFavorite: Bool { self == .music }

    /// Podcasts plays episodes: no app volume, shuffle, repeat, lyrics or queue, and the
    /// skip buttons jump back 15 s and ahead 30 s instead of changing songs.
    var isSpokenWord: Bool { self == .podcasts }
    var hasAppVolume: Bool { !isSpokenWord }
    var hasPlayModes: Bool { !isSpokenWord }
    var hasLyrics: Bool { !isSpokenWord }
    var hasQueue: Bool { !isSpokenWord }

    var previousSymbol: String { isSpokenWord ? "gobackward.15" : "backward.fill" }
    var nextSymbol: String { isSpokenWord ? "goforward.30" : "forward.fill" }
    var previousHelp: String { isSpokenWord ? "Back 15 Seconds" : "Previous" }
    var nextHelp: String { isSpokenWord ? "Forward 30 Seconds" : "Next" }
}

enum RepeatMode: String {
    case off, all, one
}

enum DisplayMode: String, CaseIterable {
    /// The large artwork, with controls on hover.
    case artwork
    /// The compact strip: thumbnail, title and controls.
    case compact
    /// A pill at the top center of the screen that opens on hover.
    case island

    var label: String {
        switch self {
        case .artwork: return "Artwork"
        case .compact: return "Compact"
        case .island: return "Island"
        }
    }
}

/// What an app is playing, as its AppleScript returns it.
struct PlayerState: Equatable {
    var source: SourceKind
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var trackID: String
    var volume: Int
    var shuffle: Bool
    var repeatMode: RepeatMode
    var favorited: Bool
    var artworkURL: URL?
    /// Changes when the app hands over new artwork for the same item (Podcasts sends the
    /// episode first and its artwork a moment later).
    var artworkTag: String = ""

    var subtitle: String {
        // A podcast's show is often both the artist and the album.
        let parts = album.caseInsensitiveCompare(artist) == .orderedSame ? [artist] : [artist, album]
        return parts.filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// Identifies the song, to know when to fetch new artwork or lyrics.
    var trackKey: String {
        trackID.isEmpty ? "\(source.rawValue)|\(title)|\(artist)|\(album)" : "\(source.rawValue)|\(trackID)"
    }
}

/// Why an app couldn't be read.
enum SourceProblem: Equatable {
    case notAuthorized
}

/// What follows in the playing list (only Music lets us read it).
struct QueueInfo: Equatable {
    struct Item: Equatable, Identifiable {
        /// Position in Music's list (to play it).
        let index: Int
        let title: String
        let artist: String
        let album: String
        let trackID: String

        var id: String { "\(index)|\(trackID)" }
        var subtitle: String { [artist, album].filter { !$0.isEmpty }.joined(separator: " — ") }
    }

    let playlistName: String
    let items: [Item]
}
