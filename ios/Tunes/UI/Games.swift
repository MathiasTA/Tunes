import AVFoundation
import SwiftUI

// MARK: - Games

enum GameKind: String, CaseIterable, Identifiable {
    case tunedle, connections, earworm, higherLower, coverStory, finishLyric, timeline
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tunedle: "Tunedle"
        case .connections: "Connections"
        case .earworm: "Earworm"
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

    init(_ app: AppModel) {
        songs = app.library.entries.map(\.song)
        var p: [Int: Int] = [:]
        for r in app.stats.records where r.seconds >= StatsStore.playThreshold { p[r.songID, default: 0] += 1 }
        plays = p
        top = app.stats.ranking(p)
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

/// The frame around every game: daily or practice, the round itself, and the results.
struct GameScreen: View {
    let kind: GameKind
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var daily = true
    @State private var seed: UInt64 = 0
    @State private var round = 0
    @State private var result: GameResult?
    @State private var data: GameData?

    private var today: String { AppModel.dayKey() }
    private var record: GameRecord { app.prefs.data.games[kind.rawValue] ?? GameRecord() }
    private var dailySeed: UInt64 {
        let days = UInt64(max(0, Date.now.timeIntervalSince1970 / 86_400))
        return days &* 7919 &+ kind.index &* 104_729
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [kind.colors[1].mixed(with: .black, by: 0.55), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                header
                if let data {
                    if daily && record.lastDaily == today && result == nil {
                        alreadyPlayed
                    } else {
                        game(data)
                            .id("\(seed)-\(round)")
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            if let result { ResultOverlay(kind: kind, result: result, daily: daily, streak: record.streak, again: playAnother, close: { dismiss() }) }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: result != nil)
        .onAppear {
            data = GameData(app)
            seed = dailySeed
            app.player.pause()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(.white.opacity(0.12), in: Circle()) }
                .accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.title3.weight(.heavy))
                Text(daily ? "Today's puzzle" : "Practice round").font(.caption.weight(.semibold)).opacity(0.7)
            }
            Spacer()
            if record.streak > 0 {
                Label("\(record.streak)", systemImage: "flame.fill").font(.subheadline.weight(.heavy)).foregroundStyle(.orange)
            }
            Button(daily ? "Practice" : "Daily") {
                withAnimation {
                    daily.toggle()
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

    private var alreadyPlayed: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: record.dailyWon ? "checkmark.seal.fill" : "moon.zzz.fill").font(.system(size: 60)).foregroundStyle(kind.colors[0])
            Text(record.dailyWon ? "You solved today's puzzle" : "You played today's puzzle").font(.title2.weight(.heavy))
            Text("A new one arrives tomorrow. Want another round now?").opacity(0.75).multilineTextAlignment(.center)
            Button { playAnother() } label: {
                Text("Play another").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                    .background(kind.colors[0], in: Capsule())
            }
            .buttonStyle(PressStyle())
            .padding(.top, 8)
            Spacer()
        }
    }

    @ViewBuilder
    private func game(_ d: GameData) -> some View {
        let done: (GameResult) -> Void = finish
        switch kind {
        case .tunedle: TunedleGame(data: d, seed: seed, done: done)
        case .connections: ConnectionsGame(data: d, seed: seed, done: done)
        case .earworm: EarwormGame(data: d, seed: seed, done: done)
        case .higherLower: HigherLowerGame(data: d, seed: seed, done: done)
        case .coverStory: CoverStoryGame(data: d, seed: seed, done: done)
        case .finishLyric: LyricGame(data: d, seed: seed, done: done)
        case .timeline: TimelineGame(data: d, seed: seed, done: done)
        }
    }

    private func finish(_ r: GameResult) {
        app.haptic(r.won ? .success : .warning)
        if daily && record.lastDaily != today {
            var rec = record
            let yesterday = AppModel.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
            rec.finishDaily(won: r.won, today: today, yesterday: yesterday)
            app.prefs.data.games[kind.rawValue] = rec
            app.checkBadges(force: true)
        }
        app.bump("gamesPlayed")
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.6)) { result = r }
    }

    private func playAnother() {
        withAnimation {
            daily = false
            result = nil
            seed = UInt64.random(in: 1...UInt64.max)
            round += 1
        }
    }
}

struct GameResult {
    var won: Bool
    var headline: String
    var detail: String
    /// A little row of squares for the share card (like 🟩🟨⬛️), drawn as colors.
    var marks: [Color] = []
    var song: Song?
}

private struct ResultOverlay: View {
    let kind: GameKind
    let result: GameResult
    let daily: Bool
    let streak: Int
    let again: () -> Void
    let close: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: result.won ? "star.circle.fill" : "music.note")
                    .font(.system(size: 64)).foregroundStyle(kind.colors[0])
                    .scaleEffect(shown ? 1 : 0.3).rotationEffect(.degrees(shown ? 0 : -40))
                Text(result.headline).font(.title.weight(.black)).multilineTextAlignment(.center)
                Text(result.detail).multilineTextAlignment(.center).opacity(0.85)
                if let s = result.song {
                    HStack(spacing: 12) {
                        s.artwork(52).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading) {
                            Text(s.title).font(.headline).lineLimit(1)
                            Text(s.artistLine).font(.caption).opacity(0.75).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(12).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                if !result.marks.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(result.marks.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(result.marks[i]).frame(width: 18, height: 18)
                        }
                    }
                }
                if daily && streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill").font(.headline).foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    if let img = shareImage() {
                        ShareLink(item: img, preview: SharePreview("\(kind.title) on Tunes", image: img)) {
                            Label("Share", systemImage: "square.and.arrow.up").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                                .background(.white.opacity(0.14), in: Capsule())
                        }
                    }
                    Button(action: again) {
                        Text("Play another").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                            .background(kind.colors[0], in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
                Button("Done", action: close).font(.subheadline.weight(.semibold)).opacity(0.8)
            }
            .padding(24)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(20)
            .scaleEffect(shown ? 1 : 0.9).opacity(shown ? 1 : 0)
        }
        .foregroundStyle(.white)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { shown = true } }
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

// MARK: - Tunedle

private struct TunedleGame: View {
    let data: GameData
    let seed: UInt64
    let done: (GameResult) -> Void

    @State private var target: (song: Song, word: String)?
    @State private var guesses: [String] = []
    @State private var current = ""
    @State private var shake = 0
    @State private var over = false
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
        guard (4...11).contains(count), cleaned.split(separator: " ").count <= 3 else { return nil }
        return cleaned
    }

    var body: some View {
        Group {
            if let target {
                VStack(spacing: 12) {
                    hints(target)
                    board(target.word)
                        .modifier(Shake(amount: CGFloat(shake)))
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
        var rng = SeededRNG(seed: seed)
        for s in data.favorites(&rng, count: 120) {
            if let w = Self.normalize(s.title) { target = (s, w); return }
        }
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
            Text("A song from your library · \(letters(t.word).count) letters").font(.subheadline.weight(.semibold)).opacity(0.8)
            if wrong >= 2 {
                Text("Hint: the artist starts with “\(t.song.artist.name.prefix(1))”").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                    .transition(.opacity)
            }
            if wrong >= 4 {
                Text(GameData.year(t.song).map { "Hint: released in \($0)" } ?? "Hint: from \(t.song.album?.title ?? "an album")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.yellow).transition(.opacity)
            }
        }
        .animation(.easeInOut, value: wrong)
    }

    private func board(_ word: String) -> some View {
        let parts: [Substring] = word.split(separator: Character(" "))
        let words: [Int] = parts.map { $0.count }
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
        .disabled(over)
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
    }

    private func submit(_ word: String) {
        guard let t = target else { return }
        guard current.count == letters(word).count else {
            withAnimation(.default) { shake += 1 }
            AppModel.shared.haptic(.warning)
            return
        }
        let g = current
        withAnimation { guesses.append(g); current = "" }
        let won = g == String(letters(word))
        if won || guesses.count >= rows {
            over = true
            let squares = guesses.map { gg -> Color in
                let ms = marks(gg, word)
                return ms.allSatisfy { $0 == .hit } ? Color(hex: "#22C55E") : (ms.contains { $0 != .miss } ? Color(hex: "#EAB308") : Color(white: 0.3))
            }
            done(GameResult(won: won, headline: won ? "Got it in \(guesses.count)!" : "So close",
                            detail: won ? "You know your library." : "It was \(t.song.title).", marks: squares, song: t.song))
        }
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

// MARK: - Connections

private struct ConnectionsGame: View {
    let data: GameData
    let seed: UInt64
    let done: (GameResult) -> Void

    struct Group: Identifiable {
        let id = UUID()
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
                    HStack(spacing: 10) {
                        Button("Shuffle") { withAnimation(.spring) { tiles.shuffle() } }
                            .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).frame(height: 46).background(.white.opacity(0.12), in: Capsule())
                        Button("Deselect") { withAnimation { picked = [] } }
                            .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).frame(height: 46).background(.white.opacity(0.12), in: Capsule())
                        GameButton(title: "Submit", disabled: picked.count != 4, action: submit)
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
    }

    private func setup() {
        var rng = SeededRNG(seed: seed)
        typealias Rule = (name: String, test: (Song) -> Bool)
        var rules: [Rule] = []
        let songs = data.songs
        let byArtist = Dictionary(grouping: songs) { $0.artist.id }
        for (_, list) in byArtist where list.count >= 4 {
            let a = list[0].artist
            rules.append(("Songs by \(a.name)", { $0.artist.id == a.id }))
        }
        let byAlbum = Dictionary(grouping: songs.filter { ($0.album?.id ?? 0) > 0 }) { $0.album?.id ?? 0 }
        for (_, list) in byAlbum where list.count >= 4 {
            if let al = list[0].album { rules.append(("From \(al.title)", { $0.album?.id == al.id })) }
        }
        let byYear = Dictionary(grouping: songs.filter { GameData.year($0) != nil }) { GameData.year($0) ?? 0 }
        for (y, list) in byYear where list.count >= 4 { rules.append(("Released in \(y)", { GameData.year($0) == y })) }
        let top10 = Set(data.top.prefix(10))
        if songs.filter({ top10.contains($0.id) }).count >= 4 { rules.append(("In your top 10", { top10.contains($0.id) })) }
        rules.shuffle(using: &rng)

        var chosen: [(Rule, [Song])] = []
        var used = Set<Int>()
        for rule in rules where chosen.count < 4 {
            // Songs that fit this rule and none of the rules already chosen (so there's only one answer).
            let fits = songs.filter { s in rule.test(s) && !used.contains(s.id) && !chosen.contains { $0.0.test(s) } }
            guard fits.count >= 4 else { continue }
            let four = Array(fits.shuffled(using: &rng).prefix(4))
            // The new rule must not also match songs already picked for earlier groups.
            guard !chosen.contains(where: { $0.1.contains(where: rule.test) }) else { continue }
            chosen.append((rule, four))
            used.formUnion(four.map(\.id))
        }
        guard chosen.count == 4 else { return }
        groups = chosen.enumerated().map { i, c in Group(name: c.0.name, songs: c.1, color: Self.palette[i]) }
        tiles = chosen.flatMap(\.1).shuffled(using: &rng)
    }

    private func submit() {
        guard picked.count == 4 else { return }
        let remaining = groups.filter { g in !solved.contains { $0.id == g.id } }
        if let g = remaining.first(where: { Set($0.songs.map(\.id)) == picked }) {
            AppModel.shared.haptic(.success)
            history.append(g.color)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                solved.append(g)
                tiles.removeAll { picked.contains($0.id) }
                picked = []
                toast = nil
            }
            if solved.count == 4 {
                done(GameResult(won: true, headline: mistakes == 0 ? "Perfect!" : "All four groups!",
                                detail: mistakes == 0 ? "Not a single mistake." : "With \(mistakes) mistake\(mistakes == 1 ? "" : "s").", marks: history))
            }
        } else {
            let close = remaining.contains { Set($0.songs.map(\.id)).intersection(picked).count == 3 }
            AppModel.shared.haptic(.warning)
            history.append(Color(white: 0.3))
            withAnimation(.default) { shake += 1; mistakes += 1; toast = close ? "One away…" : nil }
            if mistakes >= 4 {
                withAnimation(.spring) {
                    solved = groups
                    tiles = []
                }
                done(GameResult(won: false, headline: "Out of mistakes", detail: "Here's how the groups went together.", marks: history))
            }
        }
    }
}

// MARK: - Earworm

private struct EarwormGame: View {
    let data: GameData
    let seed: UInt64
    let done: (GameResult) -> Void

    @State private var target: Song?
    @State private var start: Double = 30
    @State private var step = 0
    @State private var wrong: [Song] = []
    @State private var query = ""
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var over = false
    private let clips: [Double] = [1, 2, 4, 7, 11, 16]

    var body: some View {
        SwiftUI.Group {
            if target != nil {
                VStack(spacing: 14) {
                    clipBar
                    Button(action: play) {
                        Image(systemName: playing ? "waveform" : "play.fill")
                            .font(.system(size: 34, weight: .bold))
                            .symbolEffect(.variableColor.iterative, isActive: playing)
                            .frame(width: 90, height: 90)
                            .background(GameKind.earworm.colors[0], in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Play the clip")
                    Text("Clip: \(Int(clips[step])) second\(clips[step] == 1 ? "" : "s")").font(.subheadline.weight(.semibold)).opacity(0.8)
                    ForEach(wrong) { s in
                        Label(s.title, systemImage: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.red.opacity(0.9))
                    }
                    TextField("Search your songs", text: $query)
                        .padding(12).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .autocorrectionDisabled()
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(matches) { s in
                                Button { guess(s) } label: {
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
                    .frame(maxHeight: 200)
                    Button(step < clips.count - 1 ? "Skip (+\(Int(clips[step + 1] - clips[step]))s)" : "Give up") { advance() }
                        .font(.subheadline.weight(.bold)).opacity(0.8)
                }
                .disabled(over)
            } else {
                NotEnough(text: "Earworm needs downloaded songs to play clips from.")
            }
        }
        .onAppear(perform: setup)
        .onDisappear { player?.stop() }
    }

    private var matches: [Song] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return data.songs.filter { $0.matches(q) && !wrong.contains($0) }.prefix(20).map { $0 }
    }

    private var clipBar: some View {
        GeometryReader { g in
            let w: CGFloat = g.size.width
            let reach: CGFloat = w * CGFloat(clips[step]) / 16
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
        var rng = SeededRNG(seed: seed)
        let lib = AppModel.shared.library
        guard let s = data.favorites(&rng).first(where: { lib.entry($0.id).map { FileManager.default.fileExists(atPath: $0.fileURL.path) } ?? false }),
              let e = lib.entry(s.id) else { return }
        target = s
        start = max(0, (e.highlightStart ?? 30))
        player = try? AVAudioPlayer(contentsOf: e.fileURL)
        player?.prepareToPlay()
    }

    private func play() {
        guard let p = player, !playing else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        p.currentTime = min(start, max(0, p.duration - 17))
        p.volume = 1
        p.play()
        playing = true
        progress = 0
        let length = clips[step]
        withAnimation(.linear(duration: length)) { progress = 1 }
        Task {
            try? await Task.sleep(for: .seconds(length))
            p.pause()
            playing = false
        }
    }

    private func guess(_ s: Song) {
        guard let t = target else { return }
        query = ""
        if s.id == t.id {
            finish(won: true)
        } else {
            withAnimation { wrong.append(s) }
            AppModel.shared.haptic(.warning)
            advance()
        }
    }

    private func advance() {
        if step < clips.count - 1 {
            withAnimation { step += 1 }
        } else {
            finish(won: false)
        }
    }

    private func finish(won: Bool) {
        guard let t = target, !over else { return }
        over = true
        player?.stop()
        let marks = (0..<clips.count).map { i -> Color in
            i < step ? Color(white: 0.3) : (i == step ? (won ? Color(hex: "#22C55E") : Color(white: 0.3)) : Color.white.opacity(0.12))
        }
        done(GameResult(won: won, headline: won ? "Got it in \(Int(clips[step]))s!" : "It was…",
                        detail: won ? "Your ears know your music." : "Better luck tomorrow.", marks: marks, song: t))
    }
}

// MARK: - Higher or lower

private struct HigherLowerGame: View {
    let data: GameData
    let seed: UInt64
    let done: (GameResult) -> Void

    @State private var deck: [Song] = []
    @State private var i = 0
    @State private var score = 0
    @State private var revealed = false
    @State private var lastRight: Bool?
    private let goal = 10

    var body: some View {
        SwiftUI.Group {
            if deck.count > i + 1 {
                let a = deck[i], b = deck[i + 1]
                VStack(spacing: 14) {
                    Text("Score \(score) / \(goal)").font(.headline.monospacedDigit())
                    card(a, count: data.plays[a.id] ?? 0, show: true)
                    Text("Did you play this one more or less?").font(.subheadline.weight(.semibold)).opacity(0.8)
                    card(b, count: data.plays[b.id] ?? 0, show: revealed)
                    HStack(spacing: 10) {
                        GameButton(title: "Less", color: GameKind.higherLower.colors[1], disabled: revealed) { answer(higher: false) }
                        GameButton(title: "More", color: GameKind.higherLower.colors[0], disabled: revealed) { answer(higher: true) }
                    }
                }
            } else if deck.isEmpty {
                NotEnough(text: "Play a few more songs first, so there's something to compare.")
            }
        }
        .onAppear(perform: setup)
    }

    private func card(_ s: Song, count: Int, show: Bool) -> some View {
        HStack(spacing: 14) {
            s.artwork(70).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.headline).lineLimit(2)
                Text(s.artistLine).font(.caption).opacity(0.7).lineLimit(1)
            }
            Spacer()
            Text(show ? "\(count)" : "?").font(.system(size: 30, weight: .black, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(show && lastRight != nil && revealed && s.id == deck[safe: i + 1]?.id ? (lastRight == true ? Color.green : Color.red) : Color.white)
        }
        .padding(14)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }

    private func setup() {
        var rng = SeededRNG(seed: seed)
        let played = data.songs.filter { (data.plays[$0.id] ?? 0) > 0 }.shuffled(using: &rng)
        guard played.count >= 6 else { return }
        // No equal neighbors, so every question has an answer.
        var out: [Song] = []
        for s in played where out.count < goal + 1 {
            if let last = out.last, data.plays[last.id] == data.plays[s.id] { continue }
            out.append(s)
        }
        deck = out
    }

    private func answer(higher: Bool) {
        let a = data.plays[deck[i].id] ?? 0, b = data.plays[deck[i + 1].id] ?? 0
        let right = higher ? b > a : b < a
        lastRight = right
        withAnimation(.spring) { revealed = true }
        AppModel.shared.haptic(right ? .success : .warning)
        if right { score += 1 }
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if !right || i + 2 >= deck.count {
                let won = score >= min(goal, deck.count - 1) / 2
                done(GameResult(won: won, headline: "\(score) in a row", detail: right ? "You went the distance." : "You know your plays better than most.",
                                marks: (0..<score).map { _ in Color(hex: "#22C55E") } + (right ? [] : [Color(white: 0.3)])))
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    i += 1
                    revealed = false
                    lastRight = nil
                }
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Cover Story

private struct CoverStoryGame: View {
    let data: GameData
    let seed: UInt64
    let done: (GameResult) -> Void

    @State private var target: Song?
    @State private var choices: [Song] = []
    @State private var image: UIImage?
    @State private var step = 0
    @State private var out: Set<Int> = []
    @State private var anchor = UnitPoint.center
    @State private var over = false
    private let zooms: [CGFloat] = [6, 4, 2.6, 1.7, 1]
    private let blurs: [CGFloat] = [24, 14, 8, 3, 0]

    var body: some View {
        SwiftUI.Group {
            if let target {
                VStack(spacing: 16) {
                    ZStack {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                                .scaleEffect(zooms[step], anchor: anchor)
                                .blur(radius: blurs[step])
                        } else {
                            target.artwork(280).scaleEffect(zooms[step], anchor: anchor).blur(radius: blurs[step])
                        }
                    }
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .animation(.easeInOut(duration: 0.6), value: step)
                    HStack(spacing: 6) {
                        ForEach(0..<zooms.count, id: \.self) { i in Capsule().fill(i <= step ? GameKind.coverStory.colors[0] : Color.white.opacity(0.2)).frame(height: 5) }
                    }
                    .frame(width: 200)
                    VStack(spacing: 8) {
                        ForEach(choices) { s in
                            Button { pick(s) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title).font(.subheadline.weight(.bold)).lineLimit(1)
                                        Text(s.artistLine).font(.caption).opacity(0.7).lineLimit(1)
                                    }
                                    Spacer()
                                    if out.contains(s.id) { Image(systemName: "xmark").foregroundStyle(.red) }
                                }
                                .padding(12)
                                .background(.white.opacity(out.contains(s.id) ? 0.04 : 0.12), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(PressStyle())
                            .disabled(out.contains(s.id) || over)
                        }
                    }
                }
            } else {
                NotEnough(text: "Cover Story needs songs with album covers.")
            }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        var rng = SeededRNG(seed: seed)
        let pool = data.favorites(&rng).filter { $0.artworkURL != nil || FileManager.default.fileExists(atPath: $0.localArtworkURL.path) }
        guard let t = pool.first else { return }
        // Choices from different albums, so two answers never share a cover.
        var picks = [t]
        for s in data.songs.shuffled(using: &rng) where picks.count < 4 {
            if !picks.contains(where: { $0.id == s.id || ($0.album?.id != nil && $0.album?.id == s.album?.id) }) { picks.append(s) }
        }
        target = t
        choices = picks.shuffled(using: &rng)
        anchor = UnitPoint(x: Double.random(in: 0.25...0.75, using: &rng), y: Double.random(in: 0.25...0.75, using: &rng))
        Task { image = await ImageCache.shared.image(local: t.localArtworkURL, remote: t.artworkURL, maxPixel: 600) }
    }

    private func pick(_ s: Song) {
        guard let t = target else { return }
        if s.id == t.id {
            over = true
            withAnimation { step = zooms.count - 1 }
            let marks = (0..<zooms.count).map { $0 < out.count ? Color(white: 0.3) : ($0 == out.count ? Color(hex: "#22C55E") : Color.white.opacity(0.12)) }
            done(GameResult(won: true, headline: out.isEmpty ? "First try!" : "Got it!", detail: "You'd know that cover anywhere.", marks: marks, song: t))
        } else {
            AppModel.shared.haptic(.warning)
            withAnimation { out.insert(s.id); step = min(zooms.count - 1, step + 1) }
            if out.count >= 3 || step >= zooms.count - 1 && out.count >= 2 {
                over = true
                done(GameResult(won: false, headline: "It was this one", detail: "Covers can be tricky up close.", marks: [], song: t))
            }
        }
    }
}

// MARK: - Finish the lyric

private struct LyricGame: View {
    let data: GameData
    let seed: UInt64
    let done: (GameResult) -> Void

    struct Question: Identifiable {
        let id = UUID()
        let song: Song
        let before: String?
        let line: String
        let answer: String
        let choices: [String]
    }

    @State private var questions: [Question] = []
    @State private var index = 0
    @State private var picked: String?
    @State private var score = 0
    @State private var marks: [Color] = []
    @State private var loaded = false

    var body: some View {
        SwiftUI.Group {
            if questions.count == 3, index < questions.count {
                let q = questions[index]
                VStack(spacing: 16) {
                    Text("Line \(index + 1) of 3").font(.subheadline.weight(.semibold)).opacity(0.7)
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
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(q.choices, id: \.self) { c in
                            Button { choose(c, q) } label: {
                                Text(c).font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                                    .background(background(c, q), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(PressStyle())
                            .disabled(picked != nil)
                        }
                    }
                }
                .id(q.id)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if loaded && questions.count < 3 {
                NotEnough(text: "Open the lyrics on a few of your songs first. Tunes saves them, and then this game can use them.")
            }
        }
        .onAppear(perform: setup)
    }

    private func display(_ q: Question) -> AttributedString {
        let blank = picked ?? "_____"
        return AttributedString(q.line.replacingOccurrences(of: q.answer, with: blank, options: [], range: q.line.range(of: q.answer)))
    }

    private func background(_ c: String, _ q: Question) -> Color {
        guard let p = picked else { return .white.opacity(0.12) }
        if c == q.answer { return Color(hex: "#22C55E") }
        if c == p { return Color(hex: "#EF4444") }
        return .white.opacity(0.06)
    }

    private func setup() {
        var rng = SeededRNG(seed: seed)
        var out: [Question] = []
        var checked = 0
        for s in data.favorites(&rng, count: 200) where out.count < 3 && checked < 250 {
            checked += 1
            guard let lyr = LyricsService.cached(s.id), !lyr.instrumental, lyr.lines.count > 6 else { continue }
            let lines = lyr.lines.map(\.text)
            let good = lines.indices.filter { i in
                let w = lines[i].split(separator: " ")
                return w.count >= 5 && lines[i].count < 70 && w.contains { Self.clean($0).count >= 4 }
            }
            guard let li = good.randomElement(using: &rng) else { continue }
            let line = lines[li]
            let candidates = line.split(separator: " ").map(Self.clean).filter { $0.count >= 4 }
            guard let answer = candidates.randomElement(using: &rng) else { continue }
            var pool = Set(lines.flatMap { $0.split(separator: " ").map(Self.clean) }.filter { $0.count >= 4 && $0.lowercased() != answer.lowercased() })
            pool.subtract(candidates)
            let wrong = Array(pool).shuffled(using: &rng).prefix(3)
            guard wrong.count == 3 else { continue }
            out.append(Question(song: s, before: li > 0 ? lines[li - 1] : nil, line: line, answer: answer,
                                choices: ([answer] + wrong).shuffled(using: &rng)))
        }
        questions = out
        loaded = true
    }

    private static func clean(_ w: Substring) -> String {
        String(w.unicodeScalars.filter { CharacterSet.letters.contains($0) || $0 == "'" }.map(Character.init))
    }

    private func choose(_ c: String, _ q: Question) {
        let right = c == q.answer
        withAnimation(.spring(response: 0.3)) { picked = c }
        AppModel.shared.haptic(right ? .success : .warning)
        if right { score += 1 }
        marks.append(right ? Color(hex: "#22C55E") : Color(white: 0.3))
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if index + 1 >= questions.count {
                done(GameResult(won: score >= 2, headline: "\(score) of 3", detail: score == 3 ? "Word perfect." : (score == 2 ? "You know the words." : "Time to sing along more."), marks: marks))
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index += 1; picked = nil }
            }
        }
    }
}

// MARK: - Timeline

private struct TimelineGame: View {
    let data: GameData
    let seed: UInt64
    let done: (GameResult) -> Void

    @State private var order: [Song] = []
    @State private var tries = 0
    @State private var checked = false

    private var correct: [Song] { order.sorted { (GameData.year($0) ?? 0) < (GameData.year($1) ?? 0) } }

    var body: some View {
        SwiftUI.Group {
            if order.count == 5 {
                VStack(spacing: 12) {
                    Text("Oldest at the top. Drag to reorder.").font(.subheadline.weight(.semibold)).opacity(0.8)
                    List {
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
                                        .foregroundStyle(correct[i].id == s.id ? Color.green : Color.red)
                                }
                            }
                            .listRowBackground(rowColor(i, s))
                            .foregroundStyle(.white)
                        }
                        .onMove { from, to in
                            order.move(fromOffsets: from, toOffset: to)
                            checked = false
                            AppModel.shared.haptic(.selection)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
                    .frame(height: 5 * 64)
                    GameButton(title: tries == 0 ? "Check" : "Check again", color: GameKind.timeline.colors[0], action: check)
                    if tries == 1 && checked { Text("Green ones are right. One more try.").font(.caption).opacity(0.8) }
                }
            } else {
                NotEnough(text: "Timeline needs songs from at least 5 different years.")
            }
        }
        .onAppear(perform: setup)
    }

    private func rowColor(_ i: Int, _ s: Song) -> Color {
        guard checked else { return Color.white.opacity(0.08) }
        return correct[i].id == s.id ? Color.green.opacity(0.25) : Color.red.opacity(0.2)
    }

    private func setup() {
        var rng = SeededRNG(seed: seed)
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
    }

    private func check() {
        tries += 1
        withAnimation { checked = true }
        let right = zip(order, correct).filter { $0.0.id == $0.1.id }.count
        if right == 5 {
            done(GameResult(won: true, headline: tries == 1 ? "Perfect order!" : "Sorted!", detail: "You know your music history.",
                            marks: Array(repeating: Color(hex: "#22C55E"), count: 5)))
        } else if tries >= 2 {
            AppModel.shared.haptic(.warning)
            done(GameResult(won: false, headline: "\(right) of 5 in place", detail: "The years are shown next to each song.",
                            marks: zip(order, correct).map { $0.0.id == $0.1.id ? Color(hex: "#22C55E") : Color(white: 0.3) }))
        } else {
            AppModel.shared.haptic(.warning)
        }
    }
}
