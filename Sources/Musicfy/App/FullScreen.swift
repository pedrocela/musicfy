import AppKit

/// Finds full-screen windows: a video or app that has a whole display to itself.
/// Reads only window bounds, owners and layers, which needs no permission.
enum FullScreen {
    /// The displays (Cocoa coordinates) on which the frontmost app has a window
    /// exactly the size of the display.
    static func coveredScreens() -> [NSRect] {
        guard
            let front = NSWorkspace.shared.frontmostApplication,
            front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let primary = NSScreen.screens.first
        else { return [] }
        let pid = front.processIdentifier
        let screens = NSScreen.screens.map(\.frame)
        var covered: [NSRect] = []
        for info in list {
            guard
                (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { continue }
            // Window bounds have their origin at the top left of the main display.
            let cocoa = NSRect(
                x: bounds.minX,
                y: primary.frame.maxY - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
            for screen in screens where !covered.contains(screen) && cocoa.isAlmostEqual(to: screen) {
                covered.append(screen)
            }
        }
        return covered
    }

    /// Whether a full-screen window sits on the display that holds `frame`.
    static func covers(_ frame: NSRect) -> Bool {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return coveredScreens().contains { $0.contains(center) }
    }
}

private extension NSRect {
    func isAlmostEqual(to other: NSRect) -> Bool {
        abs(minX - other.minX) < 1 && abs(minY - other.minY) < 1
            && abs(width - other.width) < 1 && abs(height - other.height) < 1
    }
}
