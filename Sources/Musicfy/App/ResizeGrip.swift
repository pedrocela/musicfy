import AppKit
import os

/// Resize diagnostics: `log show --predicate 'subsystem == "com.pedrocela.musicfy"' --last 5m`
let resizeLog = Logger(subsystem: "com.pedrocela.musicfy", category: "resize")

/// Window edges and corners that can be pulled to resize.
struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let top = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)
    static let all: ResizeEdges = [.left, .right, .top, .bottom]
}

/// Invisible layer over the player that only claims the edges (10 pt) and corners (22 pt):
/// there the cursor changes and dragging resizes. Everything else passes through to the
/// UI below. The window is borderless, so this does by hand what a title bar window gets free.
final class ResizeGripView: NSView {
    /// Which edges can be pulled in the current mode (empty: none).
    var allowedEdges: () -> ResizeEdges = { [] }
    var onBegin: () -> Void = {}
    /// Gets the edges and how far the mouse moved since mouse down. Returns `false`
    /// to end the gesture (for example, because the mode changed).
    var onResize: (ResizeEdges, CGFloat, CGFloat) -> Bool = { _, _, _ in true }
    var onEnd: () -> Void = {}

    /// Wide enough to find without hunting: a borderless window has no grab area outside it.
    private let edgeWidth: CGFloat = 10
    /// Covers the 16 pt rounded corners with room to spare.
    private let cornerSize: CGFloat = 22
    private var active: ResizeEdges = []
    private(set) var tracking = false
    private var startMouse = NSPoint.zero
    private var shownEdges: ResizeEdges = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return edges(at: local).isEmpty ? nil : self
    }

    private func edges(at point: NSPoint) -> ResizeEdges {
        let allowed = allowedEdges()
        guard !allowed.isEmpty, bounds.contains(point) else { return [] }
        var found: ResizeEdges = []
        let nearLeft = point.x < cornerSize, nearRight = point.x > bounds.maxX - cornerSize
        let nearBottom = point.y < cornerSize, nearTop = point.y > bounds.maxY - cornerSize
        if (nearLeft || nearRight), (nearTop || nearBottom) {
            // Corner: both edges, if both are allowed; otherwise whichever one is.
            let horizontal: ResizeEdges = nearLeft ? .left : .right
            let vertical: ResizeEdges = nearTop ? .top : .bottom
            let corner = ResizeEdges([horizontal, vertical]).intersection(allowed)
            if corner == [horizontal, vertical] { return corner }
            // Only one side allowed: it still counts if the point is within that side's band.
            if allowed.contains(vertical), nearTop ? point.y > bounds.maxY - edgeWidth : point.y < edgeWidth { return vertical }
            if allowed.contains(horizontal), nearLeft ? point.x < edgeWidth : point.x > bounds.maxX - edgeWidth { return horizontal }
            return []
        }
        if point.x < edgeWidth { found.insert(.left) }
        if point.x > bounds.maxX - edgeWidth { found.insert(.right) }
        if point.y < edgeWidth { found.insert(.bottom) }
        if point.y > bounds.maxY - edgeWidth { found.insert(.top) }
        return found.intersection(allowed)
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard !tracking else { return }
        showCursor(for: edges(at: convert(event.locationInWindow, from: nil)))
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !tracking else { return }
        showCursor(for: edges(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        guard !tracking else { return }
        showCursor(for: [])
    }

    /// Called by the app's mouse poll too: a background app's cursor gets reset by the
    /// frontmost app, so it's set again while the pointer sits on an edge.
    func refreshCursor(atScreenPoint point: NSPoint) {
        guard !tracking, let window else { return }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        showCursor(for: edges(at: local), force: true)
    }

    private func showCursor(for edges: ResizeEdges, force: Bool = false) {
        if edges.isEmpty {
            if !shownEdges.isEmpty { NSCursor.arrow.set() }
        } else if force || edges != shownEdges {
            Self.cursor(for: edges).set()
        }
        shownEdges = edges
    }

    private static func cursor(for edges: ResizeEdges) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch edges {
            case [.top, .left]: position = .topLeft
            case [.top, .right]: position = .topRight
            case [.bottom, .left]: position = .bottomLeft
            case [.bottom, .right]: position = .bottomRight
            case .top: position = .top
            case .bottom: position = .bottom
            case .left: position = .left
            default: position = .right
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        if edges == .top || edges == .bottom { return .resizeUpDown }
        if edges == .left || edges == .right { return .resizeLeftRight }
        return .crosshair
    }

    // MARK: Dragging

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        active = edges(at: point)
        resizeLog.notice("down at \(Int(point.x), privacy: .public),\(Int(point.y), privacy: .public) in \(Int(self.bounds.width), privacy: .public)x\(Int(self.bounds.height), privacy: .public) edges=\(self.active.rawValue, privacy: .public) allowed=\(self.allowedEdges().rawValue, privacy: .public)")
        guard !active.isEmpty else { return }
        tracking = true
        startMouse = NSEvent.mouseLocation
        Self.cursor(for: active).set()
        onBegin()
    }

    override func mouseDragged(with event: NSEvent) {
        guard tracking else { return }
        Self.cursor(for: active).set()
        let mouse = NSEvent.mouseLocation
        if !onResize(active, mouse.x - startMouse.x, mouse.y - startMouse.y) {
            finish()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if tracking { finish() }
    }

    private func finish() {
        tracking = false
        active = []
        shownEdges = []
        NSCursor.arrow.set()
        onEnd()
    }
}

/// Lets this background app own the cursor while the pointer is over its window.
/// Musicfy never becomes the active app (it would steal focus), and macOS normally
/// ignores cursor changes from inactive apps. Floating utilities flip this private
/// window-server property for that; it's looked up at runtime and skipped if missing.
enum BackgroundCursor {
    static func enable() {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let everywhere = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT: every loaded image
        guard
            let connectionSymbol = dlsym(everywhere, "_CGSDefaultConnection"),
            let setSymbol = dlsym(everywhere, "CGSSetConnectionProperty")
        else { return }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setSymbol, to: SetProperty.self)
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
