import Foundation

struct ExternalTrack: Hashable {
    let title: String
    let artist: String
    let duration: Double?
}

struct HistoryPlay {
    let title: String
    let artist: String
    let start: Date
    let seconds: Double
}

enum SpotifyImportError: LocalizedError {
    case badLink, noTracks, unreadable
    var errorDescription: String? {
        switch self {
        case .badLink: "That doesn't look like a Spotify playlist link."
        case .noTracks: "Couldn't read the songs. Make sure the playlist is public, or import an exported CSV file instead."
        case .unreadable: "Couldn't read that file."
        }
    }
}

/// Reads Spotify playlists (public link or exported CSV) and Spotify's listening history export.
enum SpotifyImport {
    static func playlistID(from link: String) -> String? {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("spotify:playlist:") { return String(s.dropFirst("spotify:playlist:".count)) }
        guard let comps = URLComponents(string: s), comps.host?.contains("spotify") == true else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(of: "playlist"), i + 1 < parts.count else { return nil }
        return parts[i + 1]
    }

    /// Reads a public playlist from Spotify's embed page. Not an official API, so it may change.
    static func fetchPlaylist(link: String) async throws -> (name: String, tracks: [ExternalTrack]) {
        guard let id = playlistID(from: link), let url = URL(string: "https://open.spotify.com/embed/playlist/\(id)") else {
            throw SpotifyImportError.badLink
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
              let jsonData = String(html[start.upperBound..<end.lowerBound]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData)
        else { throw SpotifyImportError.noTracks }

        var name = "Imported playlist"
        var tracks: [ExternalTrack] = []
        findTrackList(json, name: &name, tracks: &tracks)
        guard !tracks.isEmpty else { throw SpotifyImportError.noTracks }
        return (name, tracks)
    }

    private static func findTrackList(_ node: Any, name: inout String, tracks: inout [ExternalTrack]) {
        guard tracks.isEmpty else { return }
        if let dict = node as? [String: Any] {
            if let list = dict["trackList"] as? [[String: Any]] {
                tracks = list.compactMap { item in
                    guard let title = item["title"] as? String else { return nil }
                    let artist = (item["subtitle"] as? String) ?? ""
                    let ms = (item["duration"] as? Double) ?? (item["duration"] as? Int).map(Double.init)
                    return ExternalTrack(title: title, artist: firstArtist(artist), duration: ms.map { $0 / 1000 })
                }
                if let n = (dict["name"] as? String) ?? (dict["title"] as? String), !n.isEmpty { name = n }
                return
            }
            for (_, v) in dict { findTrackList(v, name: &name, tracks: &tracks) }
        } else if let array = node as? [Any] {
            for v in array { findTrackList(v, name: &name, tracks: &tracks) }
        }
    }

    private static func firstArtist(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "\u{00a0}", with: " ")
        return cleaned.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? cleaned
    }

    /// CSV from Exportify (or similar): needs "Track Name" and "Artist Name(s)" columns.
    static func parseCSV(_ text: String) throws -> (name: String, tracks: [ExternalTrack]) {
        let rows = csvRows(text)
        guard let header = rows.first else { throw SpotifyImportError.unreadable }
        let lower = header.map { $0.lowercased() }
        guard let ti = lower.firstIndex(where: { $0.contains("track name") || $0 == "title" || $0 == "name" }),
              let ai = lower.firstIndex(where: { $0.contains("artist") }) else { throw SpotifyImportError.unreadable }
        let di = lower.firstIndex(where: { $0.contains("duration") })
        let tracks = rows.dropFirst().compactMap { r -> ExternalTrack? in
            guard r.count > max(ti, ai), !r[ti].isEmpty else { return nil }
            let ms = di.flatMap { $0 < r.count ? Double(r[$0]) : nil }
            return ExternalTrack(title: r[ti], artist: firstArtist(r[ai]), duration: ms.map { $0 / 1000 })
        }
        guard !tracks.isEmpty else { throw SpotifyImportError.noTracks }
        return ("Imported playlist", tracks)
    }

    private static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        if chars.first == "\u{feff}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n":
                    row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Spotify's "Extended streaming history" (and the older basic "StreamingHistory" files).
    static func parseHistory(_ data: Data) throws -> [HistoryPlay] {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw SpotifyImportError.unreadable }
        let iso = ISO8601DateFormatter()
        let basic = DateFormatter()
        basic.locale = Locale(identifier: "en_US_POSIX")
        basic.timeZone = TimeZone(identifier: "UTC")
        basic.dateFormat = "yyyy-MM-dd HH:mm"
        var out: [HistoryPlay] = []
        for item in list {
            let title = (item["master_metadata_track_name"] as? String) ?? (item["trackName"] as? String)
            let artist = (item["master_metadata_album_artist_name"] as? String) ?? (item["artistName"] as? String)
            let ms = (item["ms_played"] as? Double) ?? (item["msPlayed"] as? Double)
                ?? (item["ms_played"] as? Int).map(Double.init) ?? (item["msPlayed"] as? Int).map(Double.init)
            guard let title, let artist, let ms, ms >= 5000 else { continue }
            var end: Date?
            if let ts = item["ts"] as? String { end = iso.date(from: ts) }
            if end == nil, let et = item["endTime"] as? String { end = basic.date(from: et) }
            guard let end else { continue }
            let seconds = ms / 1000
            out.append(HistoryPlay(title: title, artist: artist, start: end.addingTimeInterval(-seconds), seconds: seconds))
        }
        return out
    }
}
