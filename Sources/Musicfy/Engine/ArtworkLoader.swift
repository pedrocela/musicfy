import AppKit
import ImageIO

/// Downloads artwork by URL (Spotify) or, when Music doesn't provide it, looks it up in
/// the public iTunes catalog by artist and album. Keeps the latest ones in memory.
///
/// Every image comes out already decoded and no bigger than it will be drawn, so the main
/// thread never decodes a 3000 px cover in the middle of a crossfade, and the cache holds
/// bitmaps of a known size.
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    /// Enough for a 640 pt artwork on a Retina display.
    static let fullSize = 1280
    /// Up Next thumbnails (34 pt).
    static let thumbSize = 96

    private let cache = NSCache<NSString, NSImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 64 << 20)
        return URLSession(configuration: config)
    }()

    init() {
        cache.countLimit = 60
        cache.totalCostLimit = 96 << 20 // bytes of decoded bitmap
    }

    func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    func store(_ image: NSImage, for key: String) {
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: max(pixels, 1) * 4)
    }

    func image(from url: URL, maxPixels: Int = ArtworkLoader.fullSize) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.decode(data, maxPixels: maxPixels)
    }

    /// 600 px artwork from the iTunes search (no account or key needed).
    func searchCatalog(artist: String, album: String, title: String, maxPixels: Int = ArtworkLoader.fullSize) async -> NSImage? {
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
              let small = first["artworkUrl100"] as? String
        else { return nil }
        // Thumbnails don't need the 600 px version.
        let side = maxPixels <= 100 ? "100x100bb" : "600x600bb"
        guard let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: side)) else { return nil }
        return await image(from: big, maxPixels: maxPixels)
    }

    /// A show's artwork from Apple's catalog, by its name.
    func searchPodcast(show: String, maxPixels: Int = ArtworkLoader.fullSize) async -> NSImage? {
        guard !show.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: show),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let link = (first["artworkUrl600"] ?? first["artworkUrl100"]) as? String,
              let big = URL(string: link)
        else { return nil }
        return await image(from: big, maxPixels: maxPixels)
    }

    /// Decodes now (call it off the main thread) and scales down to `maxPixels` on the
    /// longest side. The result is a plain bitmap: drawing it costs nothing extra.
    static func decode(_ data: Data, maxPixels: Int = fullSize) -> NSImage? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
