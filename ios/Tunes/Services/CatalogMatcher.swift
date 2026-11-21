import Foundation

/// Finds the real catalog song for a title + artist from somewhere else (Spotify, file tags, CSV).
enum CatalogMatcher {
    enum Outcome {
        case match(Song)
        case unsure(best: Song, options: [Song])
        case notFound
    }

    static func find(title: String, artist: String, duration: Double?) async -> Outcome {
        let cleanTitle = stripExtras(title)
        var candidates: [Song] = []
        if let a = try? await Catalog.searchSongs("artist:\"\(artist)\" track:\"\(cleanTitle)\"", limit: 10) { candidates = a }
        if candidates.isEmpty, let b = try? await Catalog.searchSongs("\(artist) \(cleanTitle)", limit: 10) { candidates = b }
        guard !candidates.isEmpty else { return .notFound }

        let scored = candidates.map { ($0, score($0, title: title, artist: artist, duration: duration)) }.sorted { $0.1 > $1.1 }
        let best = scored[0]
        guard best.1 >= 40 else { return .notFound }
        let titleExact = stripExtras(best.0.title).normalizedForMatching == cleanTitle.normalizedForMatching
        let durationOK = duration.map { abs($0 - best.0.duration) <= 4 } ?? true
        let closeRunnerUp = scored.count > 1 && best.1 - scored[1].1 < 5 && abs(scored[1].0.duration - best.0.duration) > 3
        if titleExact && durationOK && !closeRunnerUp && best.1 >= 70 { return .match(best.0) }
        return .unsure(best: best.0, options: Array(scored.prefix(5).map(\.0)))
    }

    static func score(_ s: Song, title: String, artist: String, duration: Double?) -> Double {
        var score = 0.0
        let st = stripExtras(s.title).normalizedForMatching, wt = stripExtras(title).normalizedForMatching
        if st == wt { score += 50 } else if st.contains(wt) || wt.contains(st) { score += 30 }
        let wantArtists = artist.normalizedForMatching
        let haveArtists = s.allArtists.map { $0.name.normalizedForMatching }
        if haveArtists.contains(where: { wantArtists.contains($0) || $0.contains(wantArtists) }) { score += 30 }
        if let duration, s.duration > 0 {
            let diff = abs(duration - s.duration)
            score += diff <= 2 ? 20 : (diff <= 5 ? 10 : -min(diff, 60) * 0.5)
        }
        let versionWords = ["live", "remix", "acoustic", "instrumental", "karaoke", "sped up", "slowed"]
        let lower = s.title.lowercased(), wantLower = title.lowercased()
        for w in versionWords where lower.contains(w) && !wantLower.contains(w) { score -= 25 }
        return score
    }

    /// "Song (feat. X) - 2011 Remaster" → "Song"
    static func stripExtras(_ title: String) -> String {
        var t = title
        for marker in [" (feat", " [feat", " (with ", " - Remaster", " - remaster", " (Remaster", " - Radio Edit", " - From "] {
            if let r = t.range(of: marker) { t = String(t[..<r.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
