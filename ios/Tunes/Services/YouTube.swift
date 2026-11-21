import Foundation
import YouTubeKit

/// A YouTube video found by search.
struct VideoCandidate: Hashable, Identifiable {
    let id: String
    let title: String
    let channel: String
    let duration: Double?
}

struct MatchResult {
    let best: VideoCandidate
    let alternatives: [VideoCandidate]
    /// False when the best result is a shaky guess (wrong length, odd version, or close runners-up).
    let confident: Bool
}

enum YouTubeError: LocalizedError {
    case noResults, http(Int), noAudio, noVideo, empty, badLink, extraction(String)
    var errorDescription: String? {
        switch self {
        case .noResults: "Search: YouTube had no matching videos."
        case .http(let code): "Download: YouTube refused the request (error \(code))."
        case .noAudio: "Download: found the video, but it had no audio Tunes can play."
        case .extraction(let detail): "Download: found the video, but couldn't get its audio (\(detail))."
        case .noVideo: "No playable video found."
        case .empty: "The download came back empty."
        case .badLink: "That doesn't look like a YouTube link."
        }
    }
}

/// Searches YouTube from the phone, using the same internal API the YouTube website uses.
enum YouTubeSearch {
    static func search(_ query: String) async throws -> [VideoCandidate] {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        let body: [String: Any] = [
            "context": ["client": ["clientName": "WEB", "clientVersion": "2.20251101.00.00", "hl": "en", "gl": "US"]],
            "query": query,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YouTubeError.http(http.statusCode)
        }
        var found: [VideoCandidate] = []
        collect(try JSONSerialization.jsonObject(with: data), into: &found)
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    /// Walks the whole response, so small layout changes on YouTube's side don't break it.
    private static func collect(_ node: Any, into out: inout [VideoCandidate]) {
        if let dict = node as? [String: Any] {
            if let r = dict["videoRenderer"] as? [String: Any], let c = candidate(r) { out.append(c) }
            // Visit "contents" first (it's where search results live, in page order), whether it's a list or a single block.
            if let contents = dict["contents"] { collect(contents, into: &out) }
            for (k, v) in dict where k != "videoRenderer" && k != "contents" { collect(v, into: &out) }
        } else if let array = node as? [Any] {
            for v in array { collect(v, into: &out) }
        }
    }

    private static func candidate(_ r: [String: Any]) -> VideoCandidate? {
        guard let id = r["videoId"] as? String, id.count == 11 else { return nil }
        return VideoCandidate(id: id, title: text(r["title"]) ?? "",
                              channel: text(r["ownerText"]) ?? text(r["longBylineText"]) ?? "",
                              duration: text(r["lengthText"]).flatMap(parseDuration))
    }

    private static func text(_ any: Any?) -> String? {
        guard let d = any as? [String: Any] else { return nil }
        if let s = d["simpleText"] as? String { return s }
        if let runs = d["runs"] as? [[String: Any]] { return runs.compactMap { $0["text"] as? String }.joined() }
        return nil
    }

    static func parseDuration(_ s: String) -> Double? {
        let parts = s.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Accepts youtu.be/ID, youtube.com/watch?v=ID, music.youtube.com, shorts, or a bare ID.
    static func videoID(from link: String) -> String? {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count == 11, s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) { return s }
        guard let comps = URLComponents(string: s) else { return nil }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, v.count == 11 { return v }
        let last = comps.path.split(separator: "/").last.map(String.init) ?? ""
        return last.count == 11 ? last : nil
    }
}

/// Picks the YouTube upload that best matches a catalog song.
enum Matcher {
    private static let badWords = ["live", "cover", "remix", "karaoke", "instrumental", "sped up", "slowed",
                                   "reverb", "8d", "nightcore", "reaction", "acoustic", "tutorial", "lesson",
                                   "hour", "hours", "loop", "extended", "mashup", "parody", "teaser", "trailer",
                                   "piano", "guitar", "drum", "bass boosted", "fan made", "concert", "lyrics video"]

    static func match(_ song: Song) async throws -> MatchResult {
        let results = try await YouTubeSearch.search("\(song.artist.name) - \(song.title)")
        let duration = song.duration > 0 ? song.duration : nil
        let scored = results.map { ($0, score($0, artist: song.artist.name, title: song.title, duration: duration)) }
            .sorted { $0.1 > $1.1 }
        guard let top = scored.first else { throw YouTubeError.noResults }
        var confident = top.1 >= 45
        if let d = duration, let vd = top.0.duration, abs(vd - d) > 8 { confident = false }
        if scored.count > 1, top.1 - scored[1].1 < 4, scored[1].0.duration != top.0.duration { confident = false }
        return MatchResult(best: top.0, alternatives: Array(scored.dropFirst().prefix(5).map(\.0)), confident: confident)
    }

    static func score(_ c: VideoCandidate, artist: String, title: String, duration: Double?) -> Double {
        let vt = c.title.normalizedForMatching, ch = c.channel.normalizedForMatching
        let st = title.normalizedForMatching, an = artist.normalizedForMatching
        var score = 0.0
        let words = st.split(separator: " ").map(String.init)
        if !words.isEmpty { score += 40 * Double(words.filter { has(vt, $0) }.count) / Double(words.count) }
        if !an.isEmpty && ch.contains(an) { score += 15 }
        if ch.hasSuffix(" topic") { score += 20 }
        if !an.isEmpty && vt.contains(an) { score += 5 }
        for w in badWords where has(vt, w) && !has(st, w) { score -= 30 }
        if vt.contains("official video") || vt.contains("music video") { score -= 5 }
        if let duration, let vd = c.duration {
            let diff = abs(vd - duration)
            score -= min(diff, 120) * 0.5
            if diff <= 3 { score += 10 }
        } else if duration != nil {
            score -= 10
        }
        return score
    }

    private static func has(_ text: String, _ phrase: String) -> Bool { " \(text) ".contains(" \(phrase) ") }
}

/// Gets audio and video straight from YouTube on the phone via YouTubeKit.
enum YouTubeMedia {
    private static func video(_ id: String, allowRemote: Bool) -> YouTube {
        allowRemote ? YouTube(videoID: id, methods: [.local, .remote]) : YouTube(videoID: id, methods: [.local])
    }

    /// Downloads the audio track as .m4a (AAC, which iOS plays natively).
    static func downloadAudio(videoID: String, to dest: URL, saveSpace: Bool, allowRemote: Bool,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        let streams: [YouTubeKit.Stream]
        do {
            streams = try await video(videoID, allowRemote: allowRemote).streams
        } catch {
            throw YouTubeError.extraction(String(describing: error))
        }
        let m4a = streams.filterAudioOnly().filter { $0.fileExtension == .m4a }
        let pick = saveSpace ? m4a.lowestAudioBitrateStream() : m4a.highestAudioBitrateStream()
        guard let stream = pick ?? streams.filterAudioOnly().filter({ $0.isNativelyPlayable }).highestAudioBitrateStream() else {
            throw YouTubeError.noAudio
        }
        try await Net.fetchInChunks(stream.url, to: dest, progress: progress)
    }

    /// A streamable video URL (video + audio) for the video player.
    /// YouTube only offers combined video+audio files in standard quality (usually 360p), which is what we stream.
    static func videoURL(videoID: String, allowRemote: Bool) async throws -> URL {
        let streams = try await video(videoID, allowRemote: allowRemote).streams
        guard let stream = streams.filterVideoAndAudio().filter({ $0.isNativelyPlayable }).highestResolutionStream() else {
            throw YouTubeError.noVideo
        }
        return stream.url
    }
}

enum Net {
    /// YouTube throttles big single requests, so fetch ~10 MB ranges one after another.
    static func fetchInChunks(_ url: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let part = dest.deletingLastPathComponent().appending(path: UUID().uuidString + ".part")
        FileManager.default.createFile(atPath: part.path, contents: nil)
        let handle = try FileHandle(forWritingTo: part)
        var finished = false
        defer {
            try? handle.close()
            if !finished { try? FileManager.default.removeItem(at: part) }
        }
        let chunk = 10_000_000
        var offset = 0
        var total: Int?
        while true {
            try Task.checkCancellation()
            var req = URLRequest(url: url)
            req.timeoutInterval = 60
            req.setValue("bytes=\(offset)-\(offset + chunk - 1)", forHTTPHeaderField: "Range")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw YouTubeError.http(0) }
            guard (200..<300).contains(http.statusCode) else { throw YouTubeError.http(http.statusCode) }
            if data.isEmpty { break }
            try handle.write(contentsOf: data)
            offset += data.count
            if http.statusCode == 200 { break }
            if total == nil {
                total = http.value(forHTTPHeaderField: "Content-Range")
                    .flatMap { $0.split(separator: "/").last }
                    .flatMap { Int($0) }
            }
            if let total {
                progress(min(1, Double(offset) / Double(max(total, 1))))
                if offset >= total { break }
            } else if data.count < chunk {
                break
            }
        }
        try handle.close()
        guard offset > 0 else { throw YouTubeError.empty }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: part, to: dest)
        finished = true
        progress(1)
    }

    /// Plain file download (artwork etc).
    static func download(from url: URL, to dest: URL) async throws {
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: tmp) }
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YouTubeError.http(http.statusCode)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    static func getJSON(_ url: URL, headers: [String: String] = [:]) async throws -> Any {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YouTubeError.http(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}
