import AppKit

/// The two apps Musicfy can read and control.
enum SourceKind: String, CaseIterable, Identifiable {
    case music
    case spotify

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Spotify doesn't expose "like" through AppleScript; Music does (favorite).
    var supportsFavorite: Bool { self == .music }
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

    var subtitle: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " — ")
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
