import AppKit

/// Las dos apps que Musicfy sabe leer y controlar.
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

    /// Spotify no expone "me gusta" por AppleScript; Music sí (favorito).
    var supportsFavorite: Bool { self == .music }
}

enum RepeatMode: String {
    case off, all, one
}

enum DisplayMode: String, CaseIterable {
    /// La tapa grande, con los controles encima al pasar el mouse.
    case artwork
    /// La tira compacta: miniatura, título y controles.
    case compact
    /// Una cápsula arriba al centro de la pantalla que se abre al pasar el mouse.
    case island

    var label: String {
        switch self {
        case .artwork: return "Tapa"
        case .compact: return "Compacto"
        case .island: return "Isla"
        }
    }
}

/// Lo que está sonando en una app, tal como lo devuelve su AppleScript.
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

    /// Identifica la canción para saber cuándo hay que traer otra tapa o letra.
    var trackKey: String {
        trackID.isEmpty ? "\(source.rawValue)|\(title)|\(artist)|\(album)" : "\(source.rawValue)|\(trackID)"
    }
}

/// Por qué una app no se pudo leer.
enum SourceProblem: Equatable {
    case notAuthorized
}

/// Lo que sigue en la lista que está sonando (sólo Music lo deja leer).
struct QueueInfo: Equatable {
    struct Item: Equatable, Identifiable {
        /// Posición en la lista de Music (para mandarla a sonar).
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
