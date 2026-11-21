import Foundation
import Observation

enum StatsRange: String, CaseIterable, Identifiable {
    case week = "7 days", month = "30 days", year = "This year", all = "All time"
    var id: String { rawValue }

    var interval: DateInterval? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        switch self {
        case .week: return cal.date(byAdding: .day, value: -6, to: today).map { DateInterval(start: $0, end: .distantFuture) }
        case .month: return cal.date(byAdding: .day, value: -29, to: today).map { DateInterval(start: $0, end: .distantFuture) }
        case .year: return cal.dateInterval(of: .year, for: .now).map { DateInterval(start: $0.start, end: .distantFuture) }
        case .all: return nil
        }
    }

    var bucket: Calendar.Component { self == .week || self == .month ? .day : .month }
}

/// Listening history. Only time spent playing your own songs counts (not previews).
@MainActor @Observable
final class StatsStore {
    private(set) var records: [PlayRecord] = []
    /// Bumped whenever records change, so views can cache expensive calculations.
    private(set) var version = 0

    @ObservationIgnored private var pending: [UUID: Double] = [:]
    @ObservationIgnored private var lastCommit = Date.now
    private let debouncer = Debouncer(.seconds(2))

    static let playThreshold: Double = 30
    static let countThreshold: Double = 5

    init() {
        records = (Store.load([PlayRecord].self, "plays.json") ?? []).filter { $0.seconds >= 1 }.sorted { $0.start < $1.start }
    }

    // MARK: Recording

    func startPlay(_ entry: LibraryEntry) -> UUID {
        let s = entry.song
        let r = PlayRecord(songID: s.id, title: s.title, artist: s.artist, others: s.featured, artworkURL: s.artworkURL,
                           genre: entry.genre ?? s.album?.genre, releaseYear: s.album?.year.flatMap { Int($0) },
                           start: .now, seconds: 0, origin: .tunes)
        records.append(r)
        return r.id
    }

    func add(_ seconds: Double, to id: UUID) {
        pending[id, default: 0] += seconds
        if Date.now.timeIntervalSince(lastCommit) > 15 { flush() }
    }

    func flush() {
        lastCommit = .now
        guard !pending.isEmpty else { return }
        for (id, s) in pending {
            if let i = records.lastIndex(where: { $0.id == id }) { records[i].seconds += s }
        }
        pending = [:]
        version += 1
        scheduleSave()
    }

    /// Removes a play that started but should not count (private listening).
    func discard(_ id: UUID) {
        pending[id] = nil
        records.removeAll { $0.id == id }
    }

    func addImported(_ new: [PlayRecord]) {
        records.append(contentsOf: new)
        records.sort { $0.start < $1.start }
        version += 1
        scheduleSave()
    }

    func reset() {
        pending = [:]
        records = []
        version += 1
        Store.saveNow(records, "plays.json")
    }

    func replaceAll(_ new: [PlayRecord]) {
        records = new.sorted { $0.start < $1.start }
        version += 1
        Store.saveNow(records, "plays.json")
    }

    private func scheduleSave() {
        debouncer.run { [weak self] in
            guard let self else { return }
            Store.save(self.records.filter { $0.seconds >= 1 }, "plays.json")
        }
    }

    func saveNow() {
        flush()
        Store.saveNow(records.filter { $0.seconds >= 1 }, "plays.json")
    }

    // MARK: Queries

    func records(in interval: DateInterval?) -> [PlayRecord] {
        guard let interval else { return records.filter { $0.seconds >= Self.countThreshold } }
        return records.filter { $0.seconds >= Self.countThreshold && $0.start >= interval.start && $0.start < interval.end }
    }

    func records(_ range: StatsRange) -> [PlayRecord] { records(in: range.interval) }

    func total(_ recs: [PlayRecord]) -> Double { recs.reduce(0) { $0 + $1.seconds } }
    func plays(_ recs: [PlayRecord]) -> Int { recs.filter { $0.seconds >= Self.playThreshold }.count }

    func seconds(forArtist id: Int) -> Double {
        records.reduce(0) { $1.allArtists.contains(where: { $0.id == id }) ? $0 + $1.seconds : $0 }
    }

    func seconds(forSong id: Int) -> Double { records.reduce(0) { $1.songID == id ? $0 + $1.seconds : $0 } }
    func playCount(forSong id: Int) -> Int { records.filter { $0.songID == id && $0.seconds >= Self.playThreshold }.count }
    func lastPlayed(_ songID: Int) -> Date? { records.last { $0.songID == songID }?.start }
    func firstPlayed(artist id: Int) -> Date? { records.first { r in r.allArtists.contains { $0.id == id } }?.start }

    struct ArtistStat: Identifiable, Hashable {
        let artist: Artist
        let seconds: Double
        let plays: Int
        var id: Int { artist.id }
    }

    func topArtists(_ recs: [PlayRecord], limit: Int = 10) -> [ArtistStat] {
        var secs: [Int: Double] = [:], plays: [Int: Int] = [:], latest: [Int: Artist] = [:]
        for r in recs {
            for a in r.allArtists {
                secs[a.id, default: 0] += r.seconds
                if r.seconds >= Self.playThreshold { plays[a.id, default: 0] += 1 }
                latest[a.id] = a.pictureURL != nil ? a : (latest[a.id] ?? a)
            }
        }
        return secs.compactMap { id, s in latest[id].map { ArtistStat(artist: $0, seconds: s, plays: plays[id] ?? 0) } }
            .sorted { $0.seconds > $1.seconds }
            .prefix(limit).map { $0 }
    }

    struct SongStat: Identifiable, Hashable {
        let songID: Int
        let title: String
        let artist: Artist
        let artworkURL: URL?
        let seconds: Double
        let plays: Int
        var id: Int { songID }
    }

    func topSongs(_ recs: [PlayRecord], limit: Int = 10) -> [SongStat] {
        var groups: [Int: [PlayRecord]] = [:]
        for r in recs { groups[r.songID, default: []].append(r) }
        return groups.values.compactMap { g -> SongStat? in
            guard let r = g.last else { return nil }
            return SongStat(songID: r.songID, title: r.title, artist: r.artist, artworkURL: r.artworkURL,
                            seconds: g.reduce(0) { $0 + $1.seconds }, plays: g.filter { $0.seconds >= Self.playThreshold }.count)
        }
        .sorted { ($0.plays, $0.seconds) > ($1.plays, $1.seconds) }
        .prefix(limit).map { $0 }
    }

    func topGenres(_ recs: [PlayRecord], limit: Int = 5) -> [(name: String, share: Double)] {
        var secs: [String: Double] = [:]
        var total = 0.0
        for r in recs { if let g = r.genre, !g.isEmpty { secs[g, default: 0] += r.seconds; total += r.seconds } }
        guard total > 0 else { return [] }
        return secs.sorted { $0.value > $1.value }.prefix(limit).map { (name: $0.key, share: $0.value / total) }
    }

    func recentSongIDs(limit: Int) -> [Int] {
        var seen = Set<Int>()
        var out: [Int] = []
        for r in records.reversed() where r.seconds >= Self.countThreshold {
            if seen.insert(r.songID).inserted {
                out.append(r.songID)
                if out.count == limit { break }
            }
        }
        return out
    }

    struct Bucket: Identifiable, Hashable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    func buckets(_ range: StatsRange) -> [Bucket] {
        let cal = Calendar.current
        let unit = range.bucket
        let recs = records(range)
        var sums: [Date: Double] = [:]
        for r in recs {
            let key = cal.dateInterval(of: unit, for: r.start)?.start ?? r.start
            sums[key, default: 0] += r.seconds / 60
        }
        guard let first = range.interval?.start ?? recs.first?.start,
              var date = cal.dateInterval(of: unit, for: first)?.start else { return [] }
        var out: [Bucket] = []
        while date <= .now && out.count < 400 {
            out.append(Bucket(date: date, minutes: sums[date] ?? 0))
            guard let next = cal.date(byAdding: unit, value: 1, to: date) else { break }
            date = next
        }
        return out
    }

    /// Seconds listened per hour of the day (0-23).
    func hourly(_ recs: [PlayRecord]) -> [Double] {
        var h = Array(repeating: 0.0, count: 24)
        let cal = Calendar.current
        for r in recs { h[cal.component(.hour, from: r.start)] += r.seconds }
        return h
    }

    /// Longest run of consecutive days with music, and where it started.
    func longestStreak(_ recs: [PlayRecord]) -> (days: Int, start: Date?) {
        let cal = Calendar.current
        let days = Set(recs.map { cal.startOfDay(for: $0.start) }).sorted()
        var best = 0, bestStart: Date?, run = 0, runStart: Date?
        var prev: Date?
        for d in days {
            if let p = prev, let next = cal.date(byAdding: .day, value: 1, to: p), cal.isDate(next, inSameDayAs: d) {
                run += 1
            } else {
                run = 1
                runStart = d
            }
            if run > best { best = run; bestStart = runStart }
            prev = d
        }
        return (best, bestStart)
    }

    /// The day with the most listening.
    func biggestDay(_ recs: [PlayRecord]) -> (day: Date, seconds: Double, topSong: PlayRecord?)? {
        let cal = Calendar.current
        var groups: [Date: [PlayRecord]] = [:]
        for r in recs { groups[cal.startOfDay(for: r.start), default: []].append(r) }
        guard let best = groups.max(by: { total($0.value) < total($1.value) }) else { return nil }
        var counts: [Int: Int] = [:]
        for r in best.value { counts[r.songID, default: 0] += 1 }
        let topID = counts.max { $0.value < $1.value }?.key
        return (best.key, total(best.value), best.value.last { $0.songID == topID })
    }
}
