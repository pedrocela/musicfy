import Foundation

/// Letras de LRCLIB (lrclib.net): gratis, sin cuenta, con tiempos por línea.
struct Lyrics: Equatable {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    /// Con tiempos. Vacío si sólo hay letra plana.
    let lines: [Line]
    let plain: String
    let instrumental: Bool

    var isSynced: Bool { !lines.isEmpty }

    /// Índice de la línea que corresponde a `position` (en segundos).
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

    /// "[01:23.45] texto" → Line(83.45, "texto"). Ignora etiquetas de metadata.
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

    func lyrics(for state: PlayerState) async -> Lyrics? {
        let key = state.trackKey
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        var found = await exact(state)
        if found == nil { found = await search(state) }

        lock.lock()
        cache[key] = found
        if cache.count > 200 { cache.removeAll() }
        lock.unlock()
        return found
    }

    private func exact(_ state: PlayerState) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: state.title),
            URLQueryItem(name: "artist_name", value: state.artist),
            URLQueryItem(name: "album_name", value: state.album),
            URLQueryItem(name: "duration", value: String(Int(state.duration.rounded()))),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Self.lyrics(from: json)
    }

    /// Si no hay coincidencia exacta, la primera con letra sincronizada y duración parecida.
    private func search(_ state: PlayerState) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: state.title),
            URLQueryItem(name: "artist_name", value: state.artist),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        let close = list.filter { item in
            guard state.duration > 0, let d = item["duration"] as? Double else { return true }
            return abs(d - state.duration) < 4
        }
        let best = close.first { ($0["syncedLyrics"] as? String)?.isEmpty == false } ?? close.first
        return best.flatMap(Self.lyrics(from:))
    }

    private static func lyrics(from json: [String: Any]) -> Lyrics? {
        let synced = json["syncedLyrics"] as? String ?? ""
        let plain = json["plainLyrics"] as? String ?? ""
        let instrumental = json["instrumental"] as? Bool ?? false
        let lines = Lyrics.parseLRC(synced)
        if lines.isEmpty && plain.isEmpty && !instrumental { return nil }
        return Lyrics(lines: lines, plain: plain, instrumental: instrumental)
    }
}
