import Foundation

/// The charts the app can show, and how to get their songs.
enum ChartCatalog {
    struct Country: Identifiable, Hashable {
        let name: String
        let code: String
        var id: String { code }
    }

    static let countries: [Country] = [
        .init(name: "Denmark", code: "dk"), .init(name: "Sweden", code: "se"), .init(name: "Norway", code: "no"),
        .init(name: "Finland", code: "fi"), .init(name: "Germany", code: "de"), .init(name: "UK", code: "gb"),
        .init(name: "Ireland", code: "ie"), .init(name: "USA", code: "us"), .init(name: "Canada", code: "ca"),
        .init(name: "France", code: "fr"), .init(name: "Netherlands", code: "nl"), .init(name: "Belgium", code: "be"),
        .init(name: "Spain", code: "es"), .init(name: "Italy", code: "it"), .init(name: "Poland", code: "pl"),
        .init(name: "Austria", code: "at"), .init(name: "Switzerland", code: "ch"), .init(name: "Brazil", code: "br"),
        .init(name: "Mexico", code: "mx"), .init(name: "Colombia", code: "co"), .init(name: "Turkey", code: "tr"),
        .init(name: "Australia", code: "au"), .init(name: "Japan", code: "jp")
    ]

    static let colors = ["#B91C1C", "#334155", "#1E40AF", "#A16207", "#4338CA", "#0369A1", "#DB2777", "#6D28D9", "#57534E", "#0E7490", "#9F1239", "#C2410C"]

    static func country(_ c: Country) -> ChartSource {
        let seed = c.code.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let color = colors[seed % colors.count]
        return ChartSource(kind: .deezerPlaylist, ref: "q:Top \(c.name)|\(c.code)", name: "Top \(c.name)",
                           tag: c.code.uppercased(), colorHex: color, sourceLabel: "Deezer Charts")
    }

    static let worldwide = ChartSource(kind: .deezerGenre, ref: "0", name: "Top Worldwide", tag: "WW", colorHex: "#334155", sourceLabel: "Deezer Charts")

    static func genre(id: Int, name: String) -> ChartSource {
        ChartSource(kind: .deezerGenre, ref: String(id), name: "Top \(name)", tag: String(name.prefix(4)).uppercased(),
                    colorHex: colors[abs(id) % colors.count], sourceLabel: "Deezer genre chart")
    }

    static func editorial(_ p: Catalog.PlaylistInfo) -> ChartSource {
        ChartSource(kind: .deezerPlaylist, ref: String(p.id), name: p.title, tag: "HITS",
                    colorHex: colors[abs(p.id) % colors.count], sourceLabel: p.owner.isEmpty ? "Deezer editors" : p.owner)
    }

    static var defaults: [ChartSource] {
        [ChartSource(kind: .deezerPlaylist, ref: "q:Top Denmark|dk", name: "Top Denmark", tag: "DK", colorHex: "#B91C1C", sourceLabel: "Deezer Charts"),
         worldwide,
         ChartSource(kind: .deezerGenre, ref: "132", name: "Top Pop", tag: "POP", colorHex: "#DB2777", sourceLabel: "Deezer genre chart")]
    }

    /// Fetches the chart's current songs. Country charts use Deezer's "Top <country>" playlist,
    /// falling back to Apple Music's free chart when Deezer has none.
    static func songs(for chart: ChartSource, limit: Int = 50) async throws -> [Song] {
        switch chart.kind {
        case .deezerGenre:
            return try await Catalog.chartTracks(genreID: Int(chart.ref) ?? 0, limit: limit)
        case .deezerPlaylist:
            if chart.ref.hasPrefix("q:") {
                let body = String(chart.ref.dropFirst(2))
                let parts = body.split(separator: "|").map(String.init)
                let query = parts.first ?? chart.name
                if let id = await resolvePlaylist(query) {
                    let songs = try await Catalog.playlistTracks(id, limit: limit)
                    if !songs.isEmpty { return songs }
                }
                if parts.count > 1 { return try await appleChart(country: parts[1], limit: limit) }
                return []
            }
            return try await Catalog.playlistTracks(Int(chart.ref) ?? 0, limit: limit)
        case .appleCountry:
            return try await appleChart(country: chart.ref, limit: limit)
        }
    }

    private static func resolvePlaylist(_ query: String) async -> Int? {
        let key = "chartPlaylist:" + query
        if let cached = UserDefaults.standard.object(forKey: key) as? Int { return cached }
        guard let results = try? await Catalog.searchPlaylists(query, limit: 15) else { return nil }
        let wanted = query.normalizedForMatching
        let hit = results.first { $0.title.normalizedForMatching == wanted && $0.owner.lowercased().contains("deezer") }
            ?? results.first { $0.title.normalizedForMatching == wanted }
        if let hit { UserDefaults.standard.set(hit.id, forKey: key) }
        return hit?.id
    }

    private static func appleChart(country: String, limit: Int) async throws -> [Song] {
        guard let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(country)/music/most-played/\(min(limit, 50))/songs.json") else { return [] }
        let obj = try await Net.getJSON(url) as? [String: Any]
        let results = ((obj?["feed"] as? [String: Any])?["results"] as? [[String: Any]]) ?? []
        var songs: [Song] = []
        for r in results.prefix(limit) {
            guard let title = r["name"] as? String, let artist = r["artistName"] as? String else { continue }
            switch await CatalogMatcher.find(title: title, artist: artist, duration: nil) {
            case .match(let s): songs.append(s)
            case .unsure(let best, _): songs.append(best)
            case .notFound: continue
            }
        }
        return songs
    }
}
