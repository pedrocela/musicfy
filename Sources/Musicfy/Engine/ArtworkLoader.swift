import AppKit

/// Downloads artwork by URL (Spotify) or, when Music doesn't provide it, looks it up in
/// the public iTunes catalog by artist and album. Keeps the latest ones in memory.
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    private let cache = NSCache<NSString, NSImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        return URLSession(configuration: config)
    }()

    init() { cache.countLimit = 40 }

    func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    func store(_ image: NSImage, for key: String) { cache.setObject(image, forKey: key as NSString) }

    func image(from url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }

    /// 600 px artwork from the iTunes search (no account or key needed).
    func searchCatalog(artist: String, album: String, title: String) async -> NSImage? {
        let term = [artist, album.isEmpty ? title : album].filter { !$0.isEmpty }.joined(separator: " ")
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: album.isEmpty ? "song" : "album"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let small = first["artworkUrl100"] as? String,
              let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
        else { return nil }
        return await image(from: big)
    }
}
