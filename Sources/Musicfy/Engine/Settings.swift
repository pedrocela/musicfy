import Foundation

enum IdleBehavior: String, CaseIterable {
    /// Queda visible, en pausa, con la última canción.
    case stay
    /// Se esconde a los 30 s sin música y vuelve cuando algo suena.
    case hide
    /// Pasa a la tira compacta y vuelve a la tapa cuando arranca la música.
    case compact

    var label: String {
        switch self {
        case .stay: return "Quedarse a la vista"
        case .hide: return "Esconderse solo"
        case .compact: return "Pasar a compacto"
        }
    }
}

/// Preferencias del usuario, guardadas en UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var mode: DisplayMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    /// `nil` = automático: la última app que empezó a sonar.
    @Published var forcedSource: SourceKind? { didSet { defaults.set(forcedSource?.rawValue, forKey: "forcedSource") } }
    @Published var showVolume: Bool { didSet { defaults.set(showVolume, forKey: "showVolume") } }
    @Published var showOutput: Bool { didSet { defaults.set(showOutput, forKey: "showOutput") } }
    @Published var showLyricsButton: Bool { didSet { defaults.set(showLyricsButton, forKey: "showLyricsButton") } }
    @Published var idleBehavior: IdleBehavior { didSet { defaults.set(idleBehavior.rawValue, forKey: "idleBehavior") } }

    init() {
        defaults.register(defaults: [
            "mode": DisplayMode.artwork.rawValue,
            "showVolume": true,
            "showOutput": true,
            "showLyricsButton": true,
            "idleBehavior": IdleBehavior.compact.rawValue,
        ])
        mode = DisplayMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .artwork
        forcedSource = defaults.string(forKey: "forcedSource").flatMap(SourceKind.init(rawValue:))
        showVolume = defaults.bool(forKey: "showVolume")
        showOutput = defaults.bool(forKey: "showOutput")
        showLyricsButton = defaults.bool(forKey: "showLyricsButton")
        idleBehavior = IdleBehavior(rawValue: defaults.string(forKey: "idleBehavior") ?? "") ?? .compact
    }
}
