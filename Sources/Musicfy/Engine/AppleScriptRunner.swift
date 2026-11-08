import Foundation

/// Runs AppleScript on its own serial queue, off the main thread: a hung Music or the
/// permission dialog can't freeze the player.
///
/// Commands (play, volume, skip) jump the line: every script waiting to run first sends
/// the pending commands, so a button never waits behind a state read, the artwork or the
/// queue. At worst it waits for the one script already running.
final class AppleScriptRunner {
    static let shared = AppleScriptRunner()

    let queue = DispatchQueue(label: "musicfy.applescript", qos: .userInitiated)

    /// Only touched from `queue`.
    private var compiled: [String: NSAppleScript] = [:]
    private var sendingCommands = false
    /// Commands waiting to be sent, oldest first. Guarded by `lock`.
    private var pending: [(source: String, cache: Bool, completion: (() -> Void)?)] = []
    private let lock = NSLock()

    struct Failure: Error {
        let number: Int
        let message: String

        /// errAEEventNotPermitted: the user hasn't granted (or denied) the Automation permission.
        var isNotAuthorized: Bool { number == -1743 }
    }

    /// Compiles without running. Tells whether a script variant is valid in the installed
    /// Music (for example `favorited` versus `loved`).
    func compiles(_ source: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        if compiled[source] != nil { return true }
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return false }
        compiled[source] = script
        return true
    }

    /// Runs on the AppleScript queue, after any pending commands. `cache: false` for scripts
    /// with values baked in (position), not worth keeping compiled.
    func run(_ source: String, cache: Bool = true) -> Result<NSAppleEventDescriptor, Failure> {
        dispatchPrecondition(condition: .onQueue(queue))
        sendPendingCommands()
        return execute(source, cache: cache)
    }

    /// For commands without an answer: they go ahead of everything else waiting.
    func fire(_ source: String, cache: Bool = true, then completion: (() -> Void)? = nil) {
        lock.lock()
        pending.append((source, cache, completion))
        lock.unlock()
        queue.async { self.sendPendingCommands() }
    }

    private func sendPendingCommands() {
        guard !sendingCommands else { return }
        sendingCommands = true
        defer { sendingCommands = false }
        while true {
            lock.lock()
            let next = pending.isEmpty ? nil : pending.removeFirst()
            lock.unlock()
            guard let next else { return }
            _ = execute(next.source, cache: next.cache)
            if let completion = next.completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    private func execute(_ source: String, cache: Bool) -> Result<NSAppleEventDescriptor, Failure> {
        let script: NSAppleScript
        if cache, let hit = compiled[source] {
            script = hit
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return .failure(Failure(number: 0, message: "Couldn't create the script"))
            }
            var error: NSDictionary?
            guard fresh.compileAndReturnError(&error) else {
                return .failure(Self.failure(from: error))
            }
            if cache { compiled[source] = fresh }
            script = fresh
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return .failure(Self.failure(from: error)) }
        return .success(result)
    }

    private static func failure(from info: NSDictionary?) -> Failure {
        let number = (info?[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (info?[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
        return Failure(number: number, message: message)
    }
}

extension NSAppleEventDescriptor {
    /// Item of an AppleScript list (1-based), tolerant of `missing value`.
    func item(_ index: Int) -> NSAppleEventDescriptor? {
        guard index <= numberOfItems else { return nil }
        let item = atIndex(index)
        if item?.descriptorType == DescType(0x6E75_6C6C) { return nil } // 'null'
        if item?.descriptorType == DescType(0x6D73_6E67) { return nil } // 'msng' = missing value
        return item
    }

    func string(_ index: Int) -> String { item(index)?.stringValue ?? "" }
    func double(_ index: Int) -> Double { item(index)?.doubleValue ?? 0 }
    func int(_ index: Int) -> Int { Int(item(index)?.int32Value ?? 0) }
    func bool(_ index: Int) -> Bool { item(index)?.booleanValue ?? false }
}
