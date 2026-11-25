import AVFoundation
import SwiftUI

// MARK: - Games

enum GameKind: String, CaseIterable, Identifiable {
    case tunedle, connections, earworm, blitz, detective, higherLower, coverStory, finishLyric, lyricLine, timeline
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tunedle: "Tunedle"
        case .connections: "Connections"
        case .earworm: "Earworm"
        case .blitz: "Song Blitz"
        case .lyricLine: "Lyric Line"
        case .detective: "Song Detective"
        case .higherLower: "Higher or lower"
        case .coverStory: "Cover Story"
        case .finishLyric: "Finish the lyric"
        case .timeline: "Timeline"
        }
    }

    var blurb: String {
        switch self {
        case .tunedle: "Guess the song title in 6 tries"
        case .connections: "Sort 16 songs into 4 groups"
        case .earworm: "Name the song from a tiny clip"
        case .blitz: "As many songs as you can in a minute"
        case .lyricLine: "Which song is this lyric from?"
        case .detective: "Find the hidden song from clues"
        case .higherLower: "Which have you played more?"
        case .coverStory: "Guess the blurry cover"
        case .finishLyric: "Fill in the missing word"
        case .timeline: "Put 5 songs in release order"
        }
    }

    var icon: String {
        switch self {
        case .tunedle: "square.grid.3x3.fill"
        case .connections: "circle.grid.2x2.fill"
        case .earworm: "ear.fill"
        case .blitz: "bolt.fill"
        case .lyricLine: "quote.bubble.fill"
        case .detective: "magnifyingglass"
        case .higherLower: "arrow.up.arrow.down"
        case .coverStory: "photo.fill"
        case .finishLyric: "text.quote"
        case .timeline: "calendar"
        }
    }

    var colors: [Color] {
        switch self {
        case .tunedle: [Color(hex: "#22C55E"), Color(hex: "#15803D")]
        case .connections: [Color(hex: "#A855F7"), Color(hex: "#6D28D9")]
        case .earworm: [Color(hex: "#F97316"), Color(hex: "#C2410C")]
        case .blitz: [Color(hex: "#EF4444"), Color(hex: "#B91C1C")]
        case .lyricLine: [Color(hex: "#8B5CF6"), Color(hex: "#5B21B6")]
        case .detective: [Color(hex: "#64748B"), Color(hex: "#334155")]
        case .higherLower: [Color(hex: "#0EA5E9"), Color(hex: "#1D4ED8")]
        case .coverStory: [Color(hex: "#EC4899"), Color(hex: "#BE185D")]
        case .finishLyric: [Color(hex: "#EAB308"), Color(hex: "#A16207")]
        case .timeline: [Color(hex: "#14B8A6"), Color(hex: "#0F766E")]
        }
    }

    var index: UInt64 { UInt64(GameKind.allCases.firstIndex(of: self) ?? 0) }
}

/// The songs the games are built from.
@MainActor
struct GameData {
    let songs: [Song]
    let plays: [Int: Int]
    let top: [Int]
    let liked: Set<Int>
    let added: [Int: Date]
    let genre: [Int: String]
    let followed: [Artist]

    init(_ app: AppModel) {
        let entries = app.library.entries
        songs = entries.map(\.song)
        var p: [Int: Int] = [:]
        for r in app.stats.records where r.seconds >= StatsStore.playThreshold { p[r.songID, default: 0] += 1 }
        plays = p
        top = app.stats.ranking(p)
        liked = Set(entries.filter(\.liked).map(\.id))
        added = Dictionary(entries.map { ($0.id, $0.addedAt) }, uniquingKeysWith: { a, _ in a })
        var g: [Int: String] = [:]
        for e in entries { if let x = e.genre ?? e.song.album?.genre, !x.isEmpty { g[e.id] = x } }
        genre = g
        followed = app.library.followed
    }

    static let minimumSongs = 20
    var enough: Bool { songs.count >= Self.minimumSongs }

    /// Played songs first (so the games are about music you know), then the rest.
    func favorites(_ rng: inout SeededRNG, count: Int = 60) -> [Song] {
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var list = top.prefix(count).compactMap { byID[$0] }
        if list.count < 12 { list += songs.shuffled(using: &rng).filter { s in !list.contains { $0.id == s.id } }.prefix(40) }
        return list.shuffled(using: &rng)
    }

    static func year(_ s: Song) -> Int? { s.album?.year.flatMap { Int($0) }.flatMap { $0 > 1900 ? $0 : nil } }
}

extension GameRecord {
    mutating func finishDaily(won: Bool, today: String, yesterday: String) {
        let continues = lastDaily == yesterday && dailyWon
        lastDaily = today
        dailyWon = won
        played += 1
        if won { self.won += 1 }
        streak = won ? (continues ? streak + 1 : 1) : 0
        bestStreak = max(bestStreak, streak)
    }
}

/// What a game gets from the screen around it: its puzzle seed, moves to replay (saved progress),
/// whether it's only being shown (your finished daily), and where to report moves and the result.
struct GameIO {
    let seed: UInt64
    let moves: [String]
    let readOnly: Bool
    /// Today's puzzle (false for practice rounds).
    let daily: Bool
    let record: (String) -> Void
    let done: (GameResult) -> Void
}

struct GameResult {
    var won: Bool
    var headline: String
    var detail: String
    /// A little row of squares for the share card.
    var marks: [Color] = []
    var song: Song?
    var usedLifeline = false
    /// Badge counters to add one to, and best-ever values to keep.
    var counts: [String] = []
    var bests: [String: Int] = [:]
}

// MARK: - Hub

/// The games section at the bottom of the stats page.
struct GamesSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var playing: GameKind?

    var body: some View {
        let count = app.library.entries.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Games").font(.title3.bold())
                Spacer()
                Text("A new puzzle every day").font(.caption).foregroundStyle(.secondary)
            }
            if count >= GameData.minimumSongs { DailyStreakBanner { playing = $0 } }
            if count < GameData.minimumSongs {
                Label("Download \(GameData.minimumSongs - count) more song\(GameData.minimumSongs - count == 1 ? "" : "s") to unlock the games. They're built from your own music.",
                      systemImage: "lock.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(GameKind.allCases) { g in card(g, locked: count < GameData.minimumSongs) }
            }
        }
        .fullScreenCover(item: $playing) { g in
            GameScreen(kind: g)
                .environment(app).environment(\.look, look).tint(look.accent)
        }
    }

    private func card(_ g: GameKind, locked: Bool) -> some View {
        let rec = app.prefs.data.games[g.rawValue] ?? GameRecord()
        let doneToday = rec.lastDaily == AppModel.dayKey()
        return Button {
            guard !locked else { app.haptic(.warning); return }
            app.haptic(.light)
            playing = g
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: g.icon).font(.title2.weight(.bold))
                    Spacer()
                    if rec.streak > 0 {
                        Label("\(rec.streak)", systemImage: "flame.fill").font(.caption.weight(.heavy))
                            .padding(.horizontal, 8).padding(.vertical, 4).background(.white.opacity(0.22), in: Capsule())
                    }
                }
                Spacer(minLength: 6)
                Text(g.title).font(.headline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.8)
                Text(g.blurb).font(.caption).opacity(0.85).lineLimit(2, reservesSpace: true)
                HStack(spacing: 4) {
                    Image(systemName: locked ? "lock.fill" : (doneToday ? "checkmark.circle.fill" : "sparkles"))
                    Text(locked ? "Locked" : (doneToday ? (rec.dailyWon ? "Solved today" : "Played today") : "Today's puzzle"))
                }
                .font(.caption2.weight(.bold)).opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(LinearGradient(colors: g.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: look.radius(18), style: .continuous))
            .opacity(locked ? 0.55 : 1)
        }
        .buttonStyle(PressStyle())
    }
}

/// The games on their own page (reachable as a route).
struct GamesHubView: View {
    var body: some View {
        ScrollView { GamesSection().padding(16) }
            .themeBackground()
            .navigationTitle("Games")
    }
}

// MARK: - Game screen

/// The frame around every game: daily or practice rounds, saved progress, results, and your finished daily.
struct GameScreen: View {
    let kind: GameKind
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var daily = true
    @State private var reviewing = false
    @State private var seed: UInt64 = 0
    @State private var round = 0
    @State private var result: GameResult?
    @State private var data: GameData?

    private var today: String { AppModel.dayKey() }
    private var record: GameRecord { app.prefs.data.games[kind.rawValue] ?? GameRecord() }
    private var progressKey: String { "\(kind.rawValue)|\(today)" }
    private var dailySeed: UInt64 {
        let days = UInt64(max(0, Date.now.timeIntervalSince1970 / 86_400))
        return days &* 7919 &+ kind.index &* 104_729
    }
    private var finishedToday: Bool { record.lastDaily == today }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [kind.colors[1].mixed(with: .black, by: 0.55), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                header
                if let data {
                    if daily && finishedToday && !reviewing && result == nil {
                        alreadyPlayed
                    } else {
                        if reviewing { reviewBanner }
                        game(data)
                            .id("\(seed)-\(round)-\(reviewing)")
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            if let result {
                ResultCard(kind: kind, result: result, daily: daily, streak: record.streak, next: playAnother, close: { dismiss() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: result != nil)
        .onAppear {
            data = GameData(app)
            seed = dailySeed
            app.player.pause()
            // Keep saved progress for today and yesterday only.
            let yesterday = AppModel.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
            app.prefs.data.gameProgress = app.prefs.data.gameProgress.filter { $0.key.hasSuffix(today) || $0.key.hasSuffix(yesterday) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(.white.opacity(0.12), in: Circle()) }
                .accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.title3.weight(.heavy))
                Text(reviewing ? "Your answer" : (daily ? "Today's puzzle" : "Practice round")).font(.caption.weight(.semibold)).opacity(0.7)
            }
            Spacer()
            if record.streak > 0 {
                Label("\(record.streak)", systemImage: "flame.fill").font(.subheadline.weight(.heavy)).foregroundStyle(.orange)
            }
            Button(daily ? "Practice" : "Daily") {
                withAnimation {
                    daily.toggle()
                    reviewing = false
                    result = nil
                    seed = daily ? dailySeed : UInt64.random(in: 1...UInt64.max)
                    round += 1
                }
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12).frame(height: 32)
            .background(.white.opacity(0.14), in: Capsule())
        }
    }

    private var reviewBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.lastHeadline ?? (record.dailyWon ? "Solved" : "Finished")).font(.headline)
                if let d = record.lastDetail { Text(d).font(.caption).opacity(0.75) }
            }
            Spacer()
            Button("Back") { withAnimation { reviewing = false } }.font(.subheadline.weight(.bold))
        }
        .padding(12)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private var alreadyPlayed: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: record.dailyWon ? "checkmark.seal.fill" : "moon.zzz.fill").font(.system(size: 60)).foregroundStyle(kind.colors[0])
            Text(record.dailyWon ? "You solved today's puzzle" : "You played today's puzzle").font(.title2.weight(.heavy))
            Text("A new one arrives tomorrow. Want another round now?").opacity(0.75).multilineTextAlignment(.center)
            DailyStreakBanner(open: nil)
            GameButton(title: "Play another", color: kind.colors[0], action: playAnother).padding(.top, 8)
            if !(app.prefs.data.gameProgress[progressKey] ?? []).isEmpty {
                Button { withAnimation { reviewing = true; round += 1 } } label: {
                    Text("See your answer").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func game(_ d: GameData) -> some View {
        let saving = daily && !reviewing
        let key = progressKey
        let io = GameIO(seed: seed,
                        moves: daily ? (app.prefs.data.gameProgress[key] ?? []) : [],
                        readOnly: reviewing,
                        daily: daily,
                        record: { m in if saving { app.prefs.data.gameProgress[key, default: []].append(m) } },
                        done: finish)
        switch kind {
        case .tunedle: TunedleGame(data: d, io: io)
        case .connections: ConnectionsGame(data: d, io: io)
        case .earworm: EarwormGame(data: d, io: io)
        case .detective: DetectiveGame(data: d, io: io)
        case .higherLower: HigherLowerGame(data: d, io: io)
        case .coverStory: CoverStoryGame(data: d, io: io)
        case .finishLyric: LyricGame(data: d, io: io)
        case .timeline: TimelineGame(data: d, io: io)
        case .lyricLine: LyricLineGame(data: d, io: io)
        case .blitz: BlitzGame(data: d, io: io)
        }
    }

    private func finish(_ r: GameResult) {
        guard !reviewing else { return }
        app.haptic(r.won ? .success : .warning)
        if daily && !finishedToday {
            var rec = record
            let yesterday = AppModel.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
            rec.finishDaily(won: r.won, today: today, yesterday: yesterday)
            rec.lastHeadline = r.headline
            rec.lastDetail = r.detail
            app.prefs.data.games[kind.rawValue] = rec
            if r.won && !r.usedLifeline { app.prefs.data.counters["noLifelines", default: 0] += 1 }
            let all = GameKind.allCases.allSatisfy { k in
                let g = app.prefs.data.games[k.rawValue]
                return g?.lastDaily == today && g?.dailyWon == true
            }
            if GameKind.allCases.allSatisfy({ app.prefs.data.games[$0.rawValue]?.lastDaily == today }) {
                app.prefs.data.counters["allDone:\(today)"] = 1
            }
            if all && app.prefs.data.counters["sweep:\(today)"] == nil {
                app.prefs.data.counters["sweep:\(today)"] = 1
                app.prefs.data.counters["dailySweep", default: 0] += 1
            }
        }
        for c in r.counts { app.prefs.data.counters[c, default: 0] += 1 }
        for (k, v) in r.bests { app.prefs.data.counters[k] = max(app.prefs.data.counters[k] ?? 0, v) }
        app.bump("gamesPlayed")
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.6)) { result = r }
    }

    private func playAnother() {
        withAnimation {
            daily = false
            reviewing = false
            result = nil
            seed = UInt64.random(in: 1...UInt64.max)
            round += 1
        }
    }
}

/// The result, as a card at the bottom: the finished puzzle stays visible above it.
private struct ResultCard: View {
    let kind: GameKind
    let result: GameResult
    let daily: Bool
    let streak: Int
    let next: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: result.won ? "star.circle.fill" : "music.note").font(.system(size: 40)).foregroundStyle(kind.colors[0])
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.headline).font(.title3.weight(.black))
                    Text(result.detail).font(.subheadline).opacity(0.85)
                }
                Spacer()
                if daily && streak > 0 { Label("\(streak)", systemImage: "flame.fill").font(.headline).foregroundStyle(.orange) }
            }
            if let s = result.song {
                HStack(spacing: 10) {
                    s.artwork(44).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text(s.title).font(.subheadline.weight(.bold)).lineLimit(1)
                        Text(s.artistLine).font(.caption).opacity(0.75).lineLimit(1)
                    }
                    Spacer()
                }
            }
            if !result.marks.isEmpty {
                HStack(spacing: 4) {
                    ForEach(result.marks.indices, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(result.marks[i]).frame(width: 16, height: 16) }
                    if result.usedLifeline { Image(systemName: "lifepreserver").font(.caption).opacity(0.8) }
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                if let img = shareImage() {
                    ShareLink(item: img, preview: SharePreview("\(kind.title) on Tunes", image: img)) {
                        Image(systemName: "square.and.arrow.up").font(.headline).frame(width: 50, height: 50)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Share")
                }
                GameButton(title: "Next puzzle", color: kind.colors[0], action: next)
                Button(action: close) {
                    Image(systemName: "xmark").font(.headline).frame(width: 50, height: 50).background(.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel("Close")
            }
        }
        .padding(18)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
    }

    @MainActor
    private func shareImage() -> Image? {
        let card = VStack(alignment: .leading, spacing: 10) {
            Label(kind.title, systemImage: kind.icon).font(.system(size: 26, weight: .heavy))
            Text(result.headline).font(.system(size: 20, weight: .bold))
            if !result.marks.isEmpty {
                HStack(spacing: 5) {
                    ForEach(result.marks.indices, id: \.self) { i in RoundedRectangle(cornerRadius: 4).fill(result.marks[i]).frame(width: 26, height: 26) }
                }
            }
            if result.usedLifeline { Label("Used a lifeline", systemImage: "lifepreserver").font(.system(size: 14, weight: .semibold)) }
            Text("Tunes · \(Date.now.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 14, weight: .semibold)).opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(width: 400, alignment: .leading)
        .background(LinearGradient(colors: kind.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        let r = ImageRenderer(content: card)
        r.scale = 3
        return r.uiImage.map { Image(uiImage: $0) }
    }
}

/// A big primary button used by the games.
private struct GameButton: View {
    let title: String
    var color: Color = .white
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                .background(color.opacity(disabled ? 0.3 : 1), in: Capsule())
                .foregroundStyle(color == .white ? Color.black : Color.white)
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
    }
}

/// A round "Who Wants to Be a Millionaire" lifeline button, crossed out once used.
private struct LifelineButton: View {
    let title: String
    let icon: String
    let used: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(hex: "#1E3A8A")).overlay(Circle().stroke(Color(hex: "#FBBF24"), lineWidth: 2))
                    Image(systemName: icon).font(.subheadline.weight(.bold)).foregroundStyle(Color(hex: "#FBBF24"))
                    if used {
                        Image(systemName: "xmark").font(.system(size: 26, weight: .heavy)).foregroundStyle(.red)
                    }
                }
                .frame(width: 40, height: 40)
                Text(title).font(.caption.weight(.bold))
            }
            .opacity(used ? 0.6 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(used)
    }
}

private struct NotEnough: View {
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note.list").font(.system(size: 48)).opacity(0.6)
            Text(text).multilineTextAlignment(.center).opacity(0.8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Search your songs to make a guess (Earworm and Song Detective).
private struct SongSearch: View {
    let songs: [Song]
    let exclude: Set<Int>
    let pick: (Song) -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 6) {
            TextField("Search your songs", text: $query)
                .padding(12).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(songs.filter { $0.matches(q) && !exclude.contains($0.id) }.prefix(20)) { s in
                            Button { query = ""; pick(s) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(s.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(s.artistLine).font(.caption).opacity(0.7).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().opacity(0.3)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }
}

private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}

// MARK: - Tunedle

private struct TunedleGame: View {
    let data: GameData
    let io: GameIO

    @State private var target: (song: Song, word: String)?
    @State private var valid: Set<String> = []
    @State private var guesses: [String] = []
    @State private var current = ""
    @State private var shake = 0
    @State private var over = false
    @State private var warning: String?
    private let rows = 6

    enum Mark { case hit, near, miss }

    static func normalize(_ title: String) -> String? {
        var t = title
        for sep in [" (", " [", " - ", " feat", " ft."] { if let r = t.range(of: sep, options: .caseInsensitive) { t = String(t[..<r.lowerBound]) } }
        t = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).uppercased()
        let letters = t.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) || $0 == " " }
        let cleaned = String(String.UnicodeScalarView(letters)).split(separator: " ").joined(separator: " ")
        guard cleaned.allSatisfy({ ("A"..."Z").contains($0) || $0 == " " }) else { return nil }
        let count = cleaned.filter { $0 != " " }.count
        guard (3...11).contains(count), cleaned.split(separator: " ").count <= 3 else { return nil }
        return cleaned
    }

    static func pattern(_ w: String) -> [Int] {
        let parts: [Substring] = w.split(separator: Character(" "))
        return parts.map { $0.count }
    }

    var body: some View {
        Group {
            if let target {
                VStack(spacing: 10) {
                    hints(target)
                    board(target.word)
                        .modifier(Shake(amount: CGFloat(shake)))
                    if let warning { Text(warning).font(.subheadline.weight(.bold)).foregroundStyle(.orange).transition(.opacity) }
                    Spacer(minLength: 4)
                    keyboard(target.word)
                }
            } else {
                NotEnough(text: "None of your song titles fit this game yet. Download a few more songs.")
            }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        var rng = SeededRNG(seed: io.seed)
        var byPattern: [[Int]: Set<String>] = [:]
        for s in data.songs { if let w = Self.normalize(s.title) { byPattern[Self.pattern(w), default: []].insert(w.replacingOccurrences(of: " ", with: "")) } }
        let candidates = data.favorites(&rng, count: 150).compactMap { s in Self.normalize(s.title).map { (s, $0) } }
        // Prefer answers that share their letter pattern with at least 6 of your songs.
        let pick = candidates.first { (byPattern[Self.pattern($0.1)]?.count ?? 0) >= 6 }
            ?? candidates.first { (byPattern[Self.pattern($0.1)]?.count ?? 0) >= 3 }
            ?? candidates.first
        guard let pick else { return }
        target = (pick.0, pick.1)
        valid = byPattern[Self.pattern(pick.1)] ?? []
        for m in io.moves { apply(m, live: false) }
    }

    private func letters(_ word: String) -> [Character] { word.filter { $0 != " " }.map { $0 } }

    private func marks(_ guess: String, _ word: String) -> [Mark] {
        let answer = letters(word)
        let g = Array(guess)
        var out = [Mark](repeating: .miss, count: answer.count)
        var left: [Character: Int] = [:]
        for (i, c) in answer.enumerated() { if g.indices.contains(i), g[i] == c { out[i] = .hit } else { left[c, default: 0] += 1 } }
        for i in answer.indices where out[i] != .hit && g.indices.contains(i) {
            if let n = left[g[i]], n > 0 { out[i] = .near; left[g[i]] = n - 1 }
        }
        return out
    }

    private func color(_ m: Mark?) -> Color {
        switch m {
        case .hit: Color(hex: "#22C55E")
        case .near: Color(hex: "#EAB308")
        case .miss: Color(white: 0.28)
        case nil: Color.white.opacity(0.08)
        }
    }

    private func hints(_ t: (song: Song, word: String)) -> some View {
        let wrong = guesses.count
        return VStack(spacing: 4) {
            Text("One of your songs · \(letters(t.word).count) letters").font(.subheadline.weight(.semibold)).opacity(0.8)
            if wrong >= 2 {
                Text("The artist starts with “\(t.song.artist.name.prefix(1))”").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
            }
            if wrong >= 4 {
                Text(GameData.year(t.song).map { "Released in \($0)" } ?? "From \(t.song.album?.title ?? "an album")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.yellow)
            }
            if wrong >= 5 {
                Text("The title starts with “\(t.word.prefix(1))”").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
            }
        }
        .animation(.easeInOut, value: wrong)
    }

    private func board(_ word: String) -> some View {
        let words: [Int] = Self.pattern(word)
        let total = CGFloat(letters(word).count)
        let gaps = CGFloat(words.count - 1) * 14
        let room: CGFloat = UIScreen.main.bounds.width - 60 - gaps
        let size: CGFloat = min(44, room / max(total, 1) - 4)
        return VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { r in
                let text: [Character] = r < guesses.count ? Array(guesses[r]) : (r == guesses.count ? Array(current) : [])
                let ms: [Mark]? = r < guesses.count ? marks(guesses[r], word) : nil
                HStack(spacing: 14) {
                    ForEach(words.indices, id: \.self) { w in
                        HStack(spacing: 4) {
                            ForEach(0..<words[w], id: \.self) { k in
                                let i = words.prefix(w).reduce(0, +) + k
                                Tile(char: text.indices.contains(i) ? text[i] : nil, color: color(ms?[i]), revealed: ms != nil, delay: Double(i) * 0.08, size: size)
                            }
                        }
                    }
                }
            }
        }
    }

    private func keyboard(_ word: String) -> some View {
        var best: [Character: Mark] = [:]
        for g in guesses {
            for (c, m) in zip(Array(g), marks(g, word)) {
                let old = best[c]
                if old == .hit { continue }
                if m == .hit || old == nil || (old == .miss && m == .near) { best[c] = m }
            }
        }
        let rowsOfKeys = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
        return VStack(spacing: 7) {
            ForEach(rowsOfKeys.indices, id: \.self) { r in
                HStack(spacing: 5) {
                    if r == 2 { key("Enter", wide: true) { submit(word) } }
                    ForEach(Array(rowsOfKeys[r]), id: \.self) { c in
                        key(String(c), color: best[c].map { color($0) }) { type(c, word) }
                    }
                    if r == 2 { key("⌫", wide: true) { if !current.isEmpty { current.removeLast() } } }
                }
            }
        }
        .disabled(over || io.readOnly)
    }

    private func key(_ label: String, wide: Bool = false, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button {
            AppModel.shared.haptic(.light)
            action()
        } label: {
            Text(label).font(.system(size: wide ? 13 : 17, weight: .bold))
                .frame(width: wide ? 52 : 30, height: 46)
                .background(color ?? Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func type(_ c: Character, _ word: String) {
        guard current.count < letters(word).count else { return }
        current.append(c)
        warning = nil
    }

    private func submit(_ word: String) {
        guard current.count == letters(word).count else {
            withAnimation(.default) { shake += 1 }
            AppModel.shared.haptic(.warning)
            return
        }
        guard valid.contains(current) else {
            withAnimation(.default) { shake += 1; warning = "Not one of your songs" }
            AppModel.shared.haptic(.warning)
            return
        }
        let g = current
        current = ""
        io.record(g)
        apply(g, live: true)
    }

    private func apply(_ g: String, live: Bool) {
        guard let t = target, !over else { return }
        if live { withAnimation { guesses.append(g) } } else { guesses.append(g) }
        let won = g == String(letters(t.word))
        guard won || guesses.count >= rows else { return }
        over = true
        guard live else { return }
        let squares = guesses.map { gg -> Color in
            let ms = marks(gg, t.word)
            return ms.allSatisfy { $0 == .hit } ? Color(hex: "#22C55E") : (ms.contains { $0 != .miss } ? Color(hex: "#EAB308") : Color(white: 0.3))
        }
        io.done(GameResult(won: won, headline: won ? "Got it in \(guesses.count)!" : "So close",
                           detail: won ? "You know your library." : "It was \(t.song.title).", marks: squares, song: t.song,
                           counts: won ? ["tunedleWins"] : []))
    }
}

private struct Tile: View {
    let char: Character?
    let color: Color
    let revealed: Bool
    let delay: Double
    let size: CGFloat
    @State private var flipped = false

    var body: some View {
        Text(char.map { String($0) } ?? "")
            .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
            .frame(width: size, height: size)
            .background(flipped ? color : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(char != nil && !flipped ? 0.5 : 0.15), lineWidth: 1.5))
            .rotation3DEffect(.degrees(flipped ? 360 : 0), axis: (x: 1, y: 0, z: 0))
            .scaleEffect(char != nil && !revealed ? 1.04 : 1)
            .animation(.spring(response: 0.25), value: char)
            .onAppear { if revealed { flipped = true } }
            .onChange(of: revealed) { _, on in
                if on { withAnimation(.easeInOut(duration: 0.45).delay(delay)) { flipped = true } }
            }
    }
}

// MARK: - Connections

/// Word families for Connections, in English and Danish.
private enum WordFamilies {
    static let all: [(String, Set<String>)] = [
        ("A color in the title", ["red", "blue", "green", "yellow", "black", "white", "pink", "purple", "orange", "gold", "golden", "silver", "grey", "gray", "rød", "blå", "grøn", "gul", "sort", "hvid", "lyserød", "lilla"]),
        ("A number in the title", ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "hundred", "thousand", "million", "first", "last", "tre", "fire", "fem", "seks", "syv", "otte", "ti"]),
        ("Time in the title", ["day", "night", "morning", "midnight", "tonight", "today", "tomorrow", "yesterday", "summer", "winter", "spring", "autumn", "monday", "friday", "saturday", "sunday", "forever", "time", "nat", "dag", "morgen", "sommer", "vinter", "aften", "tid", "altid"]),
        ("Weather in the title", ["rain", "sun", "sunshine", "snow", "storm", "thunder", "lightning", "cloud", "clouds", "wind", "fog", "ice", "cold", "heat", "regn", "sol", "sne", "vind", "kulde"]),
        ("A place in the title", ["city", "town", "home", "paris", "london", "tokyo", "york", "california", "hollywood", "street", "road", "highway", "beach", "ocean", "sea", "moon", "mars", "heaven", "hell", "byen", "hjem", "havet", "vejen", "gaden"]),
        ("An animal in the title", ["dog", "cat", "bird", "birds", "wolf", "lion", "tiger", "horse", "snake", "fish", "butterfly", "bee", "fox", "bear", "hund", "kat", "fugl", "ulv", "hest"]),
        ("Food in the title", ["cherry", "cherries", "apple", "peach", "lemon", "lemonade", "strawberry", "watermelon", "banana", "honey", "sugar", "candy", "cake", "milk", "wine", "coffee", "kaffe", "æble", "jordbær", "slik", "sukker"]),
        ("The body in the title", ["heart", "eyes", "eye", "hands", "hand", "head", "lips", "face", "skin", "blood", "bones", "soul", "mind", "hjerte", "øjne", "hænder", "hoved", "blod"]),
        ("Love in the title", ["love", "lover", "kiss", "baby", "darling", "sweetheart", "crush", "elsker", "kærlighed", "kys", "skat"]),
    ]
    static let stop: Set<String> = ["the", "and", "you", "your", "for", "with", "that", "this", "but", "not", "are", "was", "all", "from", "feat", "remix", "version", "edit", "live", "mix", "radio", "original", "og", "det", "der", "jeg", "til", "med", "som", "har", "ikke", "mig", "dig", "min", "din"]
    static func words(_ title: String) -> Set<String> {
        var t = title.lowercased()
        if let r = t.range(of: " (") { t = String(t[..<r.lowerBound]) }
        return Set(t.split { !$0.isLetter && $0 != "'" }.map(String.init))
    }
}

private struct ConnectionsGame: View {
    let data: GameData
    let io: GameIO

    struct Group: Identifiable {
        let id: Int
        let name: String
        let songs: [Song]
        let color: Color
    }

    @State private var groups: [Group] = []
    @State private var tiles: [Song] = []
    @State private var picked: Set<Int> = []
    @State private var solved: [Group] = []
    @State private var mistakes = 0
    @State private var shake = 0
    @State private var toast: String?
    @State private var history: [Color] = []
    @State private var over = false

    /// Yellow (easiest) to purple (trickiest), like the real game.
    private static let palette = [Color(hex: "#EAB308"), Color(hex: "#22C55E"), Color(hex: "#3B82F6"), Color(hex: "#A855F7")]

    var body: some View {
        SwiftUI.Group {
            if groups.count == 4 {
                VStack(spacing: 12) {
                    Text("Find four groups of four").font(.subheadline.weight(.semibold)).opacity(0.8)
                    ForEach(solved) { g in
                        VStack(spacing: 2) {
                            Text(g.name.uppercased()).font(.caption.weight(.heavy))
                            Text(g.songs.map(\.title).joined(separator: ", ")).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(10)
                        .background(g.color, in: RoundedRectangle(cornerRadius: 12))
                        .transition(.scale.combined(with: .opacity))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(tiles) { s in tile(s) }
                    }
                    .modifier(Shake(amount: CGFloat(shake)))
                    HStack(spacing: 6) {
                        Text("Mistakes left").font(.caption).opacity(0.7)
                        ForEach(0..<4, id: \.self) { i in Circle().fill(i < 4 - mistakes ? Color.white : Color.white.opacity(0.15)).frame(width: 10, height: 10) }
                    }
                    if let toast { Text(toast).font(.subheadline.weight(.bold)).padding(.horizontal, 14).padding(.vertical, 8).background(.white.opacity(0.15), in: Capsule()) }
                    if !over && !io.readOnly {
                        HStack(spacing: 10) {
                            Button("Shuffle") { withAnimation(.spring) { tiles.shuffle() } }
                                .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).frame(height: 46).background(.white.opacity(0.12), in: Capsule())
                            Button("Deselect") { withAnimation { picked = [] } }
                                .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).frame(height: 46).background(.white.opacity(0.12), in: Capsule())
                            GameButton(title: "Submit", disabled: picked.count != 4) {
                                let move = picked.sorted().map(String.init).joined(separator: ",")
                                io.record(move)
                                apply(move, live: true)
                            }
                        }
                    }
                }
            } else {
                NotEnough(text: "Connections needs a bit more variety: a few artists or albums with 4 or more songs each.")
            }
        }
        .onAppear(perform: setup)
    }

    private func tile(_ s: Song) -> some View {
        let on = picked.contains(s.id)
        return Button {
            AppModel.shared.haptic(.selection)
            withAnimation(.spring(response: 0.25)) {
                if on { picked.remove(s.id) } else if picked.count < 4 { picked.insert(s.id) }
            }
        } label: {
            Text(s.title).font(.system(size: 12, weight: .bold)).lineLimit(3).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                .padding(4)
                .frame(maxWidth: .infinity).frame(height: 72)
                .background(on ? Color.white : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(on ? Color.black : Color.white)
                .scaleEffect(on ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .disabled(over || io.readOnly)
    }

    private struct Rule {
        let name: String
        /// 0 easiest … 3 trickiest.
        let level: Int
        let test: (Song) -> Bool
    }

    private func rules(_ songs: [Song]) -> [Rule] {
        var out: [Rule] = []
        func add(_ name: String, _ level: Int, _ test: @escaping (Song) -> Bool) {
            if songs.filter(test).count >= 4 { out.append(Rule(name: name, level: level, test: test)) }
        }
        for (_, list) in Dictionary(grouping: songs, by: { $0.artist.id }) where list.count >= 4 {
            let a = list[0].artist
            add("Songs by \(a.name)", 0) { $0.artist.id == a.id }
        }
        for (_, list) in Dictionary(grouping: songs.filter { ($0.album?.id ?? 0) > 0 }, by: { $0.album?.id ?? 0 }) where list.count >= 4 {
            if let al = list[0].album { add("From \(al.title)", 0) { $0.album?.id == al.id } }
        }
        for (y, list) in Dictionary(grouping: songs.filter { GameData.year($0) != nil }, by: { GameData.year($0) ?? 0 }) where list.count >= 4 {
            add("Released in \(y)", 1) { GameData.year($0) == y }
        }
        for (d, list) in Dictionary(grouping: songs.filter { GameData.year($0) != nil }, by: { (GameData.year($0) ?? 0) / 10 * 10 }) where list.count >= 4 {
            add("From the \(d)s", 1) { (GameData.year($0) ?? 0) / 10 * 10 == d }
        }
        let top10 = Set(data.top.prefix(10))
        add("In your top 10", 1) { top10.contains($0.id) }
        let liked = data.liked
        add("In your liked songs", 2) { liked.contains($0.id) }
        let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
        let added = data.added
        add("Downloaded this month", 2) { (added[$0.id] ?? .distantPast) > monthAgo }
        add("Has a featured artist", 2) { !$0.featured.isEmpty }
        add("Explicit", 2) { $0.explicit }
        add("Over 5 minutes long", 2) { $0.duration > 300 }
        add("Under 2:30", 2) { $0.duration > 0 && $0.duration < 150 }
        let genre = data.genre
        for (g, list) in Dictionary(grouping: songs.filter { genre[$0.id] != nil }, by: { genre[$0.id] ?? "" }) where list.count >= 4 {
            add("Genre: \(g)", 1) { genre[$0.id] == g }
        }
        add("One-word titles", 3) { WordFamilies.words($0.title).count == 1 }
        add("Titles that ask a question", 3) { $0.title.contains("?") }
        add("A digit in the title", 3) { $0.title.contains { $0.isNumber } }
        for (name, set) in WordFamilies.all {
            add(name, 3) { !WordFamilies.words($0.title).isDisjoint(with: set) }
        }
        // A word several of your titles share.
        var counts: [String: Int] = [:]
        for s in songs { for w in WordFamilies.words(s.title) where w.count >= 3 && !WordFamilies.stop.contains(w) { counts[w, default: 0] += 1 } }
        for (w, n) in counts where n >= 4 {
            add("“\(w.capitalized)” in the title", 3) { WordFamilies.words($0.title).contains(w) }
        }
        return out
    }

    private func setup() {
        var rng = SeededRNG(seed: io.seed)
        let songs = data.songs
        let all = rules(songs).sorted { $0.name < $1.name }.shuffled(using: &rng)
        // A mix of difficulties when possible: at most two groups of the same level on the first pass.
        var chosen: [(Rule, [Song])] = []
        var used = Set<Int>()
        for pass in 0..<2 {
            for rule in all where chosen.count < 4 {
                if chosen.contains(where: { $0.0.name == rule.name }) { continue }
                if pass == 0 && chosen.filter({ $0.0.level == rule.level }).count >= 2 { continue }
                // One answer only: the new rule can't fit songs already picked, and its songs can't fit earlier rules.
                guard !chosen.contains(where: { $0.1.contains(where: rule.test) }) else { continue }
                let fits = songs.filter { s in rule.test(s) && !used.contains(s.id) && !chosen.contains { $0.0.test(s) } }
                guard fits.count >= 4 else { continue }
                let four = Array(fits.shuffled(using: &rng).prefix(4))
                chosen.append((rule, four))
                used.formUnion(four.map(\.id))
            }
        }
        guard chosen.count == 4 else { return }
        let ordered = chosen.sorted { $0.0.level < $1.0.level }
        groups = ordered.enumerated().map { i, c in Group(id: i, name: c.0.name, songs: c.1, color: Self.palette[i]) }
        tiles = ordered.flatMap(\.1).shuffled(using: &rng)
        for m in io.moves { apply(m, live: false) }
    }

    private func apply(_ move: String, live: Bool) {
        guard !over else { return }
        let parts: [Substring] = move.split(separator: Character(","))
        let ids = Set(parts.compactMap { Int($0) })
        guard ids.count == 4 else { return }
        let remaining = groups.filter { g in !solved.contains { $0.id == g.id } }
        if let g = remaining.first(where: { Set($0.songs.map(\.id)) == ids }) {
            if live { AppModel.shared.haptic(.success) }
            history.append(g.color)
            withAnimation(live ? .spring(response: 0.45, dampingFraction: 0.8) : nil) {
                solved.append(g)
                tiles.removeAll { ids.contains($0.id) }
                picked = []
                toast = nil
            }
            if solved.count == 4 {
                over = true
                if live {
                    io.done(GameResult(won: true, headline: mistakes == 0 ? "Perfect!" : "All four groups!",
                                       detail: mistakes == 0 ? "Not a single mistake." : "With \(mistakes) mistake\(mistakes == 1 ? "" : "s").",
                                       marks: history, counts: mistakes == 0 ? ["connectionsPerfect"] : []))
                }
            }
        } else {
            let close = remaining.contains { Set($0.songs.map(\.id)).intersection(ids).count == 3 }
            if live { AppModel.shared.haptic(.warning) }
            history.append(Color(white: 0.3))
            withAnimation(live ? .default : nil) { shake += 1; mistakes += 1; toast = close ? "One away…" : nil; picked = [] }
            if mistakes >= 4 {
                over = true
                withAnimation(live ? .spring : nil) { solved = groups; tiles = [] }
                if live { io.done(GameResult(won: false, headline: "Out of mistakes", detail: "Here's how the groups went together.", marks: history)) }
            }
        }
    }
}

// MARK: - Earworm

private struct EarwormGame: View {
    let data: GameData
    let io: GameIO

    @State private var target: Song?
    @State private var start: Double = 30
    @State private var step = 0
    @State private var wrong: [Song] = []
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var over = false
    private let clips: [Double] = [1, 2, 4, 7, 11, 16]

    var body: some View {
        SwiftUI.Group {
            if let target {
                VStack(spacing: 14) {
                    clipBar
                    Button(action: play) {
                        Image(systemName: over ? (playing ? "pause.fill" : "play.fill") : (playing ? "waveform" : "play.fill"))
                            .font(.system(size: 34, weight: .bold))
                            .symbolEffect(.variableColor.iterative, isActive: playing && !over)
                            .frame(width: 90, height: 90)
                            .background(GameKind.earworm.colors[0], in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Play the clip")
                    Text("Clip: \(Int(clips[step])) second\(clips[step] == 1 ? "" : "s")").font(.subheadline.weight(.semibold)).opacity(0.8)
                    ForEach(wrong) { s in
                        Label(s.title, systemImage: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.red.opacity(0.9))
                    }
                    if over {
                        HStack(spacing: 10) {
                            target.artwork(50).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text(target.title).font(.headline)
                                Text(target.artistLine).font(.caption).opacity(0.7)
                            }
                            Spacer()
                        }
                        .padding(12).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    } else if !io.readOnly {
                        SongSearch(songs: data.songs, exclude: Set(wrong.map(\.id))) { s in act("G:\(s.id)") }
                        Button(step < clips.count - 1 ? "Skip (+\(Int(clips[step + 1] - clips[step]))s)" : "Give up") { act("K") }
                            .font(.subheadline.weight(.bold)).opacity(0.8)
                    }
                }
            } else {
                NotEnough(text: "Earworm needs downloaded songs to play clips from.")
            }
        }
        .onAppear(perform: setup)
        .onDisappear { player?.stop() }
    }

    private var clipBar: some View {
        GeometryReader { g in
            let w: CGFloat = g.size.width
            let reach: CGFloat = over ? w : w * CGFloat(clips[step]) / 16
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(.white.opacity(0.25)).frame(width: reach)
                Capsule().fill(GameKind.earworm.colors[0]).frame(width: reach * CGFloat(progress))
                ForEach(clips, id: \.self) { c in
                    Rectangle().fill(.black.opacity(0.4)).frame(width: 2).offset(x: w * CGFloat(c) / 16 - 1)
                }
            }
        }
        .frame(height: 12)
    }

    private func setup() {
        var rng = SeededRNG(seed: io.seed)
        let lib = AppModel.shared.library
        guard let s = data.favorites(&rng).first(where: { lib.entry($0.id).map { FileManager.default.fileExists(atPath: $0.fileURL.path) } ?? false }),
              let e = lib.entry(s.id) else { return }
        target = s
        start = max(0, (e.highlightStart ?? 30))
        player = try? AVAudioPlayer(contentsOf: e.fileURL)
        player?.prepareToPlay()
        for m in io.moves { apply(m, live: false) }
    }

    private func play() {
        if over {
            // After the round: play or pause the whole song.
            guard let p = player else { return }
            if p.isPlaying { p.pause(); playing = false } else { p.play(); playing = true }
            return
        }
        guard let p = player, !playing else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        p.currentTime = min(start, max(0, p.duration - 17))
        p.volume = 1
        p.play()
        playing = true
        progress = 0
        let length = over ? 16 : clips[step]
        withAnimation(.linear(duration: length)) { progress = 1 }
        Task {
            try? await Task.sleep(for: .seconds(length))
            p.pause()
            playing = false
        }
    }

    private func act(_ m: String) {
        io.record(m)
        apply(m, live: true)
    }

    private func apply(_ m: String, live: Bool) {
        guard let t = target, !over else { return }
        if m.hasPrefix("G:"), let id = Int(m.dropFirst(2)) {
            if id == t.id { finish(won: true, live: live); return }
            if let s = data.songs.first(where: { $0.id == id }) { withAnimation(live ? .default : nil) { wrong.append(s) } }
            if live { AppModel.shared.haptic(.warning) }
        }
        if step < clips.count - 1 { withAnimation(live ? .default : nil) { step += 1 } } else { finish(won: false, live: live) }
    }

    private func finish(won: Bool, live: Bool) {
        guard let t = target, !over else { return }
        over = true
        player?.stop()
        playing = false
        guard live else { return }
        // Play the song from where the clip started, and let it keep going.
        if let p = player {
            p.currentTime = min(start, max(0, p.duration - 17))
            p.play()
            playing = true
            progress = 1
        }
        let marks = (0..<clips.count).map { i -> Color in
            i < step ? Color(white: 0.3) : (i == step ? (won ? Color(hex: "#22C55E") : Color(white: 0.3)) : Color.white.opacity(0.12))
        }
        io.done(GameResult(won: won, headline: won ? "Got it in \(Int(clips[step]))s!" : "It was…",
                           detail: won ? "Your ears know your music." : "Better luck next time.", marks: marks, song: t,
                           counts: won && step == 0 ? ["earwormOneSecond"] : []))
    }
}

// MARK: - Song Detective

private struct DetectiveGame: View {
    let data: GameData
    let io: GameIO

    @State private var target: Song?
    @State private var guesses: [Song] = []
    @State private var over = false

    enum Hit { case yes, close, no }

    var body: some View {
        SwiftUI.Group {
            if let target {
                VStack(spacing: 10) {
                    Text(over ? "Case closed in \(guesses.count) guess\(guesses.count == 1 ? "" : "es")" : "Which of your songs is it? Every guess gives you clues.")
                        .font(.subheadline.weight(.semibold)).opacity(0.8).multilineTextAlignment(.center)
                    if !over && !io.readOnly {
                        SongSearch(songs: data.songs, exclude: Set(guesses.map(\.id))) { s in
                            io.record("G:\(s.id)")
                            apply(s.id, live: true)
                        }
                    }
                    header
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(guesses.reversed()) { g in row(g, target) }
                        }
                    }
                }
            } else {
                NotEnough(text: "Song Detective needs a few more songs.")
            }
        }
        .onAppear(perform: setup)
    }

    private let columns = ["Artist", "Album", "Year", "Genre", "Length", "Plays"]

    private var header: some View {
        HStack(spacing: 4) {
            Text("Song").frame(width: 84, alignment: .leading)
            ForEach(columns, id: \.self) { c in Text(c).frame(maxWidth: .infinity) }
        }
        .font(.system(size: 10, weight: .heavy)).opacity(0.7)
    }

    private func row(_ g: Song, _ t: Song) -> some View {
        let cells = clues(g, t)
        return HStack(spacing: 4) {
            Text(g.title).font(.system(size: 11, weight: .bold)).lineLimit(2)
                .frame(width: 84, alignment: .leading)
            ForEach(cells.indices, id: \.self) { i in
                Text(cells[i].1).font(.system(size: 10, weight: .bold)).lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(color(cells[i].0), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func color(_ h: Hit) -> Color {
        switch h {
        case .yes: Color(hex: "#22C55E")
        case .close: Color(hex: "#EAB308")
        case .no: Color(white: 0.25)
        }
    }

    private func arrow(_ mine: Double, _ theirs: Double) -> String { theirs > mine ? "▲" : (theirs < mine ? "▼" : "") }

    private func clues(_ g: Song, _ t: Song) -> [(Hit, String)] {
        let artist: Hit = g.artist.id == t.artist.id ? .yes : (t.allArtists.contains { a in g.allArtists.contains { $0.id == a.id } } ? .close : .no)
        let album: Hit = (g.album?.id ?? -1) == (t.album?.id ?? -2) ? .yes : .no
        var year: (Hit, String) = (.no, "?")
        if let gy = GameData.year(g), let ty = GameData.year(t) {
            year = (gy == ty ? .yes : (abs(gy - ty) <= 2 ? .close : .no), "\(gy) \(arrow(Double(gy), Double(ty)))")
        }
        let gg = data.genre[g.id], tg = data.genre[t.id]
        let genre: Hit = gg != nil && gg == tg ? .yes : .no
        let dg = g.duration, dt = t.duration
        let length: (Hit, String) = (abs(dg - dt) < 2 ? .yes : (abs(dg - dt) <= 20 ? .close : .no), "\(Fmt.time(dg)) \(abs(dg - dt) < 2 ? "" : arrow(dg, dt))")
        let pg = Double(data.plays[g.id] ?? 0), pt = Double(data.plays[t.id] ?? 0)
        let plays: (Hit, String) = (pg == pt ? .yes : (abs(pg - pt) <= max(2, pt * 0.2) ? .close : .no), "\(Int(pg)) \(arrow(pg, pt))")
        return [(artist, g.artist.name), (album, g.album?.title ?? "–"), year, (genre, gg ?? "–"), length, plays]
    }

    private func setup() {
        var rng = SeededRNG(seed: io.seed)
        target = data.favorites(&rng).first
        for m in io.moves { if m.hasPrefix("G:"), let id = Int(m.dropFirst(2)) { apply(id, live: false) } }
    }

    private func apply(_ id: Int, live: Bool) {
        guard let t = target, !over, let s = data.songs.first(where: { $0.id == id }) else { return }
        withAnimation(live ? .spring(response: 0.4) : nil) { guesses.append(s) }
        guard id == t.id else {
            if live { AppModel.shared.haptic(.light) }
            return
        }
        over = true
        guard live else { return }
        io.done(GameResult(won: true, headline: "Solved in \(guesses.count)!", detail: guesses.count <= 3 ? "Sharp detective work." : "Case closed.",
                           marks: guesses.map { $0.id == t.id ? Color(hex: "#22C55E") : Color(white: 0.3) }, song: t,
                           counts: guesses.count <= 3 ? ["detectiveQuick"] : []))
    }
}

// MARK: - Higher or lower

private struct HigherLowerGame: View {
    let data: GameData
    let io: GameIO

    @State private var deck: [Song] = []
    @State private var i = 0
    @State private var score = 0
    @State private var revealed = false
    @State private var shownCount = 0
    @State private var lastRight: Bool?
    @State private var over = false
    @AppStorage("higherLowerHowTo") private var seenHowTo = false
    /// Practice only: keep going until the first wrong answer.
    @State private var endless = false
    private let goal = 10
    private var best: Int { AppModel.shared.prefs.data.counters["higherLowerBest"] ?? 0 }

    var body: some View {
        SwiftUI.Group {
            if deck.count > i + 1 {
                let a = deck[i], b = deck[i + 1]
                VStack(spacing: 14) {
                    if !seenHowTo {
                        Text("You see how many times you've played the top song. Guess if you've played the bottom one more or fewer times.")
                            .font(.caption).opacity(0.8).multilineTextAlignment(.center)
                            .padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !io.daily && !io.readOnly && score == 0 && !revealed {
                        Picker("Mode", selection: Binding(get: { endless }, set: { endless = $0; i = 0; setup() })) {
                            Text("10 songs").tag(false)
                            Text("Endless").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Text(endless ? "Run \(score) · Best \(max(best, score))" : "Score \(score) / \(goal)").font(.headline.monospacedDigit())
                    known(a)
                    mystery(b)
                }
            } else if deck.isEmpty {
                NotEnough(text: "Play a few more songs first, so there's something to compare.")
            }
        }
        .onAppear(perform: setup)
    }

    private func known(_ s: Song) -> some View {
        HStack(spacing: 14) {
            s.artwork(64).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.headline).lineLimit(2)
                Text(s.artistLine).font(.caption).opacity(0.7).lineLimit(1)
                Text("You've played this \(data.plays[s.id] ?? 0) times").font(.subheadline.weight(.heavy)).foregroundStyle(GameKind.higherLower.colors[0])
            }
            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .id("known-\(s.id)")
    }

    private func mystery(_ s: Song) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                s.artwork(64).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.title).font(.headline).lineLimit(2)
                    Text(s.artistLine).font(.caption).opacity(0.7).lineLimit(1)
                }
                Spacer()
                Text(revealed ? "\(shownCount)" : "?")
                    .font(.system(size: 36, weight: .black, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(revealed ? (lastRight == true ? Color.green : Color.red) : Color.white)
            }
            Text(revealed ? "plays" : "More or fewer plays?").font(.subheadline.weight(.semibold)).opacity(0.8)
            HStack(spacing: 10) {
                GameButton(title: "Fewer plays ▼", color: GameKind.higherLower.colors[1], disabled: revealed || over || io.readOnly) { act("L") }
                GameButton(title: "More plays ▲", color: GameKind.higherLower.colors[0], disabled: revealed || over || io.readOnly) { act("H") }
            }
        }
        .padding(14)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(GameKind.higherLower.colors[0].opacity(0.6), lineWidth: 2))
        .id("mystery-\(s.id)")
    }

    private func setup() {
        var rng = SeededRNG(seed: io.seed)
        deck = []
        deck = more(&rng, limit: endless ? 400 : goal + 1)
        guard deck.count >= 2 else { deck = []; return }
        for m in io.moves { apply(m, live: false) }
    }

    /// More songs for the deck, never two with the same play count back to back.
    private func more(_ rng: inout SeededRNG, limit: Int) -> [Song] {
        let played = data.songs.filter { (data.plays[$0.id] ?? 0) > 0 }.shuffled(using: &rng)
        guard played.count >= 6 else { return [] }
        var out: [Song] = []
        var last = deck.last
        for s in played where out.count < limit {
            if let l = last, data.plays[l.id] == data.plays[s.id] || l.id == s.id { continue }
            out.append(s)
            last = s
        }
        return out
    }

    private func act(_ m: String) {
        seenHowTo = true
        io.record(m)
        apply(m, live: true)
    }

    private func apply(_ m: String, live: Bool) {
        guard !over, deck.count > i + 1 else { return }
        let a = data.plays[deck[i].id] ?? 0, b = data.plays[deck[i + 1].id] ?? 0
        let right = m == "H" ? b > a : b < a
        if right { score += 1 }
        if endless && right && i + 2 >= deck.count {
            var rng = SeededRNG(seed: UInt64.random(in: 1...UInt64.max))
            deck += more(&rng, limit: 400)
        }
        let end = !right || i + 2 >= deck.count
        guard live else {
            if end { over = true; revealed = true; shownCount = b; lastRight = right } else { i += 1 }
            return
        }
        lastRight = right
        withAnimation(.spring) { revealed = true }
        withAnimation(.easeOut(duration: 0.8)) { shownCount = b }
        AppModel.shared.haptic(right ? .success : .warning)
        if end { over = true }
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            if end {
                let won = endless ? score >= 5 : score >= min(goal, deck.count - 1) / 2
                io.done(GameResult(won: won, headline: "\(score) in a row", detail: right ? "You went the distance." : "It had \(b) plays.",
                                   marks: (0..<score).map { _ in Color(hex: "#22C55E") } + (right ? [] : [Color(white: 0.3)]),
                                   bests: ["higherLowerBest": score]))
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    i += 1
                    revealed = false
                    shownCount = 0
                    lastRight = nil
                }
            }
        }
    }
}

// MARK: - Cover Story

private struct CoverStoryGame: View {
    let data: GameData
    let io: GameIO

    /// One choice: a single (by song) or an album (by album), with a song to take the cover from.
    struct Choice: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        let cover: Song
    }

    @State private var albums = false
    @State private var answer: Choice?
    @State private var choices: [Choice] = []
    @State private var image: UIImage?
    @State private var step = 0
    @State private var out: Set<Int> = []
    @State private var removed: Set<Int> = []
    @State private var anchor = UnitPoint.center
    @State private var over = false
    @State private var lifeline = false
    private let zooms: [CGFloat] = [6, 4, 2.6, 1.7, 1]
    private let blurs: [CGFloat] = [24, 14, 8, 3, 0]

    var body: some View {
        SwiftUI.Group {
            if let answer {
                VStack(spacing: 14) {
                    Text(albums ? "Which album?" : "Which song?").font(.headline)
                    ZStack {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                                .scaleEffect(over ? 1 : zooms[step], anchor: anchor)
                                .blur(radius: over ? 0 : blurs[step])
                        } else {
                            answer.cover.artwork(260).scaleEffect(zooms[step], anchor: anchor).blur(radius: blurs[step])
                        }
                    }
                    .frame(width: 260, height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .animation(.easeInOut(duration: 0.6), value: step)
                    HStack(spacing: 6) {
                        ForEach(0..<zooms.count, id: \.self) { i in Capsule().fill(i <= step ? GameKind.coverStory.colors[0] : Color.white.opacity(0.2)).frame(height: 5) }
                    }
                    .frame(width: 200)
                    VStack(spacing: 8) {
                        ForEach(choices) { c in choiceRow(c, answer: answer) }
                    }
                    LifelineButton(title: "50:50", icon: "circle.lefthalf.filled", used: lifeline || over || io.readOnly) { act("L") }
                }
            } else {
                NotEnough(text: "Cover Story needs songs with a few different covers.")
            }
        }
        .onAppear(perform: setup)
    }

    private func choiceRow(_ c: Choice, answer: Choice) -> some View {
        let gone = out.contains(c.id) || removed.contains(c.id)
        return Button { act("P:\(c.id)") } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(c.subtitle).font(.caption).opacity(0.7).lineLimit(1)
                }
                Spacer()
                if out.contains(c.id) { Image(systemName: "xmark").foregroundStyle(.red) }
                if over && c.id == answer.id { Image(systemName: "checkmark").foregroundStyle(.green) }
            }
            .padding(12)
            .background(.white.opacity(gone ? 0.03 : 0.12), in: RoundedRectangle(cornerRadius: 12))
            .opacity(removed.contains(c.id) ? 0.25 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(gone || over || io.readOnly)
    }

    private func setup() {
        var rng = SeededRNG(seed: io.seed)
        let withArt = data.favorites(&rng, count: 200).filter { $0.artworkURL != nil || FileManager.default.fileExists(atPath: $0.localArtworkURL.path) }
        let perAlbum = Dictionary(grouping: data.songs.filter { ($0.album?.id ?? 0) > 0 }, by: { $0.album?.id ?? 0 })
        // Singles: a single, or the only song you have from its album.
        var singles: [Choice] = []
        var seenCovers = Set<Int>()
        for s in withArt {
            let aid = s.album?.id ?? -s.id
            let isSingle = s.album?.recordType?.lowercased() == "single" || (perAlbum[aid]?.count ?? 1) <= 1
            guard isSingle, seenCovers.insert(aid).inserted else { continue }
            singles.append(Choice(id: s.id, title: s.title, subtitle: s.artistLine, cover: s))
        }
        var albumChoices: [Choice] = []
        for s in withArt {
            guard let al = s.album, al.id > 0, (perAlbum[al.id]?.count ?? 0) >= 2, !albumChoices.contains(where: { $0.id == al.id }) else { continue }
            albumChoices.append(Choice(id: al.id, title: al.title, subtitle: al.artist?.name ?? s.artist.name, cover: s))
        }
        let canSingles = singles.count >= 4, canAlbums = albumChoices.count >= 4
        guard canSingles || canAlbums else { return }
        albums = canSingles && canAlbums ? Bool.random(using: &rng) : canAlbums
        let picks = Array((albums ? albumChoices : singles).prefix(4))
        answer = picks[0]
        choices = picks.shuffled(using: &rng)
        anchor = UnitPoint(x: Double.random(in: 0.25...0.75, using: &rng), y: Double.random(in: 0.25...0.75, using: &rng))
        let cover = picks[0].cover
        Task { image = await ImageCache.shared.image(local: cover.localArtworkURL, remote: cover.artworkURL, maxPixel: 600) }
        for m in io.moves { apply(m, live: false) }
    }

    private func act(_ m: String) {
        io.record(m)
        apply(m, live: true)
    }

    private func apply(_ m: String, live: Bool) {
        guard let a = answer, !over else { return }
        if m == "L" {
            guard !lifeline else { return }
            lifeline = true
            var rng = SeededRNG(seed: io.seed &+ 5)
            let wrongs = choices.filter { $0.id != a.id && !out.contains($0.id) }.shuffled(using: &rng).prefix(2)
            withAnimation(live ? .easeInOut(duration: 0.5) : nil) { removed.formUnion(wrongs.map(\.id)) }
            return
        }
        guard m.hasPrefix("P:"), let id = Int(m.dropFirst(2)) else { return }
        if id == a.id {
            over = true
            withAnimation(live ? .default : nil) { step = zooms.count - 1 }
            guard live else { return }
            let marks = (0..<zooms.count).map { $0 < out.count ? Color(white: 0.3) : ($0 == out.count ? Color(hex: "#22C55E") : Color.white.opacity(0.12)) }
            io.done(GameResult(won: true, headline: out.isEmpty ? "First try!" : "Got it!", detail: "You'd know that cover anywhere.",
                               marks: marks, song: albums ? nil : a.cover, usedLifeline: lifeline, counts: out.isEmpty ? ["coverFirstTry"] : []))
        } else {
            if live { AppModel.shared.haptic(.warning) }
            withAnimation(live ? .default : nil) { out.insert(id); step = min(zooms.count - 1, step + 1) }
            let left = choices.filter { !out.contains($0.id) && !removed.contains($0.id) }
            if left.count <= 1 {
                over = true
                if live { io.done(GameResult(won: false, headline: "It was \(a.title)", detail: "Covers can be tricky up close.", usedLifeline: lifeline)) }
            }
        }
    }
}

// MARK: - Finish the lyric

private struct LyricGame: View {
    let data: GameData
    let io: GameIO

    struct Question: Identifiable {
        let id: Int
        let song: Song
        let before: String?
        let line: String
        let answer: String
        let choices: [String]
    }

    @State private var questions: [Question] = []
    @State private var index = 0
    @State private var picked: [Int: String] = [:]
    @State private var score = 0
    @State private var marks: [Color] = []
    @State private var loading = true
    @State private var audienceFor: Int?
    @State private var votes: [String: Int] = [:]
    @State private var over = false

    var body: some View {
        SwiftUI.Group {
            if loading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView().tint(.white).scaleEffect(1.4)
                    Text("Finding lyrics from your songs…").opacity(0.8)
                    Spacer()
                }
            } else if questions.count == 3 {
                questionView(questions[min(index, 2)])
            } else {
                NotEnough(text: "Couldn't find lyrics for your songs right now. Connect to the internet and try again, or open the lyrics on a few songs.")
            }
        }
        .task { await setup() }
    }

    private func questionView(_ q: Question) -> some View {
        VStack(spacing: 14) {
            Text("Line \(q.id + 1) of 3").font(.subheadline.weight(.semibold)).opacity(0.7)
            HStack(spacing: 12) {
                q.song.artwork(48).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading) {
                    Text(q.song.title).font(.headline).lineLimit(1)
                    Text(q.song.artistLine).font(.caption).opacity(0.7).lineLimit(1)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                if let b = q.before { Text(b).font(.body).opacity(0.5) }
                Text(display(q)).font(.title3.weight(.bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            if audienceFor == q.id { AudienceChart(choices: q.choices, votes: votes) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(q.choices, id: \.self) { c in
                    Button { act("A:\(q.id):\(c)") } label: {
                        Text(c).font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                            .background(background(c, q), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(picked[q.id] != nil || over || io.readOnly)
                }
            }
            LifelineButton(title: "Ask the Audience", icon: "person.3.fill", used: audienceFor != nil || over || io.readOnly || picked[q.id] != nil) {
                act("L:\(q.id)")
            }
        }
        .id(q.id)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func display(_ q: Question) -> String {
        let fill = picked[q.id] ?? "_____"
        guard let r = q.line.range(of: q.answer, options: [.caseInsensitive]) else { return q.line }
        return q.line.replacingCharacters(in: r, with: fill)
    }

    private func background(_ c: String, _ q: Question) -> Color {
        guard let p = picked[q.id] else { return .white.opacity(0.12) }
        if c == q.answer { return Color(hex: "#22C55E") }
        if c == p { return Color(hex: "#EF4444") }
        return .white.opacity(0.06)
    }

    private static func clean(_ w: Substring) -> String {
        String(w.unicodeScalars.filter { CharacterSet.letters.contains($0) || $0 == "'" }.map(Character.init))
    }

    /// Questions from a song's lyrics (up to `max`).
    private static func makeQuestions(_ lyr: Lyrics, song: Song, max: Int, rng: inout SeededRNG) -> [Question] {
        let lines = lyr.lines.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let good = lines.indices.filter { i in
            let w = lines[i].split(separator: " ")
            return w.count >= 4 && lines[i].count <= 80 && w.contains { clean($0).count >= 4 }
        }.shuffled(using: &rng)
        let vocabulary = Set(lines.flatMap { $0.split(separator: " ").map(clean) }.filter { $0.count >= 4 }.map { $0.lowercased() })
        var out: [Question] = []
        var usedLines = Set<String>()
        for li in good where out.count < max {
            let line = lines[li]
            guard usedLines.insert(line.lowercased()).inserted else { continue }
            let words = line.split(separator: " ").map(clean).filter { $0.count >= 4 }
            guard let answer = words.randomElement(using: &rng) else { continue }
            let inLine = Set(words.map { $0.lowercased() })
            var pool = Array(vocabulary.subtracting(inLine)).sorted()
            if pool.count < 3 { pool += ["night", "heart", "dream", "never", "always", "falling", "again", "tonight"].filter { !inLine.contains($0) } }
            let capital = answer.first?.isUppercase == true
            let wrong: [String] = pool.shuffled(using: &rng).prefix(3).map { w in capital ? w.prefix(1).uppercased() + w.dropFirst() : w }
            guard wrong.count == 3 else { continue }
            out.append(Question(id: 0, song: song, before: li > 0 ? lines[li - 1] : nil, line: line, answer: answer,
                                choices: ([answer] + wrong).shuffled(using: &rng)))
        }
        return out
    }

    @MainActor
    private func setup() async {
        guard questions.isEmpty else { return }
        var rng = SeededRNG(seed: io.seed)
        let candidates = data.favorites(&rng, count: 120)
        var out: [Question] = []
        var fetched = 0
        // Saved lyrics first, then fetch a few online if needed.
        for pass in 0..<2 where out.count < 3 {
            for s in candidates where out.count < 3 {
                if out.contains(where: { $0.song.id == s.id }) { continue }
                var lyr = LyricsService.cached(s.id)
                if lyr == nil && pass == 1 && fetched < 12 && !AppModel.shared.prefs.data.offline {
                    fetched += 1
                    lyr = await LyricsService.fetch(s)
                }
                guard let l = lyr, !l.instrumental, l.lines.count >= 4 else { continue }
                out += Self.makeQuestions(l, song: s, max: 1, rng: &rng)
            }
        }
        // Very few songs with lyrics: take more lines from the ones there are.
        if out.count < 3 {
            for q in out where out.count < 3 {
                if let l = LyricsService.cached(q.song.id) {
                    out += Self.makeQuestions(l, song: q.song, max: 3 - out.count, rng: &rng).filter { n in !out.contains { $0.line == n.line } }
                }
            }
        }
        questions = Array(out.prefix(3)).enumerated().map { i, q in
            Question(id: i, song: q.song, before: q.before, line: q.line, answer: q.answer, choices: q.choices)
        }
        loading = false
        for m in io.moves { apply(m, live: false) }
    }

    private func act(_ m: String) {
        io.record(m)
        apply(m, live: true)
    }

    /// The audience's votes: an unsure crowd. The right word usually gets 30–50% with a wrong word close behind,
    /// and about a quarter of the time a believable wrong word wins.
    private func audienceVotes(_ q: Question) -> [String: Int] {
        var rng = SeededRNG(seed: io.seed &+ UInt64(q.id) &* 31)
        var weights: [String: Double] = [:]
        for c in q.choices where c != q.answer {
            var w = Double.random(in: 0.5...1, using: &rng)
            if c.count == q.answer.count { w += 0.4 }
            if c.first?.lowercased() == q.answer.first?.lowercased() { w += 0.4 }
            weights[c] = w
        }
        let decoy = weights.max { $0.value < $1.value }?.key ?? q.choices.first { $0 != q.answer } ?? q.answer
        let fooled = Double.random(in: 0...1, using: &rng) < 0.25
        let right = fooled ? Int.random(in: 22...32, using: &rng) : Int.random(in: 30...50, using: &rng)
        let second = fooled ? right + Int.random(in: 3...10, using: &rng) : max(8, right - Int.random(in: 5...15, using: &rng))
        var result: [String: Int] = [q.answer: right, decoy: second]
        let others = q.choices.filter { $0 != q.answer && $0 != decoy }
        var rest = max(0, 100 - right - second)
        for (k, c) in others.enumerated() {
            let share = k == others.count - 1 ? rest : Int(Double(rest) * Double.random(in: 0.35...0.65, using: &rng))
            result[c] = share
            rest -= share
        }
        return result
    }

    private func apply(_ m: String, live: Bool) {
        guard !over, questions.count == 3 else { return }
        let parts: [String] = m.split(separator: Character(":"), maxSplits: 2).map { String($0) }
        guard parts.count >= 2, let qid = Int(parts[1]), questions.indices.contains(qid) else { return }
        let q = questions[qid]
        if parts[0] == "L" {
            guard audienceFor == nil else { return }
            votes = audienceVotes(q)
            withAnimation(live ? .spring : nil) { audienceFor = qid }
            return
        }
        guard parts[0] == "A", parts.count == 3, picked[qid] == nil else { return }
        let c = parts[2]
        let right = c == q.answer
        withAnimation(live ? .spring(response: 0.3) : nil) { picked[qid] = c }
        if right { score += 1 }
        marks.append(right ? Color(hex: "#22C55E") : Color(white: 0.3))
        if live { AppModel.shared.haptic(right ? .success : .warning) }
        let last = qid >= 2
        if last { over = true }
        guard live else {
            if !last { index = qid + 1 }
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if last {
                // A line answered with the audience's help doesn't count as word perfect.
                let perfect = score == 3 && audienceFor == nil
                io.done(GameResult(won: score >= 2, headline: "\(score) of 3",
                                   detail: perfect ? "Word perfect." : (score >= 2 ? "You know the words." : "Time to sing along more."),
                                   marks: marks, usedLifeline: audienceFor != nil, counts: perfect ? ["lyricPerfect"] : []))
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index = qid + 1 }
            }
        }
    }
}

/// The audience voting: dots lighting up in the answer colors while bars rise.
private struct AudienceChart: View {
    let choices: [String]
    let votes: [String: Int]
    @State private var shown: CGFloat = 0
    private static let colors = [Color(hex: "#F97316"), Color(hex: "#3B82F6"), Color(hex: "#22C55E"), Color(hex: "#A855F7")]

    private var order: [Int] { choices.indices.flatMap { i in Array(repeating: i, count: votes[choices[i]] ?? 0) } }

    var body: some View {
        let order = self.order
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(7), spacing: 3), count: 25), spacing: 3) {
                ForEach(0..<100, id: \.self) { k in
                    Circle()
                        .fill(k < order.count && CGFloat(k) / 100 < shown ? Self.colors[order[k] % 4] : Color.white.opacity(0.12))
                        .frame(width: 7, height: 7)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(choices.indices, id: \.self) { i in bar(i) }
            }
            .frame(height: 120)
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { withAnimation(.easeOut(duration: 2)) { shown = 1 } }
    }

    private func bar(_ i: Int) -> some View {
        let v = CGFloat(votes[choices[i]] ?? 0)
        return VStack(spacing: 4) {
            Text("\(Int(v * shown))%").font(.caption.weight(.heavy).monospacedDigit())
            RoundedRectangle(cornerRadius: 4).fill(Self.colors[i % 4]).frame(height: max(4, 80 * v / 100 * shown))
            Text(choices[i]).font(.system(size: 10, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Timeline

private struct TimelineGame: View {
    let data: GameData
    let io: GameIO

    @State private var order: [Song] = []
    @State private var tries = 0
    @State private var checked = false
    @State private var over = false
    @State private var call: FriendCall?
    @State private var calling = false

    private var correct: [Song] { order.sorted { (GameData.year($0) ?? 0) < (GameData.year($1) ?? 0) } }

    var body: some View {
        SwiftUI.Group {
            if order.count == 5 {
                ScrollView {
                VStack(spacing: 12) {
                    Text("Oldest at the top. Drag to reorder.").font(.subheadline.weight(.semibold)).opacity(0.8)
                    list
                    if let call { FriendBubble(call: call, ringing: calling) }
                    if !over && !io.readOnly {
                        GameButton(title: tries == 0 ? "Check" : "Check again", color: GameKind.timeline.colors[0]) {
                            act("C:" + order.map { String($0.id) }.joined(separator: ","))
                        }
                        if tries == 1 && checked { Text("Green ones are right. One more try.").font(.caption).opacity(0.8) }
                        LifelineButton(title: "Phone a Friend", icon: "phone.fill", used: call != nil) { act("F") }
                    }
                }
                .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            } else {
                NotEnough(text: "Timeline needs songs from at least 5 different years.")
            }
        }
        .onAppear(perform: setup)
    }

    private var list: some View {
        let right = correct
        return List {
            ForEach(Array(order.enumerated()), id: \.element.id) { i, s in
                HStack(spacing: 12) {
                    s.artwork(46).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.subheadline.weight(.bold)).lineLimit(1)
                        Text(s.artistLine).font(.caption).opacity(0.7).lineLimit(1)
                    }
                    Spacer()
                    if checked {
                        Text(GameData.year(s).map(String.init) ?? "").font(.headline.monospacedDigit())
                            .foregroundStyle(right[i].id == s.id ? Color.green : Color.red)
                    }
                }
                .listRowBackground(checked ? (right[i].id == s.id ? Color.green.opacity(0.25) : Color.red.opacity(0.2)) : Color.white.opacity(0.08))
                .foregroundStyle(.white)
            }
            .onMove { from, to in
                guard !over && !io.readOnly else { return }
                order.move(fromOffsets: from, toOffset: to)
                checked = false
                AppModel.shared.haptic(.selection)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(over || io.readOnly ? .inactive : .active))
        .scrollDisabled(true)
        .frame(height: 5 * 66)
    }

    private func setup() {
        var rng = SeededRNG(seed: io.seed)
        var years = Set<Int>()
        var picks: [Song] = []
        for s in data.favorites(&rng, count: 150) where picks.count < 5 {
            guard let y = GameData.year(s), !years.contains(y) else { continue }
            years.insert(y)
            picks.append(s)
        }
        guard picks.count == 5 else { return }
        var shuffled = picks.shuffled(using: &rng)
        if shuffled.map(\.id) == picks.sorted(by: { (GameData.year($0) ?? 0) < (GameData.year($1) ?? 0) }).map(\.id) { shuffled.reverse() }
        order = shuffled
        for m in io.moves { apply(m, live: false) }
    }

    private func act(_ m: String) {
        io.record(m)
        apply(m, live: true)
    }

    private func apply(_ m: String, live: Bool) {
        guard !over else { return }
        if m == "F" {
            guard call == nil else { return }
            call = FriendCall.make(order: order, correct: correct, data: data, seed: io.seed)
            guard live else { return }
            calling = true
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.spring) { calling = false }
            }
            return
        }
        guard m.hasPrefix("C:") else { return }
        let idParts: [Substring] = m.dropFirst(2).split(separator: Character(","))
        let ids = idParts.compactMap { Int($0) }
        let byID = Dictionary(order.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newOrder = ids.compactMap { byID[$0] }
        if newOrder.count == 5 { order = newOrder }
        tries += 1
        withAnimation(live ? .default : nil) { checked = true }
        let right = zip(order, correct).filter { $0.0.id == $0.1.id }.count
        if right == 5 || tries >= 2 { over = true }
        guard live else { return }
        if right == 5 {
            io.done(GameResult(won: true, headline: tries == 1 ? "Perfect order!" : "Sorted!", detail: "You know your music history.",
                               marks: Array(repeating: Color(hex: "#22C55E"), count: 5), usedLifeline: call != nil,
                               counts: tries == 1 ? ["timelineFirstCheck"] : []))
        } else if tries >= 2 {
            AppModel.shared.haptic(.warning)
            io.done(GameResult(won: false, headline: "\(right) of 5 in place", detail: "The years are shown next to each song.",
                               marks: zip(order, correct).map { $0.0.id == $0.1.id ? Color(hex: "#22C55E") : Color(white: 0.3) },
                               usedLifeline: call != nil))
        } else {
            AppModel.shared.haptic(.warning)
        }
    }
}

/// Phone a Friend: a fan (or a friend) gives one true hint about the timeline.
private struct FriendCall {
    let name: String
    let color: Color
    let artist: Artist?
    let text: String

    static let names = ["Emil", "Freja", "Noah", "Ida", "Oscar", "Alma", "William", "Clara", "Lucas", "Ella", "Sofie", "Malthe", "Maja", "Viktor", "Nora"]
    static let colors = ["#F97316", "#22C55E", "#3B82F6", "#A855F7", "#EC4899", "#14B8A6", "#EAB308", "#EF4444"]

    @MainActor
    static func make(order: [Song], correct: [Song], data: GameData, seed: UInt64) -> FriendCall {
        var rng = SeededRNG(seed: seed &+ 99)
        let name = names.randomElement(using: &rng) ?? "Alex"
        let color = Color(hex: colors.randomElement(using: &rng) ?? "#3B82F6")
        func y(_ s: Song) -> Int { GameData.year(s) ?? 0 }
        let oldest = correct[0], newest = correct[4]
        // Who calls: a fan of an artist in the puzzle, a fan of someone you follow, or a friend.
        let roll = Int.random(in: 0..<3, using: &rng)
        if roll == 0, let s = order.randomElement(using: &rng) {
            let fan = "I know my \(s.artist.name)."
            let text: String
            if s.id == oldest.id { text = "\(fan) “\(s.title)” is the oldest one on that list." }
            else if s.id == newest.id { text = "\(fan) “\(s.title)” is the newest of those." }
            else if Bool.random(using: &rng) { text = "\(fan) “\(s.title)” came out in \(y(s)), no doubt." }
            else {
                let low = y(s) - Int.random(in: 0...1, using: &rng)
                text = "\(fan) “\(s.title)”… around \(low) or \(low + 1)?"
            }
            return FriendCall(name: name, color: color, artist: s.artist, text: text)
        }
        let followed = roll == 1 ? data.followed.randomElement(using: &rng) : nil
        // Prefer a hint about songs that are in the wrong place right now.
        let wrong = order.indices.filter { order[$0].id != correct[$0].id }.map { order[$0] }
        let focus = wrong.randomElement(using: &rng) ?? order.randomElement(using: &rng) ?? oldest
        var hints: [String] = [
            "Pretty sure “\(oldest.title)” is the oldest one.",
            "“\(newest.title)” is the newest of those, I think.",
            "“\(focus.title)”? That's \(y(focus)), I'm sure.",
            "Hmm… “\(focus.title)” is from around \(y(focus) - 1) or \(y(focus))?",
            "If I were you, I'd put “\(correct[2].title)” right in the middle.",
        ]
        if let other = order.filter({ $0.id != focus.id }).randomElement(using: &rng) {
            let pair = y(focus) < y(other) ? (focus, other) : (other, focus)
            hints.append("No idea honestly… but my gut says “\(pair.0.title)” is older than “\(pair.1.title)”.")
        }
        for i in 0..<4 where y(correct[i + 1]) - y(correct[i]) <= 1 {
            hints.append("“\(correct[i].title)” and “\(correct[i + 1].title)” came out within a year of each other.")
        }
        if y(correct[1]) - y(oldest) >= 6 {
            hints.append("One of them is way older than the rest, like \(y(correct[1]) - y(oldest)) years.")
        }
        let decades = Dictionary(grouping: order, by: { y($0) / 10 * 10 })
        if let top = decades.max(by: { $0.value.count < $1.value.count }), top.value.count >= 2 {
            hints.append("\(top.value.count) of those are from the \(top.key)s, I think.")
        }
        let text = hints.randomElement(using: &rng) ?? hints[0]
        return FriendCall(name: name, color: color, artist: followed, text: text)
    }
}

private struct FriendBubble: View {
    let call: FriendCall
    let ringing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(call.color).frame(width: 46, height: 46)
                    .overlay(Text(String(call.name.prefix(1))).font(.title3.weight(.heavy)).foregroundStyle(.white))
                if let a = call.artist {
                    a.picture(20).clipShape(Circle()).overlay(Circle().stroke(Color.black, lineWidth: 2)).offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(call.artist.map { "\(call.name), huge \($0.name) fan" } ?? call.name).font(.caption.weight(.bold)).opacity(0.8)
                if ringing {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill").symbolEffect(.bounce, options: .repeating)
                        Text("Calling…")
                    }
                    .font(.subheadline.weight(.semibold))
                } else {
                    Text("“Hello? \(call.text) Good luck!”").font(.subheadline.weight(.semibold))
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - All-dailies streak banner

/// Days in a row you finished every daily, and what's left today to keep it going.
struct DailyStreakBanner: View {
    /// Opens a game when its name is tapped (nil where that isn't possible).
    let open: ((GameKind) -> Void)?
    @Environment(AppModel.self) private var app

    private struct Info {
        var left: [GameKind]
        var done: Int
        var streak: Int
        var ended: Int
    }

    private func info() -> Info {
        let today = AppModel.dayKey()
        let kinds = GameKind.allCases
        let left = kinds.filter { app.prefs.data.games[$0.rawValue]?.lastDaily != today }
        let counters = app.prefs.data.counters
        let cal = Calendar.current
        func key(_ d: Int) -> String { AppModel.dayKey(cal.date(byAdding: .day, value: -d, to: .now) ?? .now) }
        func run(from start: Int) -> Int {
            var n = 0
            var d = start
            while counters["allDone:\(key(d))"] != nil { n += 1; d += 1 }
            return n
        }
        let streak = left.isEmpty ? run(from: 0) : run(from: 1)
        let ended = streak == 0 && counters["allDone:\(key(1))"] == nil ? run(from: 2) : 0
        return Info(left: left, done: kinds.count - left.count, streak: streak, ended: ended)
    }

    private static func names(_ kinds: [GameKind]) -> String {
        let t = kinds.map(\.title)
        guard t.count > 1 else { return t.first ?? "" }
        return t.dropLast().joined(separator: ", ") + " and " + (t.last ?? "")
    }

    private func text(_ i: Info) -> String {
        let n = GameKind.allCases.count
        let keep = i.streak > 0 ? "to keep your \(i.streak)-day streak" : "to start a streak"
        if i.left.isEmpty { return "All done for today · \(i.streak)-day streak. See you tomorrow" }
        if i.done == 0 {
            if i.streak > 0 { return "\(i.streak)-day streak · Play all \(n) dailies today to keep it going" }
            if i.ended > 1 { return "Your \(i.ended)-day streak ended. Play all \(n) today to start a new one" }
            return "Play all \(n) dailies today to start a streak"
        }
        switch i.left.count {
        case 1: return "Just \(i.left[0].title) left \(keep)"
        case 2, 3: return "Finish \(Self.names(i.left)) \(keep)"
        default: return "\(i.left.count) dailies left \(keep)"
        }
    }

    var body: some View {
        let i = info()
        let total = GameKind.allCases.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.2), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(i.done) / CGFloat(total))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "flame.fill").foregroundStyle(i.streak > 0 || i.left.isEmpty ? Color.orange : Color.secondary)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text(i)).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if !i.left.isEmpty && i.streak > 0 && Calendar.current.component(.hour, from: .now) >= 20 {
                        Text("Ends at midnight").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            if let open, (1...3).contains(i.left.count) {
                HStack(spacing: 8) {
                    ForEach(i.left) { k in
                        Button { open(k) } label: {
                            Label(k.title, systemImage: k.icon).font(.caption.weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(k.colors[0].opacity(0.25), in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Lyric Line

/// Songs from your library with lyrics: saved ones first, then a few fetched online.
@MainActor
private enum LyricSource {
    static func songs(_ data: GameData, rng: inout SeededRNG, need: Int) async -> [(Song, Lyrics)] {
        let candidates = data.favorites(&rng, count: 150)
        var out: [(Song, Lyrics)] = []
        var fetched = 0
        for pass in 0..<2 where out.count < need {
            for s in candidates where out.count < need {
                if out.contains(where: { $0.0.id == s.id }) { continue }
                var lyr = LyricsService.cached(s.id)
                if lyr == nil && pass == 1 && fetched < 15 && !AppModel.shared.prefs.data.offline {
                    fetched += 1
                    lyr = await LyricsService.fetch(s)
                }
                guard let l = lyr, !l.instrumental, l.lines.count >= 4 else { continue }
                out.append((s, l))
            }
        }
        return out
    }
}

private struct LyricLineGame: View {
    let data: GameData
    let io: GameIO

    struct Question: Identifiable {
        let id: Int
        let song: Song
        let before: String?
        let line: String
        let choices: [Song]
    }

    @State private var questions: [Question] = []
    @State private var index = 0
    @State private var picked: [Int: Int] = [:]
    @State private var removed: [Int: Set<Int>] = [:]
    @State private var score = 0
    @State private var marks: [Color] = []
    @State private var loading = true
    @State private var over = false
    private let rounds = 5

    var body: some View {
        SwiftUI.Group {
            if loading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView().tint(.white).scaleEffect(1.4)
                    Text("Finding lyrics from your songs…").opacity(0.8)
                    Spacer()
                }
            } else if questions.count == rounds {
                question(questions[min(index, rounds - 1)])
            } else {
                NotEnough(text: "Couldn't find enough lyrics for your songs right now. Connect to the internet and try again.")
            }
        }
        .task { await setup() }
    }

    private func question(_ q: Question) -> some View {
        VStack(spacing: 14) {
            Text("Line \(q.id + 1) of \(rounds) · \(score) right").font(.subheadline.weight(.semibold)).opacity(0.7)
            VStack(alignment: .leading, spacing: 8) {
                if let b = q.before { Text(b).font(.body).opacity(0.45) }
                Text("“\(q.line)”").font(.title3.weight(.bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            Text("Which of your songs is it from?").font(.subheadline.weight(.semibold)).opacity(0.8)
            VStack(spacing: 8) {
                ForEach(q.choices) { c in choice(c, q) }
            }
            LifelineButton(title: "50:50", icon: "circle.lefthalf.filled", used: !removed.isEmpty || over || io.readOnly || picked[q.id] != nil) {
                act("L:\(q.id)")
            }
        }
        .id(q.id)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func choice(_ c: Song, _ q: Question) -> some View {
        let gone = removed[q.id]?.contains(c.id) == true
        let p = picked[q.id]
        let bg: Color = p == nil ? .white.opacity(0.12) : (c.id == q.song.id ? Color(hex: "#22C55E") : (c.id == p ? Color(hex: "#EF4444") : .white.opacity(0.05)))
        return Button { act("A:\(q.id):\(c.id)") } label: {
            HStack(spacing: 12) {
                c.artwork(42).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(c.artistLine).font(.caption).opacity(0.7).lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .background(bg, in: RoundedRectangle(cornerRadius: 12))
            .opacity(gone ? 0.25 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(gone || p != nil || over || io.readOnly)
    }

    @MainActor
    private func setup() async {
        guard questions.isEmpty else { return }
        var rng = SeededRNG(seed: io.seed)
        let found = await LyricSource.songs(data, rng: &rng, need: rounds)
        var out: [Question] = []
        for (s, l) in found {
            let lines = l.lines.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let good = lines.indices.filter { lines[$0].split(separator: " ").count >= 4 && lines[$0].count <= 80 }
            guard let li = good.randomElement(using: &rng) else { continue }
            var others: [Song] = []
            for o in data.songs.shuffled(using: &rng) where others.count < 3 {
                if o.id != s.id && o.title != s.title && !others.contains(where: { $0.id == o.id }) { others.append(o) }
            }
            guard others.count == 3 else { continue }
            out.append(Question(id: out.count, song: s, before: li > 0 ? lines[li - 1] : nil, line: lines[li],
                                choices: ([s] + others).shuffled(using: &rng)))
        }
        questions = Array(out.prefix(rounds))
        loading = false
        for m in io.moves { apply(m, live: false) }
    }

    private func act(_ m: String) {
        io.record(m)
        apply(m, live: true)
    }

    private func apply(_ m: String, live: Bool) {
        guard !over, questions.count == rounds else { return }
        let parts: [String] = m.split(separator: Character(":")).map { String($0) }
        guard parts.count >= 2, let qid = Int(parts[1]), questions.indices.contains(qid) else { return }
        let q = questions[qid]
        if parts[0] == "L" {
            guard removed.isEmpty else { return }
            var rng = SeededRNG(seed: io.seed &+ UInt64(qid) &+ 17)
            let wrong = q.choices.filter { $0.id != q.song.id }.shuffled(using: &rng).prefix(2).map(\.id)
            withAnimation(live ? .easeInOut(duration: 0.5) : nil) { removed[qid] = Set(wrong) }
            return
        }
        guard parts[0] == "A", parts.count == 3, let id = Int(parts[2]), picked[qid] == nil else { return }
        let right = id == q.song.id
        withAnimation(live ? .spring(response: 0.3) : nil) { picked[qid] = id }
        if right { score += 1 }
        marks.append(right ? Color(hex: "#22C55E") : Color(white: 0.3))
        if live { AppModel.shared.haptic(right ? .success : .warning) }
        let last = qid >= rounds - 1
        if last { over = true }
        guard live else {
            if !last { index = qid + 1 }
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if last {
                let perfect = score == rounds && removed.isEmpty
                io.done(GameResult(won: score >= 3, headline: "\(score) of \(rounds)",
                                   detail: perfect ? "You know every word." : (score >= 3 ? "You know your lyrics." : "Time to read along more."),
                                   marks: marks, usedLifeline: !removed.isEmpty, counts: perfect ? ["lineReaderPerfect"] : []))
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index = qid + 1 }
            }
        }
    }
}

// MARK: - Song Blitz

private struct BlitzGame: View {
    let data: GameData
    let io: GameIO

    struct Round {
        let song: Song
        let file: URL
        let start: Double
        let choices: [Song]
    }

    @State private var rounds: [Round] = []
    @State private var index = 0
    @State private var right = 0
    @State private var started: Date?
    @State private var over = false
    @State private var player: AVAudioPlayer?
    @State private var flash: Bool?
    @State private var rng = SeededRNG(seed: 1)
    private let length: Double = 60
    private let target = 10
    private var best: Int { AppModel.shared.prefs.data.counters["blitzBest"] ?? 0 }

    var body: some View {
        SwiftUI.Group {
            if rounds.count < 4 {
                NotEnough(text: "Song Blitz needs at least 4 downloaded songs.")
            } else if over {
                VStack(spacing: 12) {
                    Spacer()
                    Text("\(right)").font(.system(size: 80, weight: .black, design: .rounded))
                    Text(io.daily ? "right · the goal was \(target)" : "right in one minute").font(.title3.weight(.semibold)).opacity(0.8)
                    if !io.daily { Text("Best: \(max(best, right))").font(.headline).foregroundStyle(.orange) }
                    Spacer()
                }
            } else if let started {
                playing(started)
            } else {
                startScreen
            }
        }
        .onAppear(perform: setup)
        .onDisappear { player?.stop() }
    }

    private var startScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bolt.fill").font(.system(size: 64)).foregroundStyle(GameKind.blitz.colors[0])
            Text("One minute. Go!").font(.title.weight(.black))
            Text(io.daily ? "Get \(target) songs right within 60 seconds to win today's blitz. Leaving ends your daily."
                          : "As many songs right as you can in 60 seconds. Wrong answers just move on.")
                .multilineTextAlignment(.center).opacity(0.8)
            if !io.daily { Text("Best: \(best)").font(.headline).foregroundStyle(.orange) }
            GameButton(title: "Start", color: GameKind.blitz.colors[0], disabled: io.readOnly, action: start)
            Spacer()
        }
    }

    private func playing(_ started: Date) -> some View {
        let r = rounds[index % rounds.count]
        return VStack(spacing: 16) {
            TimelineView(.periodic(from: started, by: 0.1)) { ctx in
                let left = max(0, length - ctx.date.timeIntervalSince(started))
                HStack {
                    Text(String(format: "%.1f", left)).font(.system(size: 44, weight: .black, design: .rounded)).monospacedDigit()
                        .foregroundStyle(left < 10 ? Color.red : Color.white)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(right)\(io.daily ? " / \(target)" : "")").font(.title.weight(.heavy)).monospacedDigit()
                        Text("right").font(.caption).opacity(0.7)
                    }
                }
            }
            Image(systemName: "waveform").font(.system(size: 50)).symbolEffect(.variableColor.iterative, isActive: true)
                .foregroundStyle(flash == nil ? Color.white : (flash == true ? Color.green : Color.red))
                .frame(height: 70)
            VStack(spacing: 8) {
                ForEach(r.choices) { c in
                    Button { answer(c, r) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.headline).lineLimit(1)
                                Text(c.artistLine).font(.caption).opacity(0.7).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .id(index)
            .transition(.opacity)
        }
    }

    private func setup() {
        var r = SeededRNG(seed: io.seed)
        let lib = AppModel.shared.library
        var out: [Round] = []
        for s in data.favorites(&r, count: 200) where out.count < 80 {
            guard let e = lib.entry(s.id), FileManager.default.fileExists(atPath: e.fileURL.path) else { continue }
            var others: [Song] = []
            for o in data.songs.shuffled(using: &r) where others.count < 3 {
                if o.id != s.id && o.title != s.title && !others.contains(where: { $0.id == o.id }) { others.append(o) }
            }
            guard others.count == 3 else { continue }
            out.append(Round(song: s, file: e.fileURL, start: e.highlightStart ?? 30, choices: ([s] + others).shuffled(using: &r)))
        }
        rounds = out
        rng = r
        // A daily blitz that was started and left counts as finished with the score it had.
        if io.moves.contains("S") {
            right = io.moves.filter { $0 == "R" }.count
            over = true
            if !io.readOnly { finish(live: true, reason: "You left mid-blitz.") }
        }
    }

    private func start() {
        io.record("S")
        started = .now
        playCurrent()
        Task {
            while !over {
                try? await Task.sleep(for: .milliseconds(100))
                if let s = started, Date.now.timeIntervalSince(s) >= length, !over { finish(live: true, reason: nil) }
            }
        }
    }

    private func playCurrent() {
        player?.stop()
        let r = rounds[index % rounds.count]
        let p = try? AVAudioPlayer(contentsOf: r.file)
        try? AVAudioSession.sharedInstance().setActive(true)
        p?.currentTime = min(r.start, max(0, (p?.duration ?? 60) - 20))
        p?.play()
        player = p
    }

    private func answer(_ c: Song, _ r: Round) {
        guard !over else { return }
        let ok = c.id == r.song.id
        io.record(ok ? "R" : "W")
        if ok { right += 1 }
        AppModel.shared.haptic(ok ? .success : .warning)
        withAnimation(.easeOut(duration: 0.15)) { flash = ok }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation { flash = nil }
        }
        if io.daily && right >= target {
            finish(live: true, reason: nil)
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
        playCurrent()
    }

    private func finish(live: Bool, reason: String?) {
        guard live else { return }
        let elapsed = started.map { min(length, Date.now.timeIntervalSince($0)) } ?? length
        over = true
        player?.stop()
        let won = io.daily ? right >= target : right >= target
        let headline: String
        if io.daily { headline = right >= target ? "\(target) in \(Int(elapsed.rounded()))s!" : "\(right) of \(target)" }
        else { headline = right > best ? "New highscore: \(right)!" : "\(right) right" }
        let detail = reason ?? (io.daily ? (won ? "Lightning fast." : "So close. Try a practice blitz.") : "Your best is \(max(best, right)).")
        io.done(GameResult(won: won, headline: headline, detail: detail,
                           marks: Array(repeating: Color(hex: "#22C55E"), count: min(right, 20)), bests: ["blitzBest": right]))
    }
}
