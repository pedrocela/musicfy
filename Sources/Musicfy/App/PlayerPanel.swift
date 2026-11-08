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

    // MARK: - Hidden without leaving the screen

    /// When a full-screen Space closes, macOS moves every ordered-out window of the app to
    /// the first desktop and keeps it there for good, even one that asked for every Space;
    /// setting the collection behavior again doesn't undo it. A window that stays ordered
    /// in (at alpha 0) keeps every Space. So hiding the player never orders it out: it goes
    /// transparent and click-through, and `isShown` says whether it is really showing.
    private(set) var concealed = false

    /// On screen and not hidden. Use this, not `isVisible` (true while concealed).
    var isShown: Bool { isVisible && !concealed }

    override func orderOut(_ sender: Any?) {
        guard isVisible, !concealed else { return }
        concealed = true
        alphaValue = 0
        super.ignoresMouseEvents = true
        if isKeyWindow {
            // Give the keyboard back: a key panel would keep catching keys while invisible.
            super.orderOut(nil)
            super.orderFrontRegardless()
        }
    }

    override func orderFrontRegardless() {
        reveal()
        super.orderFrontRegardless()
    }

    override func orderFront(_ sender: Any?) {
        reveal()
        super.orderFront(sender)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        reveal()
        super.makeKeyAndOrderFront(sender)
    }

    private func reveal() {
        guard concealed else { return }
        concealed = false
        super.ignoresMouseEvents = false
    }

    /// Hidden, it lets every click through, whatever the hover logic asks for.
    override var ignoresMouseEvents: Bool {
        get { super.ignoresMouseEvents }
        set { super.ignoresMouseEvents = concealed || newValue }
    }

    /// Ordered in but left on one desktop only (pinned by macOS before this fix, or by
    /// anything else): it can't be freed, only replaced by a new window.
    var isPinnedToOneSpace: Bool { isVisible && !isOnActiveSpace }

    /// Playback keys while the player has the keyboard.
    var onPlaybackKey: ((PlaybackKey) -> Void)?

    // Can take the keyboard without activating the app.
    override var canBecomeKey: Bool { !concealed }
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
