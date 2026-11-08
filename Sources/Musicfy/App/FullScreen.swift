import AppKit
import IOKit.pwr_mgt

/// Finds full-screen windows: a video or app that has a whole display to itself, and
/// tells a video apart from an app. Reads only window bounds, owners and layers, and
/// the system's power assertions, which needs no permission.
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

    /// The frontmost app, if it has a full-screen window on the display that holds `frame`.
    static func app(covering frame: NSRect) -> NSRunningApplication? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard coveredScreens().contains(where: { $0.contains(center) }) else { return nil }
        return NSWorkspace.shared.frontmostApplication
    }

    /// Whether `app` is playing video: players and browsers keep the display awake while
    /// a video plays, and an app like an editor or a chat doesn't.
    static func isPlayingVideo(_ app: NSRunningApplication) -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == KERN_SUCCESS,
              let byProcess = raw?.takeRetainedValue() as NSDictionary?
        else { return false }
        let front = app.processIdentifier
        let frontID = app.bundleIdentifier ?? ""
        for (key, value) in byProcess {
            guard let owner = (key as? NSNumber)?.int32Value,
                  let assertions = value as? [NSDictionary]
            else { continue }
            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String,
                      type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion"
                else { continue }
                if let level = (assertion["AssertLevel"] as? NSNumber)?.intValue, level == 0 { continue }
                let onBehalf = (assertion["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value
                if owner == front || onBehalf == front || belongs(owner, to: frontID) { return true }
            }
        }
        return false
    }

    /// Helper processes count as the app: Chrome plays in `com.google.Chrome.helper…`,
    /// Safari in WebKit's own processes.
    private static func belongs(_ pid: pid_t, to bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        var owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        if owner.isEmpty {
            var name = [CChar](repeating: 0, count: 64)
            if proc_name(pid, &name, UInt32(name.count)) > 0 { owner = String(cString: name) }
        }
        if owner.hasPrefix(bundleID + ".") { return true }
        return owner.hasPrefix("com.apple.WebKit") && bundleID.hasPrefix("com.apple.Safari")
    }
}

private extension NSRect {
    func isAlmostEqual(to other: NSRect) -> Bool {
        abs(minX - other.minX) < 1 && abs(minY - other.minY) < 1
            && abs(width - other.width) < 1 && abs(height - other.height) < 1
    }
}
