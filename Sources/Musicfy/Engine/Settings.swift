import Foundation

enum IdleBehavior: String, CaseIterable {
    /// Stays visible, paused, with the last song.
    case stay
    /// Hides after 30 s without music and comes back when something plays.
    case hide
    /// Keeps its mode and size, and fades to half opacity after a while paused.
    /// Full opacity again on hover or when music starts.
    case fade

    var label: String {
        switch self {
        case .stay: return "Stay Visible"
        case .hide: return "Hide Automatically"
        case .fade: return "Fade When Paused"
        }
    }
}

/// The user's preferences, stored in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var mode: DisplayMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    /// `nil` = automatic: the last app that started playing.
    @Published var forcedSource: SourceKind? { didSet { defaults.set(forcedSource?.rawValue, forKey: "forcedSource") } }
    @Published var showVolume: Bool { didSet { defaults.set(showVolume, forKey: "showVolume") } }
    @Published var showOutput: Bool { didSet { defaults.set(showOutput, forKey: "showOutput") } }
    @Published var showLyricsButton: Bool { didSet { defaults.set(showLyricsButton, forKey: "showLyricsButton") } }
    @Published var showQueueButton: Bool { didSet { defaults.set(showQueueButton, forKey: "showQueueButton") } }
    @Published var idleBehavior: IdleBehavior { didSet { defaults.set(idleBehavior.rawValue, forKey: "idleBehavior") } }
    /// Off by default: a full-screen video or app has the screen to itself.
    @Published var showOverFullScreen: Bool { didSet { defaults.set(showOverFullScreen, forKey: "showOverFullScreen") } }

    init() {
        defaults.register(defaults: [
            "mode": DisplayMode.artwork.rawValue,
            "showVolume": true,
            "showOutput": true,
            "showLyricsButton": true,
            "showQueueButton": true,
            "idleBehavior": IdleBehavior.fade.rawValue,
            "showOverFullScreen": false,
        ])
        mode = DisplayMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .artwork
        forcedSource = defaults.string(forKey: "forcedSource").flatMap(SourceKind.init(rawValue:))
        showVolume = defaults.bool(forKey: "showVolume")
        showOutput = defaults.bool(forKey: "showOutput")
        showLyricsButton = defaults.bool(forKey: "showLyricsButton")
        showQueueButton = defaults.bool(forKey: "showQueueButton")
        // "compact" was the old "Shrink When Paused": it now fades instead.
        let storedIdle = defaults.string(forKey: "idleBehavior")
        idleBehavior = storedIdle == "compact" ? .fade : IdleBehavior(rawValue: storedIdle ?? "") ?? .fade
        showOverFullScreen = defaults.bool(forKey: "showOverFullScreen")
    }
}
