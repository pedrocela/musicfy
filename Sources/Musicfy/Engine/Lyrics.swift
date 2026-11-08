import Foundation
import os

/// Lyrics from LRCLIB (lrclib.net): free, no account, timed per line.
struct Lyrics: Equatable {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    /// Timed. Empty when there are only plain lyrics.
    let lines: [Line]
    let plain: String
    let instrumental: Bool

    var isSynced: Bool { !lines.isEmpty }

    /// Index of the line for `position` (in seconds).
    func index(at position: Double) -> Int? {
        guard isSynced else { return nil }
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// "[01:23.45] text" → Line(83.45, "text"). Ignores metadata tags.
    static func parseLRC(_ lrc: String) -> [Line] {
        var result: [Line] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                    times.append(minutes * 60 + seconds)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { result.append(Line(time: time, text: text)) }
        }
        return result.sorted { $0.time < $1.time }
    }
}

final class LyricsLoader {
    static let shared = LyricsLoader()

    private var cache: [String: Lyrics?] = [:]
    private let lock = NSLock()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "Musicfy/0.1 (https://github.com/pedrocela/musicfy)"]
        return URLSession(configuration: config)
    }()

    /// What one LRCLIB request found. `failed` (no network, a server error) is kept apart
    /// from `missing` so a dropped connection doesn't mark the song as having no lyrics.
    enum Lookup: Equatable {
        case found(Lyrics)
        case missing
        case failed
    }

    func lyrics(for state: PlayerState) async -> Lyrics? {
        let key = state.trackKey
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let first = await exact(state)
        let result: Lookup
        if case .found = first { result = first } else { result = await search(state) }

        let lyrics: Lyrics?
        switch (first, result) {
        case (_, .found(let found)):
            lyrics = found
        case (.missing, .missing):
            lyrics = nil // LRCLIB really has nothing for it
        default:
            // A request failed: don't remember "no lyrics", ask again next time.
            Log.network.info("Lyrics lookup failed; not cached")
            return nil
        }
        lock.lock()
        cache[key] = lyrics
        if cache.count > 200 { cache.removeAll() }
        lock.unlock()
        return lyrics
    }

    private func exact(_ state: PlayerState) async -> Lookup {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: state.title),
            URLQueryItem(name: "artist_name", value: state.artist),
            URLQueryItem(name: "album_name", value: state.album),
            URLQueryItem(name: "duration", value: String(Int(state.duration.rounded()))),
        ]
        guard let data = await get(components.url) else { return .failed }
        guard !data.isEmpty, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let found = Self.lyrics(from: json)
        else { return .missing }
        return .found(found)
    }

    /// Without an exact match, the first one with synced lyrics and a similar duration.
    private func search(_ state: PlayerState) async -> Lookup {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: state.title),
            URLQueryItem(name: "artist_name", value: state.artist),
        ]
        guard let data = await get(components.url) else { return .failed }
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let found = Self.best(in: list, duration: state.duration)
        else { return .missing }
        return .found(found)
    }

    /// The body of a 200, empty `Data` for a 404 (LRCLIB's "not found"), `nil` for anything
    /// else: no network, a timeout, a server error.
    private func get(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: return data
            case 404: return Data()
            case let status:
                Log.network.error("LRCLIB answered \(status ?? 0, privacy: .public)")
                return nil
            }
        } catch {
            Log.network.error("LRCLIB unreachable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// From a search's results: the first with synced lyrics among those whose duration is
    /// within 4 s of the song's, or else the first of those.
    static func best(in list: [[String: Any]], duration: Double) -> Lyrics? {
        let close = list.filter { item in
            guard duration > 0, let d = item["duration"] as? Double else { return true }
            return abs(d - duration) < 4
        }
        let best = close.first { ($0["syncedLyrics"] as? String)?.isEmpty == false } ?? close.first
        return best.flatMap(lyrics(from:))
    }

    static func lyrics(from json: [String: Any]) -> Lyrics? {
        let synced = json["syncedLyrics"] as? String ?? ""
        let plain = json["plainLyrics"] as? String ?? ""
        let instrumental = json["instrumental"] as? Bool ?? false
        let lines = Lyrics.parseLRC(synced)
        if lines.isEmpty && plain.isEmpty && !instrumental { return nil }
        return Lyrics(lines: lines, plain: plain, instrumental: instrumental)
    }
}
