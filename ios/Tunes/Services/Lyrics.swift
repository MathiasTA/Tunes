import Foundation

struct LyricLine: Hashable, Identifiable, Codable {
    let time: Double?
    let text: String
    var id: String { "\(time ?? -1)-\(text)" }
}

struct Lyrics: Codable, Hashable {
    var lines: [LyricLine]
    var synced: Bool
    var instrumental: Bool

    static let none = Lyrics(lines: [], synced: false, instrumental: false)
    var isEmpty: Bool { lines.isEmpty && !instrumental }

    /// Index of the line being sung at `time`.
    func index(at time: Double) -> Int? {
        guard synced else { return nil }
        var result: Int?
        for (i, l) in lines.enumerated() {
            guard let t = l.time else { continue }
            if t <= time { result = i } else { break }
        }
        return result
    }
}

/// Free synced lyrics from LRCLIB. Cached on the phone so they work offline.
enum LyricsService {
    private static func cacheURL(_ id: Int) -> URL {
        Paths.makeDir(Paths.dataDir.appending(path: "Lyrics", directoryHint: .isDirectory)).appending(path: "\(id).json")
    }

    static func cached(_ songID: Int) -> Lyrics? {
        guard let data = try? Data(contentsOf: cacheURL(songID)) else { return nil }
        return try? JSONDecoder().decode(Lyrics.self, from: data)
    }

    static func fetch(_ song: Song) async -> Lyrics {
        if let c = cached(song.id) { return c }
        var result = Lyrics.none
        if let exact = try? await get(song) { result = exact }
        else if let found = try? await search(song) { result = found }
        if !result.isEmpty, let data = try? JSONEncoder().encode(result) {
            try? data.write(to: cacheURL(song.id), options: .atomic)
        }
        return result
    }

    static func clearCache(_ songID: Int) { try? FileManager.default.removeItem(at: cacheURL(songID)) }

    private static func request(_ path: String, _ items: [URLQueryItem]) -> URLRequest? {
        var comps = URLComponents(string: "https://lrclib.net/api/\(path)")
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Tunes iOS app (personal use)", forHTTPHeaderField: "User-Agent")
        return req
    }

    private static func get(_ song: Song) async throws -> Lyrics? {
        var items = [URLQueryItem(name: "track_name", value: song.title), URLQueryItem(name: "artist_name", value: song.artist.name)]
        if let album = song.album?.title { items.append(URLQueryItem(name: "album_name", value: album)) }
        if song.duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(song.duration)))) }
        guard let req = request("get", items) else { return nil }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func search(_ song: Song) async throws -> Lyrics? {
        guard let req = request("search", [URLQueryItem(name: "track_name", value: song.title),
                                           URLQueryItem(name: "artist_name", value: song.artist.name)]) else { return nil }
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let best = list.min { a, b in
            abs((a["duration"] as? Double ?? 0) - song.duration) < abs((b["duration"] as? Double ?? 0) - song.duration)
        }
        if let best, let d = best["duration"] as? Double, song.duration > 0, abs(d - song.duration) > 10 { return nil }
        return parse(best)
    }

    private static func parse(_ obj: [String: Any]?) -> Lyrics? {
        guard let obj else { return nil }
        if obj["instrumental"] as? Bool == true { return Lyrics(lines: [], synced: false, instrumental: true) }
        if let synced = obj["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return Lyrics(lines: lines, synced: true, instrumental: false) }
        }
        if let plain = obj["plainLyrics"] as? String, !plain.isEmpty {
            return Lyrics(lines: plain.components(separatedBy: .newlines).map { LyricLine(time: nil, text: $0) }, synced: false, instrumental: false)
        }
        return nil
    }

    static func parseLRC(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = Substring(raw)
            var times: [Double] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) { times.append(m * 60 + s) }
                line = line[line.index(after: close)...]
            }
            let words = line.trimmingCharacters(in: .whitespaces)
            for t in times { out.append(LyricLine(time: t, text: words)) }
        }
        return out.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
    }
}
