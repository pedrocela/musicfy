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
        if source == .podcasts { return podcastSubtitle }
        let parts = album.caseInsensitiveCompare(artist) == .orderedSame ? [artist] : [artist, album]
        return parts.filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// Podcasts reports the show as the artist and the episode's date as the album
    /// ("6 November 2026"): the show, then a short date ("6 Nov", with the year only if
    /// it isn't this one). Anything else in the album is left out.
    private var podcastSubtitle: String {
        let show = artist.isEmpty ? album : artist
        guard !artist.isEmpty, let date = Self.episodeDate(album) else { return show }
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let style = Date.FormatStyle().day().month(.abbreviated)
        return "\(show) · " + (sameYear ? date.formatted(style) : date.formatted(style.year()))
    }

    private static func episodeDate(_ text: String) -> Date? {
        guard !text.isEmpty, text.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        for locale in [Locale.current, Locale(identifier: "en_US_POSIX")] {
            for style in [DateFormatter.Style.long, .medium, .full] {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.dateStyle = style
                formatter.timeStyle = .none
                if let date = formatter.date(from: text) { return date }
            }
            let formatter = DateFormatter()
            formatter.locale = locale
            for format in ["d MMMM yyyy", "MMMM d, yyyy", "d MMM yyyy", "MMM d, yyyy"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: text) { return date }
            }
        }
        return nil
    }

    /// Identifies the album (for Podcasts, the show): the artwork only animates when this changes.
    var albumKey: String {
        let group = source == .podcasts ? (artist.isEmpty ? album : artist) : "\(artist)|\(album)"
        let key = group.trimmingCharacters(in: .whitespaces).lowercased()
        return key.isEmpty || key == "|" ? trackKey : "\(source.rawValue)|\(key)"
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
