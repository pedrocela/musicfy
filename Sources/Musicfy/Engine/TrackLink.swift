import Foundation

/// The public link of the playing song, to copy it.
/// Spotify gives the id (spotify:track:…); for Music it's looked up in Apple's catalog, and
/// for Podcasts the episode is looked up there too (or at least its show).
enum TrackLink {
    static func url(for state: PlayerState) async -> URL? {
        switch state.source {
        case .spotify:
            let parts = state.trackID.split(separator: ":")
            guard parts.count == 3, parts[1] == "track" else { return nil }
            return URL(string: "https://open.spotify.com/track/\(parts[2])")
        case .podcasts:
            return await podcastLink(show: state.artist, episode: state.title)
        case .music:
            let term = [state.artist, state.title].filter { !$0.isEmpty }.joined(separator: " ")
            guard !term.isEmpty else { return nil }
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "5"),
                Catalog.countryItem,
            ]
            guard let url = components.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]]
            else { return nil }
            // The first result can be another version, or another artist's song by the
            // same name: only one that is this song.
            let match = results.first {
                Catalog.same($0["trackName"] as? String, state.title) && Catalog.same($0["artistName"] as? String, state.artist)
            } ?? results.first { Catalog.same($0["artistName"] as? String, state.artist) && !state.artist.isEmpty }
            guard let link = match?["trackViewUrl"] as? String else { return nil }
            return URL(string: link)
        }
    }

    private static func podcastLink(show: String, episode: String) async -> URL? {
        func search(_ term: String, entity: String) async -> [[String: Any]] {
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "media", value: "podcast"),
                URLQueryItem(name: "entity", value: entity),
                URLQueryItem(name: "limit", value: "10"),
                Catalog.countryItem,
            ]
            guard let url = components.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [] }
            return json["results"] as? [[String: Any]] ?? []
        }
        let term = [show, episode].filter { !$0.isEmpty }.joined(separator: " ")
        if !episode.isEmpty {
            let episodes = await search(term, entity: "podcastEpisode")
            let match = episodes.first { ($0["trackName"] as? String)?.caseInsensitiveCompare(episode) == .orderedSame }
            if let link = (match ?? episodes.first)?["trackViewUrl"] as? String { return URL(string: link) }
        }
        guard !show.isEmpty, let first = await search(show, entity: "podcast").first,
              let link = first["collectionViewUrl"] as? String
        else { return nil }
        return URL(string: link)
    }
}

/// Apple's public catalog (the iTunes search): which store to ask, and whether a result
/// is the song that was asked for.
enum Catalog {
    /// The Mac's region. Without it the search answers from the US store, whose links and
    /// versions aren't always the ones this Mac's Music has.
    static var country: String { Locale.current.region?.identifier ?? "US" }
    static var countryItem: URLQueryItem { URLQueryItem(name: "country", value: country) }

    /// The same name, give or take case, accents, punctuation and a suffix
    /// ("Heroes" and "Heroes - 2017 Remaster"; "Beyoncé" and "beyonce").
    static func same(_ found: String?, _ wanted: String) -> Bool {
        let a = fold(found ?? ""), b = fold(wanted)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }

    private static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(plain.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
