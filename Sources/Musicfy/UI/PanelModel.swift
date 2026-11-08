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

    /// Lado del modo tapa, que se agranda tirando de un borde. Se recuerda.
    @Published var artworkSide: CGFloat = PanelModel.savedArtworkSide {
        didSet { UserDefaults.standard.set(Double(artworkSide), forKey: "artworkSide") }
    }

    /// Cambio de modo con fundido: la vista vieja se achica y se va, la nueva llega con un resorte.
    @Published var swapOut = false
    /// Se está arrastrando la tapa o el compacto sobre la zona de la Isla (arriba al centro).
    @Published var islandHint = false
    /// La Isla se está tirando hacia abajo: de 0 a 1, cuánto falta para que se vuelva tapa.
    @Published var islandPull: CGFloat = 0

    var actions = PanelActions()

    private static var savedArtworkSide: CGFloat {
        let saved = UserDefaults.standard.double(forKey: "artworkSide")
        let side = saved > 0 ? CGFloat(saved) : Theme.artworkSize.width
        return min(max(side, Theme.artworkSideRange.lowerBound), Theme.artworkSideRange.upperBound)
    }
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
