import AppKit

/// Bordes y esquinas de la ventana desde donde se cambia el tamaño.
struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let top = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)
    static let all: ResizeEdges = [.left, .right, .top, .bottom]
}

/// Capa invisible encima del player que toma sólo los bordes (5 pt) y las esquinas (12 pt):
/// ahí cambia el cursor y arrastrar cambia el tamaño. Todo lo demás pasa de largo
/// a la interfaz de abajo. La ventana no tiene marco, así que esto lo hace a mano.
final class ResizeGripView: NSView {
    /// Qué bordes se pueden tirar en el modo actual (vacío: ninguno).
    var allowedEdges: () -> ResizeEdges = { [] }
    var onBegin: () -> Void = {}
    /// Recibe el borde y cuánto se movió el mouse desde que se apretó. Devuelve `false`
    /// para cortar el gesto (por ejemplo, porque cambió de modo).
    var onResize: (ResizeEdges, CGFloat, CGFloat) -> Bool = { _, _, _ in true }
    var onEnd: () -> Void = {}

    private let edgeWidth: CGFloat = 5
    private let cornerSize: CGFloat = 12
    private var active: ResizeEdges = []
    private var tracking = false
    private var startMouse = NSPoint.zero
    private var showingCursor = false

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
        // Esquinas: zona más grande.
        if (nearLeft || nearRight), (nearTop || nearBottom) {
            found.insert(nearLeft ? .left : .right)
            found.insert(nearTop ? .top : .bottom)
        } else {
            if point.x < edgeWidth { found.insert(.left) }
            if point.x > bounds.maxX - edgeWidth { found.insert(.right) }
            if point.y < edgeWidth { found.insert(.bottom) }
            if point.y > bounds.maxY - edgeWidth { found.insert(.top) }
        }
        found.formIntersection(allowed)
        return found
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard !tracking else { return }
        updateCursor(for: edges(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        guard !tracking else { return }
        updateCursor(for: [])
    }

    private func updateCursor(for edges: ResizeEdges) {
        if edges.isEmpty {
            if showingCursor { NSCursor.arrow.set() }
            showingCursor = false
        } else {
            Self.cursor(for: edges).set()
            showingCursor = true
        }
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

    // MARK: Arrastre

    override func mouseDown(with event: NSEvent) {
        active = edges(at: convert(event.locationInWindow, from: nil))
        guard !active.isEmpty else { return }
        tracking = true
        startMouse = NSEvent.mouseLocation
        onBegin()
    }

    override func mouseDragged(with event: NSEvent) {
        guard tracking else { return }
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
        updateCursor(for: [])
        onEnd()
    }
}
