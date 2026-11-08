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
        // On every Space, full-screen ones too: whether it steps aside for a full-screen
        // video is the app's call (see FullScreen). Managed: it joins the Mission Control
        // spread like any window (stationary kept it frozen in place).
        collectionBehavior = Self.everySpace
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        // A click makes it key (without activating the app), so the keyboard
        // shortcuts below work right after clicking the player.
        becomesKeyOnlyIfNeeded = false
    }

    static let everySpace: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed, .ignoresCycle]

    /// When a full-screen Space closes, macOS moves every hidden window of the app (ordered
    /// out or at alpha 0) to the first desktop and keeps it there, even one that asked for
    /// every Space. Setting the behavior again before showing puts it back on all of them.
    func reassertAllSpaces() {
        collectionBehavior = []
        collectionBehavior = Self.everySpace
    }

    /// Same, for a player already on screen that got left behind on another desktop.
    func rejoinAllSpaces() {
        guard isVisible, !isOnActiveSpace else { return }
        reassertAllSpaces()
        let alpha = alphaValue
        orderOut(nil)
        orderFrontRegardless()
        alphaValue = alpha
    }

    /// Playback keys while the player has the keyboard.
    var onPlaybackKey: ((PlaybackKey) -> Void)?

    // Can take the keyboard without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Caught here, before any SwiftUI control, so Space never presses a focused button.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let key = PlaybackKey(event) {
            if !event.isARepeat { onPlaybackKey?(key) }
            return
        }
        super.sendEvent(event)
    }
}

/// Space = play/pause, ⌘← = previous, ⌘→ = next.
enum PlaybackKey {
    case playPause, previous, next

    init?(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, mods) {
        case (49, []): self = .playPause          // Space
        case (123, [.command]): self = .previous  // ⌘←
        case (124, [.command]): self = .next      // ⌘→
        default: return nil
        }
    }
}

/// The first click on the player counts, even when the window isn't focused.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
