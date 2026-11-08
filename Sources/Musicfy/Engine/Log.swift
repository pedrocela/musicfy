import Foundation
import os

/// Where Musicfy writes what went wrong. Read it in Console.app (filter by
/// "com.pedrocela.musicfy") or from Terminal:
///   log stream --predicate 'subsystem == "com.pedrocela.musicfy"' --level debug
enum Log {
    static let subsystem = "com.pedrocela.musicfy"
    static let scripts = Logger(subsystem: subsystem, category: "applescript")
    static let podcasts = Logger(subsystem: subsystem, category: "podcasts")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let app = Logger(subsystem: subsystem, category: "app")
}

/// The build Musicfy was made from, stamped into Info.plist by build.sh.
enum BuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Short commit hash, with "-dirty" if there were uncommitted changes. Empty when unknown.
    static var commit: String {
        Bundle.main.object(forInfoDictionaryKey: "MusicfyCommit") as? String ?? ""
    }

    /// "Musicfy 0.1.0 (212 · e417ce5)".
    static var label: String {
        let detail = commit.isEmpty ? build : "\(build) · \(commit)"
        return "Musicfy \(version) (\(detail))"
    }
}
