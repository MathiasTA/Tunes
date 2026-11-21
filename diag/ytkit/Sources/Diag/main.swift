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


@main
struct Diag {
    static func main() async {
        var firstID = "HfmWPfqyYyY"
        for q in ["Tobias Rahim - Stor Mand", "Taylor Swift - The Fate of Ophelia"] {
            do {
                let r = try await YouTubeSearch.search(q)
                if let f = r.first, q.hasPrefix("Tobias") { firstID = f.id }
                print("SEARCH \(q): \(r.count) results; first: \(r.prefix(3).map { "\($0.id) \($0.title) | \($0.channel) | \($0.duration ?? -1)" })")
            } catch { print("SEARCH \(q) ERROR: \(error)") }
        }
        for (label, methods) in [("local", [YouTube.ExtractionMethod.local]), ("remote", [.remote]), ("both", [.local, .remote])] {
            do {
                let streams = try await YouTube(videoID: firstID, methods: methods).streams
                let audio = streams.filterAudioOnly()
                print("STREAMS \(label): total \(streams.count), audio \(audio.count), m4a \(audio.filter { $0.fileExtension == .m4a }.count)")
                if let s = audio.filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream() {
                    var req = URLRequest(url: s.url)
                    req.setValue("bytes=0-999999", forHTTPHeaderField: "Range")
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    print("DOWNLOAD \(label): HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0), \(data.count) bytes")
                }
            } catch { print("STREAMS \(label) ERROR: \(error)") }
        }
    }
}
