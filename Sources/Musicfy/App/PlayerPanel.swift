import AppKit
import SwiftUI

/// Borderless window that floats above everything: every app, every Space and
/// full-screen apps too. It never steals focus.
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
        showsOverFullScreen = false
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

    /// On every Space; over full-screen apps and videos only if asked. Managed: it joins
    /// the Mission Control spread like any window (stationary kept it frozen in place).
    var showsOverFullScreen: Bool {
        get { collectionBehavior.contains(.fullScreenAuxiliary) }
        set {
            collectionBehavior = newValue
                ? [.canJoinAllSpaces, .fullScreenAuxiliary, .managed, .ignoresCycle]
                : [.canJoinAllSpaces, .managed, .ignoresCycle]
        }
    }

    // Can take the keyboard without activating the app (for menus and sliders).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The first click on the player counts, even when the window isn't focused.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
