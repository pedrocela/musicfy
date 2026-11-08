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

    var actions = PanelActions()
}

/// Lo que la interfaz le pide a la app; lo resuelve el AppDelegate.
struct PanelActions {
    var setMode: (DisplayMode) -> Void = { _ in }
    var toggleArtworkCompact: () -> Void = {}
    var hide: () -> Void = {}
    var showMenu: () -> Void = {}
    var showOutputMenu: () -> Void = {}
}
