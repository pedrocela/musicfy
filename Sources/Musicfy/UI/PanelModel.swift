import SwiftUI

/// Estado de la ventana (no de la música): modo visible, mouse encima, volumen abierto.
@MainActor
final class PanelModel: ObservableObject {
    /// El modo que se ve ahora. Puede diferir del elegido en Ajustes
    /// (por ejemplo, la tapa pasa a compacto cuando no suena nada).
    @Published var mode: DisplayMode = .artwork
    @Published var isHovering = false
    @Published var volumeOpen = false
    @Published var islandExpanded = false
    /// Panel que se abre debajo del player (tapa y compacto), como en Music.
    @Published var drawer: Drawer = .none
    /// Dónde se pega la Isla en el borde de arriba.
    @Published var islandAlignment: IslandAlignment =
        IslandAlignment(rawValue: UserDefaults.standard.string(forKey: "islandAlignment") ?? "") ?? .center {
        didSet { UserDefaults.standard.set(islandAlignment.rawValue, forKey: "islandAlignment") }
    }

    var actions = PanelActions()
}

enum IslandAlignment: String {
    case leading, center, trailing

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

enum Drawer: Equatable {
    case none, lyrics, queue
}

/// Lo que la interfaz le pide a la app; lo resuelve el AppDelegate.
struct PanelActions {
    var setMode: (DisplayMode) -> Void = { _ in }
    var toggleArtworkCompact: () -> Void = {}
    var hide: () -> Void = {}
    var showMenu: () -> Void = {}
    var showOutputMenu: () -> Void = {}
}
