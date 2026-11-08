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
        if handOffDrag(event) { return }
        super.sendEvent(event)
    }

    // MARK: - Dragging from anywhere

    /// A press that may turn into moving the window, if the mouse travels far enough.
    private var pendingDrag: NSEvent?
    /// How far the mouse travels before a press on a button becomes a drag.
    private let dragThreshold: CGFloat = 4

    /// Clicks go where they always went; a press that moves becomes a drag of the whole
    /// window, from wherever it started, except where something drags by itself: the
    /// background (it already moves the window), the resize edges and the scrub bars.
    private func handOffDrag(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            pendingDrag = event.clickCount == 1 && startsWindowDrag(at: event.locationInWindow) ? event : nil
        case .leftMouseDragged:
            guard let down = pendingDrag else { return false }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard hypot(dx, dy) >= dragThreshold, let surface = dragSurface(at: down.locationInWindow) else {
                return false
            }
            pendingDrag = nil
            cancelPress(like: event)
            surface.takeOverDrag(from: down)
            return true
        case .leftMouseUp:
            pendingDrag = nil
        default:
            break
        }
        return false
    }

    private func startsWindowDrag(at point: NSPoint) -> Bool {
        guard let frameView = contentView?.superview else { return false }
        let hit = frameView.hitTest(point)
        if hit is WindowDragSurface || hit is ResizeGripView { return false }
        return !views(of: NoWindowDrag.Marker.self).contains { $0.frameInWindow.contains(point) }
    }

    /// The topmost drag surface under the point, or else any one on the player.
    private func dragSurface(at point: NSPoint) -> WindowDragSurface? {
        let surfaces = views(of: NSView.self).compactMap { $0 as? WindowDragSurface }.filter { !$0.isHiddenOrHasHiddenAncestor }
        return surfaces.last { $0.frameInWindow.contains(point) } ?? surfaces.last
    }

    /// Lets go of the button under the press without clicking it: released far outside.
    private func cancelPress(like event: NSEvent) {
        guard let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: -10_000, y: -10_000),
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: 1,
            pressure: 0
        ) else { return }
        super.sendEvent(up)
    }

    private func views<T: NSView>(of type: T.Type) -> [T] {
        var found: [T] = []
        var stack: [NSView] = contentView.map { [$0] } ?? []
        while let view = stack.popLast() {
            if let match = view as? T { found.append(match) }
            stack.append(contentsOf: view.subviews.reversed())
        }
        return found
    }
}

private extension NSView {
    var frameInWindow: NSRect { convert(bounds, to: nil) }
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
