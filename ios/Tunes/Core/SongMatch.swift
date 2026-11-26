import Foundation

/// Finds versions of the same song (a single and its album version), so they count as one.
/// Two songs match with the same title (ignoring "feat.", "Remastered", "Single Version" and similar), the same
/// main artist, and lengths within 10 seconds. Remixes, live, acoustic, sped up, slowed and other versions whose
/// title says so stay separate.
@MainActor
enum SongMatch {
    static func key(title: String, artist: String) -> String {
        var t = title.lowercased()
        let cuts = ["(feat", "[feat", " feat.", " feat ", " ft.", "(with ", " - remaster", "(remaster", "[remaster",
                    " - single version", "(single version)", "(album version)", " - album version", "(radio version)"]
        for c in cuts { if let r = t.range(of: c) { t = String(t[..<r.lowerBound]) } }
        let kept = t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        let clean = String(String.UnicodeScalarView(kept)).split(separator: Character(" ")).joined(separator: " ")
        return clean + "|" + artist.lowercased()
    }

    static func key(_ s: Song) -> String { key(title: s.title, artist: s.artist.name) }

    /// Album versions win over singles, then the lower ID (the older download).
    private static func rank(_ e: LibraryEntry) -> (Int, Int) {
        let single = e.song.album?.recordType?.lowercased() == "single" || e.song.album == nil
        return (single ? 1 : 0, e.id)
    }

    /// Groups of library songs that are the same song, the main version first.
    private static var cachedGroups: (stamp: String, value: [[LibraryEntry]])?
    private static var cachedCanonical: (stamp: String, value: [Int: Int])?

    /// Cached until the library changes, since lots of screens ask for this.
    static func groups(_ lib: Library) -> [[LibraryEntry]] {
        let stamp = "\(lib.version)-\(lib.entries.count)"
        if let c = cachedGroups, c.stamp == stamp { return c.value }
        let v = computeGroups(lib)
        cachedGroups = (stamp, v)
        return v
    }

    private static func computeGroups(_ lib: Library) -> [[LibraryEntry]] {
        var byKey: [String: [LibraryEntry]] = [:]
        for e in lib.entries { byKey[key(e.song), default: []].append(e) }
        var out: [[LibraryEntry]] = []
        for (_, list) in byKey where list.count > 1 {
            // Split by length: versions more than 10 s apart are different songs.
            var clusters: [[LibraryEntry]] = []
            for e in list.sorted(by: { rank($0) < rank($1) }) {
                if let i = clusters.firstIndex(where: { c in abs((c[0].song.duration) - e.song.duration) <= 10 || c[0].song.duration <= 0 || e.song.duration <= 0 }) {
                    clusters[i].append(e)
                } else { clusters.append([e]) }
            }
            out += clusters.filter { $0.count > 1 }
        }
        return out.sorted { $0[0].song.title < $1[0].song.title }
    }

    /// Song ID → the main version's ID, for songs that have another version in the library.
    static func canonical(_ lib: Library) -> [Int: Int] {
        let stamp = "\(lib.version)-\(lib.entries.count)"
        if let c = cachedCanonical, c.stamp == stamp { return c.value }
        var map: [Int: Int] = [:]
        for g in groups(lib) { for e in g { map[e.id] = g[0].id } }
        cachedCanonical = (stamp, map)
        return map
    }

    /// The other versions of a song you have.
    static func versions(of s: Song, in lib: Library) -> [LibraryEntry] {
        groups(lib).first { g in g.contains { $0.id == s.id } }?.filter { $0.id != s.id } ?? []
    }
}
