import Foundation

/// The public link of the playing song, to copy it.
/// Spotify gives the id (spotify:track:…); for Music it's looked up in Apple's catalog.
enum TrackLink {
    static func url(for state: PlayerState) async -> URL? {
        switch state.source {
        case .spotify:
            let parts = state.trackID.split(separator: ":")
            guard parts.count == 3, parts[1] == "track" else { return nil }
            return URL(string: "https://open.spotify.com/track/\(parts[2])")
        case .music:
            let term = [state.artist, state.title].filter { !$0.isEmpty }.joined(separator: " ")
            guard !term.isEmpty else { return nil }
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "1"),
            ]
            guard let url = components.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let link = first["trackViewUrl"] as? String
            else { return nil }
            return URL(string: link)
        }
    }
}
