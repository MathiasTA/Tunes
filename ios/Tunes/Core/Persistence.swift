import Foundation
import SwiftUI

/// Where everything lives on the phone.
enum Paths {
    static let documents = URL.documentsDirectory
    static let audioDir = makeDir(documents.appending(path: "Audio", directoryHint: .isDirectory))
    static let artDir = makeDir(documents.appending(path: "Artwork", directoryHint: .isDirectory))
    static let dataDir = makeDir(documents.appending(path: "Data", directoryHint: .isDirectory))
    static let cacheDir = makeDir(URL.cachesDirectory.appending(path: "Tunes", directoryHint: .isDirectory))

    static func songArtwork(_ id: Int) -> URL { artDir.appending(path: "song-\(id).jpg") }
    static func artistImage(_ id: Int) -> URL { artDir.appending(path: "artist-\(id).jpg") }
    static var avatar: URL { artDir.appending(path: "avatar.jpg") }
    static func data(_ name: String) -> URL { dataDir.appending(path: name) }

    @discardableResult
    static func makeDir(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func size(of dir: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

/// JSON load/save for the app's data files. Saves happen off the main thread.
enum Store {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: Paths.data(name)) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Keep a copy of a file we couldn't read instead of silently losing it.
            let broken = Paths.data(name + ".unreadable")
            try? FileManager.default.removeItem(at: broken)
            try? FileManager.default.copyItem(at: Paths.data(name), to: broken)
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        let url = Paths.data(name)
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func saveNow<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: Paths.data(name), options: .atomic)
    }
}

/// Coalesces many quick saves into one.
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?
    private let delay: Duration

    init(_ delay: Duration = .milliseconds(600)) { self.delay = delay }

    func run(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

enum Fmt {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func time(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let t = Int(seconds.rounded(.down))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "37 min", "4.2 h", "112 h"
    static func listening(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = seconds / 3600
        return hours < 10 ? String(format: "%.1f h", hours) : "\(Int(hours.rounded())) h"
    }

    static func count(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }

    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    static func shortDate(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255; a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum Palette {
    /// Stable placeholder colors for artwork, picked from an id.
    static let artColors = ["#3B5BDB", "#0F766E", "#9D174D", "#B45309", "#4D7C0F", "#6D28D9", "#B91C1C", "#334155", "#0E7490", "#A16207"]
    static func color(for id: Int) -> Color { Color(hex: artColors[abs(id) % artColors.count]) }
    static func hex(for id: Int) -> String { artColors[abs(id) % artColors.count] }
}

extension String {
    /// Lowercased, accents removed, punctuation turned into spaces. Used for matching.
    var normalizedForMatching: String {
        let folded = folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current).lowercased()
        let chars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(chars).split(separator: " ").joined(separator: " ")
    }
}
