import Foundation

/// Little stories hidden in your listening history: binges, comebacks, skips, and how songs climb your charts.
@MainActor
extension StatsStore {
    struct SongFact: Identifiable, Hashable {
        let songID: Int
        let title: String
        let artist: String
        let artworkURL: URL?
        /// What's being counted (times in a row, days, skips, days away...).
        let value: Int
        var id: Int { songID }

        init(_ r: PlayRecord, value: Int) {
            songID = r.songID
            title = r.title
            artist = r.artist.name
            artworkURL = r.artworkURL
            self.value = value
        }
    }

    /// The most times one song was played back to back.
    func binge(_ recs: [PlayRecord]) -> SongFact? {
        var best: (PlayRecord, Int)?
        var run = 0
        var prev: Int?
        for r in recs where r.seconds >= Self.playThreshold {
            run = r.songID == prev ? run + 1 : 1
            prev = r.songID
            if run > (best?.1 ?? 1) { best = (r, run) }
        }
        return best.flatMap { $0.1 >= 3 ? SongFact($0.0, value: $0.1) : nil }
    }

    /// The song played on the most different days.
    func rideOrDie(_ recs: [PlayRecord]) -> SongFact? {
        let cal = Calendar.current
        var days: [Int: Set<Date>] = [:]
        var last: [Int: PlayRecord] = [:]
        for r in recs where r.seconds >= Self.playThreshold {
            days[r.songID, default: []].insert(cal.startOfDay(for: r.start))
            last[r.songID] = r
        }
        guard let top = days.max(by: { $0.value.count < $1.value.count }), top.value.count >= 3, let r = last[top.key] else { return nil }
        return SongFact(r, value: top.value.count)
    }

    /// The song skipped most (played for less than 30 seconds), at least 3 times.
    func mostSkipped(_ recs: [PlayRecord]) -> SongFact? {
        var count: [Int: Int] = [:]
        var last: [Int: PlayRecord] = [:]
        for r in recs where r.seconds < Self.playThreshold && r.origin == .tunes {
            count[r.songID, default: 0] += 1
            last[r.songID] = r
        }
        guard let top = count.max(by: { $0.value < $1.value }), top.value >= 3, let r = last[top.key] else { return nil }
        return SongFact(r, value: top.value)
    }

    /// A song you came back to inside `recs` after the longest break (at least 30 days).
    func comeback(_ recs: [PlayRecord]) -> SongFact? {
        guard let start = recs.first?.start else { return nil }
        var before: [Int: Date] = [:]
        for r in records where r.start < start && r.seconds >= Self.playThreshold { before[r.songID] = r.start }
        var best: (PlayRecord, Int)?
        var seen = Set<Int>()
        for r in recs where r.seconds >= Self.playThreshold && seen.insert(r.songID).inserted {
            guard let prev = before[r.songID] else { continue }
            let gap = Int(r.start.timeIntervalSince(prev) / 86_400)
            if gap > (best?.1 ?? 29) { best = (r, gap) }
        }
        return best.map { SongFact($0.0, value: $0.1) }
    }

    /// The very first song in your history.
    var firstSong: PlayRecord? { records.first { $0.seconds >= Self.countThreshold } }

    /// Albums where you played every song you have from them (at least 4) inside `recs`.
    func albumsCompleted(_ recs: [PlayRecord], library: Library) -> [Album] {
        var played = Set<Int>()
        for r in recs where r.seconds >= Self.playThreshold { played.insert(r.songID) }
        var albums: [Int: (Album, [Int])] = [:]
        for e in library.entries {
            guard let a = e.song.album, a.id > 0 else { continue }
            albums[a.id, default: (a, [])].1.append(e.id)
        }
        return albums.values.filter { $0.1.count >= 4 && $0.1.allSatisfy(played.contains) }.map(\.0).sorted { $0.title < $1.title }
    }

    // MARK: Charts

    /// Plays per song inside an interval.
    func playCounts(from start: Date, to end: Date) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for r in records where r.seconds >= Self.playThreshold && r.start >= start && r.start < end { out[r.songID, default: 0] += 1 }
        return out
    }

    /// Ranked song IDs (most plays first; ties broken by song ID so ranks stay stable).
    func ranking(_ counts: [Int: Int]) -> [Int] {
        counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    struct ChartEntry: Identifiable, Hashable {
        enum Move: Hashable { case new, back, up(Int), down(Int), same }
        let rank: Int
        let songID: Int
        let plays: Int
        let move: Move
        let weeks: Int
        var id: Int { songID }
    }

    struct WeeklyChart: Identifiable {
        let weekStart: Date
        let entries: [ChartEntry]
        var id: Date { weekStart }
    }

    /// Your personal top 20 for each calendar week (newest last), with movement and weeks on the chart.
    func weeklyCharts(maxWeeks: Int = 104) -> [WeeklyChart] {
        memo("weekly-\(maxWeeks)") {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let first = records.first?.start,
              var week = cal.dateInterval(of: .weekOfYear, for: max(first, cal.date(byAdding: .weekOfYear, value: -maxWeeks, to: .now) ?? first))?.start
        else { return [] }
        var byWeek: [Date: [Int: Int]] = [:]
        for r in records where r.seconds >= Self.playThreshold {
            guard let w = cal.dateInterval(of: .weekOfYear, for: r.start)?.start, w >= week else { continue }
            byWeek[w, default: [:]][r.songID, default: 0] += 1
        }
        var out: [WeeklyChart] = []
        var prevRanks: [Int: Int] = [:]
        var everCharted = Set<Int>()
        var weeksOn: [Int: Int] = [:]
        while week <= .now {
            let counts = byWeek[week] ?? [:]
            let top = Array(ranking(counts).prefix(20))
            var entries: [ChartEntry] = []
            var ranks: [Int: Int] = [:]
            for (i, id) in top.enumerated() {
                let rank = i + 1
                ranks[id] = rank
                weeksOn[id, default: 0] += 1
                let move: ChartEntry.Move
                if let p = prevRanks[id] { move = p == rank ? .same : (p > rank ? .up(p - rank) : .down(rank - p)) }
                else { move = everCharted.contains(id) ? .back : .new }
                entries.append(ChartEntry(rank: rank, songID: id, plays: counts[id] ?? 0, move: move, weeks: weeksOn[id] ?? 1))
            }
            everCharted.formUnion(top)
            prevRanks = ranks
            if !entries.isEmpty { out.append(WeeklyChart(weekStart: week, entries: entries)) }
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }
        return out
    }
    }

    /// A song's rank over time: plays in the 4 weeks before each weekly sample, only while inside the top 50.
    func journey(of songID: Int, from start: Date? = nil, to end: Date = .now, samples: Int? = nil) -> [(date: Date, rank: Int?)] {
        guard let firstPlay = records.first(where: { $0.songID == songID && $0.seconds >= Self.playThreshold })?.start else { return [] }
        let from = max(start ?? firstPlay, firstPlay)
        let span = end.timeIntervalSince(from)
        guard span > 0 else { return [] }
        let step: TimeInterval = samples.map { max(86_400, span / Double($0)) } ?? 7 * 86_400
        let window: TimeInterval = samples == nil ? 28 * 86_400 : max(7 * 86_400, min(28 * 86_400, span / 3))
        var out: [(date: Date, rank: Int?)] = []
        var t = from.addingTimeInterval(min(step, span))
        while t <= end.addingTimeInterval(1) {
            let counts = playCounts(from: t.addingTimeInterval(-window), to: t)
            let rank = ranking(counts).firstIndex(of: songID).map { $0 + 1 }
            out.append((date: t, rank: rank.flatMap { $0 <= 50 ? $0 : nil }))
            t = t.addingTimeInterval(step)
            if out.count > 160 { break }
        }
        return out
    }

    // MARK: Days

    /// What you played on this date in earlier years (or a month ago, if there's nothing older).
    func onThisDay(_ date: Date = .now) -> (label: String, songs: [SongStat])? {
        memo("onthisday-\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)") {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        for years in 1...10 {
            guard let day = cal.date(byAdding: .year, value: -years, to: today),
                  let next = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let recs = records(in: DateInterval(start: day, end: next))
            let top = topSongs(recs, limit: 3)
            if !top.isEmpty { return (years == 1 ? "One year ago today" : "\(years) years ago today", top) }
        }
        if let day = cal.date(byAdding: .month, value: -1, to: today), let next = cal.date(byAdding: .day, value: 1, to: day) {
            let top = topSongs(records(in: DateInterval(start: day, end: next)), limit: 3)
            if !top.isEmpty { return ("One month ago today", top) }
        }
        return nil
    }
    }

    /// The last full calendar week (Monday to Sunday) and month.
    static func lastWeek(_ now: Date = .now) -> DateInterval? {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let start = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek) else { return nil }
        return DateInterval(start: start, end: thisWeek)
    }

    static func lastMonth(_ now: Date = .now) -> DateInterval? {
        let cal = Calendar.current
        guard let thisMonth = cal.dateInterval(of: .month, for: now)?.start,
              let start = cal.date(byAdding: .month, value: -1, to: thisMonth) else { return nil }
        return DateInterval(start: start, end: thisMonth)
    }

    /// Your most-played song of last week.
    func songOfTheWeek() -> SongStat? {
        memo("songofweek") {
        guard let w = Self.lastWeek() else { return nil }
        return topSongs(records(in: w), limit: 1).first
    }
    }
}
