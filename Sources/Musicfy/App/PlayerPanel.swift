import AppKit
import SwiftUI

/// Ventana sin marco que flota sobre todo: todas las apps, todos los escritorios
/// y también sobre apps en pantalla completa. No le roba el foco a nadie.
final class PlayerPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Theme.artworkSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        becomesKeyOnlyIfNeeded = true
    }

    // Puede tomar el teclado sin activar la app (para los menús y las barras).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// El primer clic sobre el player ya cuenta, aunque la ventana no tenga el foco.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
