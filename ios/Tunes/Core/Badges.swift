import SwiftUI

/// Bronze, silver and gold. Badges are just for showing off: they don't unlock anything else.
enum BadgeTier: Int, Comparable, CaseIterable {
    case none = 0, bronze, silver, gold
    static func < (a: BadgeTier, b: BadgeTier) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .none: "Locked"
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        }
    }

    /// Metal colors: highlight, mid, shadow.
    var metal: [Color] {
        switch self {
        case .none: [Color(white: 0.45), Color(white: 0.3), Color(white: 0.2)]
        case .bronze: [Color(hex: "#F3C08B"), Color(hex: "#C47A3A"), Color(hex: "#6E3B14")]
        case .silver: [Color(hex: "#FFFFFF"), Color(hex: "#C3C8D0"), Color(hex: "#6B7280")]
        case .gold: [Color(hex: "#FFF4B0"), Color(hex: "#F5C04A"), Color(hex: "#9A6A00")]
        }
    }
}

/// One badge: what it counts, and how much is needed for bronze, silver and gold.
struct BadgeDef: Identifiable {
    let id: String
    let name: String
    let icon: String
    let blurb: String
    let unit: String
    let tiers: [Int]

    func tier(for value: Int) -> BadgeTier {
        if value >= tiers[2] { return .gold }
        if value >= tiers[1] { return .silver }
        if value >= tiers[0] { return .bronze }
        return .none
    }

    /// The next goal, or nil once gold.
    func next(after value: Int) -> Int? { tiers.first { value < $0 } }
}

struct BadgeStatus: Identifiable {
    let def: BadgeDef
    let value: Int
    var id: String { def.id }
    var tier: BadgeTier { def.tier(for: value) }
    var progressToNext: Double {
        guard let next = def.next(after: value) else { return 1 }
        let prev = def.tiers.last { $0 <= value } ?? 0
        return Double(value - prev) / Double(max(1, next - prev))
    }
}

enum Badges {
    static let all: [BadgeDef] = [
        BadgeDef(id: "listener", name: "Listener", icon: "headphones", blurb: "Hours of music listened in total.", unit: "hours", tiers: [10, 100, 500]),
        BadgeDef(id: "marathon", name: "Marathon", icon: "figure.run", blurb: "Minutes listened in a single day.", unit: "minutes", tiers: [120, 300, 600]),
        BadgeDef(id: "streak", name: "On a Roll", icon: "flame.fill", blurb: "Days in a row with music.", unit: "days", tiers: [7, 30, 100]),
        BadgeDef(id: "nightOwl", name: "Night Owl", icon: "moon.stars.fill", blurb: "Songs played between midnight and 4 am.", unit: "songs", tiers: [25, 150, 500]),
        BadgeDef(id: "earlyBird", name: "Early Bird", icon: "sunrise.fill", blurb: "Songs played between 5 and 8 am.", unit: "songs", tiers: [25, 150, 500]),
        BadgeDef(id: "explorer", name: "Explorer", icon: "safari.fill", blurb: "Different artists you've listened to.", unit: "artists", tiers: [25, 100, 300]),
        BadgeDef(id: "superfan", name: "Superfan", icon: "star.circle.fill", blurb: "Hours spent with your favorite artist.", unit: "hours", tiers: [5, 25, 100]),
        BadgeDef(id: "onRepeat", name: "On Repeat", icon: "repeat.circle.fill", blurb: "Plays of your most played song.", unit: "plays", tiers: [25, 100, 250]),
        BadgeDef(id: "collector", name: "Collector", icon: "square.stack.3d.up.fill", blurb: "Songs in your library.", unit: "songs", tiers: [50, 250, 1000]),
        BadgeDef(id: "curator", name: "Curator", icon: "music.note.list", blurb: "Playlists you've made.", unit: "playlists", tiers: [3, 10, 25]),
        BadgeDef(id: "heartEyes", name: "Heart Eyes", icon: "heart.circle.fill", blurb: "Songs you've liked.", unit: "likes", tiers: [25, 100, 500]),
        BadgeDef(id: "albumLover", name: "Album Lover", icon: "opticaldisc.fill", blurb: "Albums you've played at least 5 songs from.", unit: "albums", tiers: [5, 25, 100]),
        BadgeDef(id: "genreHopper", name: "Genre Hopper", icon: "shuffle.circle.fill", blurb: "Different genres you've played.", unit: "genres", tiers: [5, 10, 20]),
        BadgeDef(id: "timeTraveler", name: "Time Traveler", icon: "clock.arrow.2.circlepath", blurb: "Decades your music comes from.", unit: "decades", tiers: [3, 5, 7]),
        BadgeDef(id: "follower", name: "Loyal Fan", icon: "person.2.fill", blurb: "Artists you follow.", unit: "artists", tiers: [5, 25, 100]),
        BadgeDef(id: "digger", name: "Crate Digger", icon: "shippingbox.fill", blurb: "Songs you've imported yourself, from YouTube or files.", unit: "songs", tiers: [1, 10, 50]),
        BadgeDef(id: "mover", name: "Moving In", icon: "arrow.right.arrow.left.circle.fill", blurb: "Songs brought over from Spotify playlists.", unit: "songs", tiers: [25, 100, 500]),
        BadgeDef(id: "wrapped", name: "Wrapped Up", icon: "gift.fill", blurb: "Times you've watched your Wrapped.", unit: "times", tiers: [1, 5, 20]),
        BadgeDef(id: "sharer", name: "Spread the Word", icon: "square.and.arrow.up.circle.fill", blurb: "Songs you've shared.", unit: "shares", tiers: [1, 10, 50]),
        BadgeDef(id: "dj", name: "DJ", icon: "dial.medium.fill", blurb: "Songs you've added to the queue.", unit: "songs", tiers: [10, 100, 500]),
        BadgeDef(id: "scratcher", name: "Scratch Master", icon: "record.circle.fill", blurb: "Times you've spun the vinyl player by hand.", unit: "scratches", tiers: [1, 25, 100]),
        BadgeDef(id: "stylist", name: "Stylist", icon: "paintpalette.fill", blurb: "Different themes you've tried.", unit: "themes", tiers: [3, 8, 15]),
        BadgeDef(id: "lyricist", name: "Sing Along", icon: "music.mic.circle.fill", blurb: "Times you've opened the lyrics.", unit: "times", tiers: [5, 50, 200]),
        BadgeDef(id: "veteran", name: "Veteran", icon: "calendar.circle.fill", blurb: "Days since your first play.", unit: "days", tiers: [7, 60, 365]),
        BadgeDef(id: "puzzler", name: "Puzzler", icon: "puzzlepiece.extension.fill", blurb: "Your longest streak of daily games.", unit: "days", tiers: [3, 7, 30]),
        BadgeDef(id: "wordWizard", name: "Word Wizard", icon: "square.grid.3x3.fill", blurb: "Tunedle puzzles solved.", unit: "wins", tiers: [5, 25, 100]),
        BadgeDef(id: "perfectPitch", name: "Perfect Pitch", icon: "ear.fill", blurb: "Earworms named from the 1-second clip.", unit: "songs", tiers: [1, 5, 20]),
        BadgeDef(id: "connected", name: "Connected", icon: "circle.grid.2x2.fill", blurb: "Connections solved without a mistake.", unit: "puzzles", tiers: [1, 10, 50]),
        BadgeDef(id: "higherGround", name: "Higher Ground", icon: "arrow.up.arrow.down.circle.fill", blurb: "Your best Higher or lower run.", unit: "in a row", tiers: [5, 10, 20]),
        BadgeDef(id: "eagleEye", name: "Eagle Eye", icon: "eye.fill", blurb: "Cover Story right on the first try.", unit: "covers", tiers: [3, 15, 50]),
        BadgeDef(id: "lyricLegend", name: "Lyric Legend", icon: "text.quote", blurb: "Finish the lyric with all 3 right.", unit: "games", tiers: [1, 10, 30]),
        BadgeDef(id: "timekeeper", name: "Timekeeper", icon: "hourglass", blurb: "Timelines right on the first check.", unit: "games", tiers: [1, 10, 30]),
        BadgeDef(id: "sherlock", name: "Sherlock", icon: "magnifyingglass.circle.fill", blurb: "Song Detective solved in 3 guesses or fewer.", unit: "cases", tiers: [1, 5, 20]),
        BadgeDef(id: "noLifelines", name: "No Lifelines", icon: "hand.raised.slash.fill", blurb: "Daily puzzles solved without a lifeline.", unit: "puzzles", tiers: [5, 25, 100]),
        BadgeDef(id: "gameNight", name: "Game Night", icon: "gamecontroller.fill", blurb: "Games played.", unit: "games", tiers: [25, 100, 500]),
        BadgeDef(id: "dailySweep", name: "Daily Sweep", icon: "checkmark.seal.fill", blurb: "Days you solved every daily puzzle.", unit: "days", tiers: [1, 5, 20]),
        BadgeDef(id: "blitzMaster", name: "Blitz Master", icon: "bolt.fill", blurb: "Your best Song Blitz score in one minute.", unit: "right", tiers: [10, 15, 25]),
        BadgeDef(id: "lineReader", name: "Line Reader", icon: "quote.bubble.fill", blurb: "Lyric Line rounds with all 5 right.", unit: "rounds", tiers: [1, 10, 30]),
    ]

    /// Works out every badge's current value. Runs in a few milliseconds even with big histories.
    @MainActor
    static func evaluate() -> [BadgeStatus] {
        let app = AppModel.shared
        let lib = app.library
        let counters = app.prefs.data.counters
        // Everything that needs your whole history comes from `facts`, worked out in the background.
        let f = facts
        let cal = Calendar.current
        _ = cal
        func value(_ id: String) -> Int {
            switch id {
            case "listener": return f.hours
            case "marathon": return f.bigDayMinutes
            case "streak": return f.longestStreak
            case "nightOwl": return f.night
            case "earlyBird": return f.early
            case "explorer": return f.artists
            case "superfan": return f.topArtistHours
            case "onRepeat": return f.onRepeat
            case "collector": return lib.entries.count
            case "curator": return app.playlists.manual.count
            case "heartEyes": return lib.liked.count
            case "albumLover": return f.albumLover
            case "genreHopper": return f.genres
            case "timeTraveler": return f.decades
            case "follower": return lib.followed.count
            case "digger": return lib.entries.filter { $0.id < 0 }.count + (counters["filesImported"] ?? 0)
            case "mover": return counters["spotifySongs"] ?? 0
            case "wrapped": return counters["wrappedOpened"] ?? 0
            case "sharer": return counters["shared"] ?? 0
            case "dj": return counters["queued"] ?? 0
            case "scratcher": return counters["vinylScratches"] ?? 0
            case "stylist": return counters.keys.filter { $0.hasPrefix("theme:") }.count
            case "lyricist": return counters["lyricsOpened"] ?? 0
            case "veteran": return f.veteranDays
            case "puzzler": return app.prefs.data.games.values.map(\.bestStreak).max() ?? 0
            case "wordWizard": return counters["tunedleWins"] ?? 0
            case "perfectPitch": return counters["earwormOneSecond"] ?? 0
            case "connected": return counters["connectionsPerfect"] ?? 0
            case "higherGround": return counters["higherLowerBest"] ?? 0
            case "eagleEye": return counters["coverFirstTry"] ?? 0
            case "lyricLegend": return counters["lyricPerfect"] ?? 0
            case "timekeeper": return counters["timelineFirstCheck"] ?? 0
            case "sherlock": return counters["detectiveQuick"] ?? 0
            case "noLifelines": return counters["noLifelines"] ?? 0
            case "gameNight": return counters["gamesPlayed"] ?? 0
            case "dailySweep": return counters["dailySweep"] ?? 0
            case "blitzMaster": return counters["blitzBest"] ?? 0
            case "lineReader": return counters["lineReaderPerfect"] ?? 0
            default: return 0
            }
        }
        return f.empty && lib.entries.isEmpty && counters.isEmpty
            ? Self.all.map { BadgeStatus(def: $0, value: 0) }
            : Self.all.map { BadgeStatus(def: $0, value: value($0.id)) }
    }
}

// MARK: - Medal art

/// A shiny medal: metal ring, the badge's symbol, and a slow sweep of light. Locked medals are grey with a lock.
struct MedalView: View {
    let icon: String
    let tier: BadgeTier
    var size: CGFloat = 64
    var progress: Double = 0
    @State private var shine = false

    var body: some View {
        let m = tier.metal
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [m[0], m[1], m[2]], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(RadialGradient(colors: [m[1], m[2]], center: .center, startRadius: 0, endRadius: size * 0.45))
                .padding(size * 0.1)
                .overlay(Circle().stroke(m[0].opacity(0.7), lineWidth: max(1, size * 0.02)).padding(size * 0.1))
            Image(systemName: icon)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(tier == .none ? Color.white.opacity(0.35) : Color.white)
                .shadow(color: .black.opacity(0.35), radius: size * 0.03, y: size * 0.02)
            if tier != .none {
                // The sweep of light across the metal
                Circle()
                    .fill(AngularGradient(colors: [.clear, .white.opacity(0.55), .clear, .clear], center: .center))
                    .rotationEffect(.degrees(shine ? 360 : 0))
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(size * 0.06)
                    .background(Circle().fill(Color(white: 0.2)))
                    .offset(x: size * 0.32, y: size * 0.32)
            }
            if tier != .gold && progress > 0 {
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-size * 0.05)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: (tier == .gold ? Color.yellow : .black).opacity(tier == .none ? 0.15 : 0.3), radius: size * 0.08, y: size * 0.04)
        .onAppear {
            guard tier != .none, AppModel.shared.prefs.data.animations else { return }
            withAnimation(.linear(duration: tier == .gold ? 4 : 6).repeatForever(autoreverses: false)) { shine = true }
        }
    }
}


// MARK: - History facts (worked out in the background)

/// Numbers from your whole listening history that badges and the Streak theme need. Going through a long
/// history (like an imported Spotify history) takes a moment, so it happens off the main thread and only when
/// your history changed; taps and song changes never wait for it.
struct HistoryFacts {
    var hours = 0, bigDayMinutes = 0, longestStreak = 0, night = 0, early = 0, artists = 0
    var topArtistHours = 0, onRepeat = 0, albumLover = 0, genres = 0, decades = 0, veteranDays = 0
    var streak = StreakInfo()
    var empty = true
    var stamp = ""

    nonisolated static func compute(_ recs: [PlayRecord], albumOf: [Int: Int]) -> HistoryFacts {
        var f = HistoryFacts()
        guard !recs.isEmpty else { return f }
        f.empty = false
        let cal = Calendar.current
        var total = 0.0
        var perDay: [Date: Double] = [:]
        var artists = Set<Int>(), genres = Set<String>(), decades = Set<Int>()
        var artistSeconds: [Int: Double] = [:]
        var songPlays: [Int: Int] = [:]
        var albumSongs: [Int: Set<Int>] = [:]
        var first = Date.distantFuture
        for r in recs {
            total += r.seconds
            if r.start < first { first = r.start }
            for a in r.allArtists { artists.insert(a.id) }
            if let g = r.genre { genres.insert(g) }
            if let y = r.releaseYear, y > 1900 { decades.insert(y / 10) }
            artistSeconds[r.artist.id, default: 0] += r.seconds
            if r.seconds >= 5 { perDay[cal.startOfDay(for: r.start), default: 0] += r.seconds }
            if r.seconds >= 30 {
                songPlays[r.songID, default: 0] += 1
                let h = cal.component(.hour, from: r.start)
                if h < 4 { f.night += 1 } else if h >= 5 && h < 8 { f.early += 1 }
            }
            if let album = albumOf[r.songID] { albumSongs[album, default: []].insert(r.songID) }
        }
        f.hours = Int(total / 3600)
        f.bigDayMinutes = Int((perDay.values.max() ?? 0) / 60)
        f.artists = artists.count
        f.genres = genres.count
        f.decades = decades.count
        f.topArtistHours = Int((artistSeconds.values.max() ?? 0) / 3600)
        f.onRepeat = songPlays.values.max() ?? 0
        f.albumLover = albumSongs.values.filter { $0.count >= 5 }.count
        f.veteranDays = cal.dateComponents([.day], from: first, to: .now).day ?? 0
        // Longest run of days with music, and the current streak (for the Streak theme).
        let days = perDay.keys.sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        f.longestStreak = best
        if let last = days.last {
            var current = 0
            var d = last
            let set = Set(days)
            while set.contains(d) {
                current += 1
                guard let p = cal.date(byAdding: .day, value: -1, to: d) else { break }
                d = p
            }
            let gap = cal.dateComponents([.day], from: last, to: cal.startOfDay(for: .now)).day ?? 0
            let level: Int = switch current {
            case ..<3: 0
            case ..<7: 1
            case ..<14: 2
            case ..<30: 3
            case ..<100: 4
            default: 5
            }
            f.streak = StreakInfo(current: gap <= 1 ? current : 0, level: max(0, level - max(0, gap - 1)))
        }
        return f
    }
}

extension Badges {
    @MainActor static var facts = HistoryFacts()
    @MainActor private static var working = false
    @MainActor private static var again = false

    /// Refreshes `facts` in the background if your history changed, then calls `done` on the main thread.
    @MainActor static func refreshFacts(_ done: (() -> Void)? = nil) {
        let app = AppModel.shared
        let stamp = "\(app.stats.version)-\(app.stats.records.count)"
        guard stamp != facts.stamp else { done?(); return }
        guard !working else { again = true; return }
        working = true
        let recs = app.stats.records
        var albumOf: [Int: Int] = [:]
        for e in app.library.entries { if let a = e.song.album, a.id > 0 { albumOf[e.id] = a.id } }
        Task.detached(priority: .utility) {
            var f = HistoryFacts.compute(recs, albumOf: albumOf)
            f.stamp = stamp
            await MainActor.run {
                facts = f
                working = false
                done?()
                if again { again = false; refreshFacts(done) }
            }
        }
    }
}
