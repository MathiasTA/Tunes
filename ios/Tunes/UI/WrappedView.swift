import SwiftUI

// MARK: - Data

struct WrappedData {
    struct Personality { let title: String; let blurb: String; let icon: String }

    let range: StatsRange
    let total: Double
    let plays: Int
    let artistCount: Int
    let songCount: Int
    let daysListened: Int
    let topArtists: [StatsStore.ArtistStat]
    let topSongs: [StatsStore.SongStat]
    let genres: [(name: String, share: Double)]
    let biggest: (day: Date, seconds: Double, topSong: PlayRecord?)?
    let hourly: [Double]
    let peakHour: Int
    let streak: (days: Int, start: Date?)
    let discoveries: [StatsStore.ArtistStat]
    let averageYear: Int?
    let oldest: PlayRecord?
    let personality: Personality
    let records: [PlayRecord]

    var periodName: String {
        switch range {
        case .week: "this week"
        case .month: "the last 30 days"
        case .year: "this year"
        case .all: "all time"
        }
    }

    @MainActor
    init(range: StatsRange, stats: StatsStore) {
        self.range = range
        let recs = stats.records(range)
        records = recs
        total = stats.total(recs)
        plays = stats.plays(recs)
        artistCount = Set(recs.flatMap { $0.allArtists.map(\.id) }).count
        songCount = Set(recs.map(\.songID)).count
        let cal = Calendar.current
        daysListened = Set(recs.map { cal.startOfDay(for: $0.start) }).count
        topArtists = stats.topArtists(recs, limit: 10)
        topSongs = stats.topSongs(recs, limit: 20)
        genres = stats.topGenres(recs, limit: 5)
        biggest = stats.biggestDay(recs)
        let hours = stats.hourly(recs)
        hourly = hours
        peakHour = hours.indices.max { hours[$0] < hours[$1] } ?? 20
        streak = stats.longestStreak(recs)

        // Artists first heard inside the period (for all time: in the last 90 days).
        var first: [Int: Date] = [:]
        for r in stats.records { for a in r.allArtists where first[a.id] == nil { first[a.id] = r.start } }
        let since = range == .all ? Date.now.addingTimeInterval(-90 * 86_400) : (range.interval?.start ?? .distantPast)
        discoveries = stats.topArtists(recs, limit: 200).filter { (first[$0.artist.id] ?? .distantPast) >= since }.prefix(5).map { $0 }

        let years = recs.compactMap { r -> (Int, Double)? in r.releaseYear.map { ($0, r.seconds) } }.filter { $0.0 > 1900 }
        let weight = years.reduce(0) { $0 + $1.1 }
        averageYear = weight > 0 ? Int((years.reduce(0) { $0 + Double($1.0) * $1.1 } / weight).rounded()) : nil
        oldest = recs.filter { ($0.releaseYear ?? 0) > 1900 && $0.seconds >= 30 }.min { ($0.releaseYear ?? 0) < ($1.releaseYear ?? 0) }

        let topShare = (topArtists.first?.seconds ?? 0) / max(total, 1)
        let repeatRatio = Double(plays) / Double(max(songCount, 1))
        let hour = peakHour
        if topShare > 0.3 {
            personality = .init(title: "The Devotee", blurb: "One artist has your heart, and you're not hiding it.", icon: "heart.circle.fill")
        } else if artistCount >= 60 {
            personality = .init(title: "The Explorer", blurb: "\(artistCount) artists. You never stop digging for something new.", icon: "safari.fill")
        } else if hour >= 22 || hour <= 3 {
            personality = .init(title: "The Night Owl", blurb: "Your music comes alive after dark.", icon: "moon.stars.fill")
        } else if hour >= 5 && hour <= 9 {
            personality = .init(title: "The Early Bird", blurb: "You start every day with a soundtrack.", icon: "sunrise.fill")
        } else if repeatRatio > 6 {
            personality = .init(title: "The Replayer", blurb: "When you love a song, you really love it.", icon: "repeat.circle.fill")
        } else {
            personality = .init(title: "The All-Rounder", blurb: "A bit of everything, any time of day.", icon: "circle.hexagongrid.fill")
        }
    }
}

// MARK: - Slides

enum WrappedSlide: Int, CaseIterable, Identifiable {
    case intro, minutes, biggestDay, quiz, topArtist, topSongs, genres, discoveries, clock, personality, timeMachine, streak, summary
    var id: Int { rawValue }
    var duration: Double { self == .topSongs || self == .summary ? 11 : 8 }
}

struct WrappedTheme {
    let colors: [Color]
    let ink: Color

    static let all: [WrappedTheme] = [
        .init(colors: [Color(hex: "#7C3AED"), Color(hex: "#EC4899"), Color(hex: "#F59E0B")], ink: .white),
        .init(colors: [Color(hex: "#0EA5E9"), Color(hex: "#22D3EE"), Color(hex: "#A7F3D0")], ink: Color(hex: "#082F49")),
        .init(colors: [Color(hex: "#111827"), Color(hex: "#34D399"), Color(hex: "#065F46")], ink: .white),
        .init(colors: [Color(hex: "#F97316"), Color(hex: "#FACC15"), Color(hex: "#FB7185")], ink: Color(hex: "#3B0A0A")),
        .init(colors: [Color(hex: "#1E1B4B"), Color(hex: "#6366F1"), Color(hex: "#C084FC")], ink: .white),
        .init(colors: [Color(hex: "#84CC16"), Color(hex: "#FDE047"), Color(hex: "#14532D")], ink: Color(hex: "#052E16")),
        .init(colors: [Color(hex: "#BE123C"), Color(hex: "#FB923C"), Color(hex: "#4C0519")], ink: .white),
        .init(colors: [Color(hex: "#F5F5F4"), Color(hex: "#F9A8D4"), Color(hex: "#93C5FD")], ink: Color(hex: "#1C1917"))
    ]
}

// MARK: - Wrapped player

struct WrappedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var range: StatsRange = .year
    @State private var data: WrappedData?
    @State private var slides: [WrappedSlide] = []
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var pressStart: Date?
    @State private var forward = true
    @State private var songFor: [WrappedSlide: Int] = [:]
    @State private var themeOffset = 0
    @State private var quizAnswered = false
    @State private var showShare = false
    @State private var muted = false

    private var slide: WrappedSlide { slides.indices.contains(index) ? slides[index] : .intro }
    private var theme: WrappedTheme { WrappedTheme.all[(index + themeOffset) % WrappedTheme.all.count] }

    var body: some View {
        ZStack {
            WrappedBackground(theme: theme, seed: index + themeOffset)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: index)

            if let data {
                slideView(data)
                    .id("\(index)-\(themeOffset)")
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                    .foregroundStyle(theme.ink)
                    .padding(.top, 70)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 40)
            }

            VStack(spacing: 10) {
                progressBars
                HStack {
                    Button { muted.toggle(); app.wrappedAudio.muted = muted } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(muted ? "Unmute" : "Mute")
                    Button { remix() } label: {
                        Label("Remix", systemImage: "wand.and.stars").font(.subheadline.weight(.bold)).padding(.horizontal, 10).frame(height: 32)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    Spacer()
                    if paused { Image(systemName: "pause.fill").transition(.scale.combined(with: .opacity)) }
                    Button { close() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40) }
                        .accessibilityLabel("Close")
                }
                .foregroundStyle(theme.ink)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: index)
        .animation(.easeInOut(duration: 0.25), value: paused)
        .statusBarHidden()
        .onAppear {
            app.player.pause()
            load(.year)
        }
        .onDisappear { app.wrappedAudio.stop() }
        .task { await tick() }
        .sheet(isPresented: $showShare, onDismiss: { setPaused(false) }) {
            if let data { ShareCardEditor(data: data).environment(app) }
        }
    }

    // MARK: Slide content

    @ViewBuilder
    private func slideView(_ d: WrappedData) -> some View {
        switch slide {
        case .intro: IntroSlide(data: d, range: range) { r in load(r) }
        case .minutes: MinutesSlide(data: d)
        case .biggestDay: BiggestDaySlide(data: d)
        case .quiz: QuizSlide(data: d, answered: $quizAnswered)
        case .topArtist: TopArtistSlide(data: d)
        case .topSongs: TopSongsSlide(data: d)
        case .genres: GenresSlide(data: d)
        case .discoveries: DiscoveriesSlide(data: d)
        case .clock: ClockSlide(data: d, ink: theme.ink)
        case .personality: PersonalitySlide(data: d)
        case .timeMachine: TimeMachineSlide(data: d)
        case .streak: StreakSlide(data: d)
        case .summary: SummarySlide(data: d) { setPaused(true); showShare = true }
        }
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(slides.indices, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(theme.ink.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(theme.ink)
                                .frame(width: geo.size.width * (i < index ? 1 : (i == index ? progress : 0)))
                        }
                }
                .frame(height: 3)
            }
        }
    }

    // MARK: Control

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressStart == nil {
                    pressStart = .now
                    setPaused(true)
                }
            }
            .onEnded { v in
                let held = Date.now.timeIntervalSince(pressStart ?? .now)
                pressStart = nil
                if !showShare { setPaused(false) }
                if v.translation.height > 120 { close(); return }
                if held < 0.3 && abs(v.translation.width) < 20 {
                    let width = UIScreen.main.bounds.width
                    if v.location.x < width * 0.3 { go(-1) } else { go(1) }
                } else if v.translation.width < -60 {
                    go(1)
                } else if v.translation.width > 60 {
                    go(-1)
                }
            }
    }

    private func setPaused(_ on: Bool) {
        paused = on
        app.wrappedAudio.setPaused(on)
    }

    private func tick() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            guard data != nil, !paused, !showShare else { continue }
            if slide == .quiz && !quizAnswered { continue }
            if slide == .summary && progress >= 1 { continue }
            progress = min(1, progress + 0.033 / slide.duration)
            if progress >= 1 && slide != .summary { go(1) }
        }
    }

    private func go(_ step: Int) {
        let target = index + step
        if target < 0 { progress = 0; return }
        if target >= slides.count { close(); return }
        forward = step > 0
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            index = target
            progress = 0
        }
        app.haptic(.selection)
        playSong()
    }

    private func close() {
        app.wrappedAudio.stop()
        dismiss()
    }

    private func load(_ r: StatsRange) {
        range = r
        let d = WrappedData(range: r, stats: app.stats)
        data = d
        var list: [WrappedSlide] = [.intro, .minutes]
        if d.biggest != nil { list.append(.biggestDay) }
        if d.topSongs.count >= 4 { list.append(.quiz) }
        if !d.topArtists.isEmpty { list.append(.topArtist) }
        if !d.topSongs.isEmpty { list.append(.topSongs) }
        if !d.genres.isEmpty { list.append(.genres) }
        if !d.discoveries.isEmpty { list.append(.discoveries) }
        if d.total > 0 { list.append(contentsOf: [.clock, .personality]) }
        if d.averageYear != nil { list.append(.timeMachine) }
        if d.streak.days >= 2 { list.append(.streak) }
        list.append(.summary)
        slides = list
        quizAnswered = false
        pickSongs(random: false)
        playSong()
    }

    private func remix() {
        withAnimation(.easeInOut(duration: 0.6)) { themeOffset = (themeOffset + 1 + Int.random(in: 0..<3)) % WrappedTheme.all.count }
        pickSongs(random: true)
        playSong()
        app.haptic(.medium)
    }

    private func playSong() {
        let id = songFor[slide]
        app.wrappedAudio.play(id.flatMap { app.library.entry($0) })
    }

    /// One song per slide, each relevant to what's on screen, never the same twice.
    private func pickSongs(random: Bool) {
        guard let d = data else { return }
        let lib = app.library
        var used = Set<Int>()
        var map: [WrappedSlide: Int] = [:]
        let top = d.topSongs.map(\.songID).filter { lib.isDownloaded($0) }
        func songs(byArtist id: Int) -> [Int] {
            let ranked = d.topSongs.filter { s in d.records.contains { $0.songID == s.songID && $0.allArtists.contains { $0.id == id } } }.map(\.songID)
            return ranked + lib.songs(byArtist: id).map(\.id)
        }
        func take(_ slide: WrappedSlide, _ candidates: [Int]) {
            var list = candidates.filter { lib.isDownloaded($0) && !used.contains($0) }
            if random { list.shuffle() }
            if let id = list.first ?? top.filter({ !used.contains($0) }).randomElement() ?? lib.entries.map(\.id).filter({ !used.contains($0) }).randomElement() {
                used.insert(id)
                map[slide] = id
            }
        }
        // The #1 song is saved for the top songs reveal, so the quiz isn't spoiled.
        if let first = top.first { used.insert(first); map[.topSongs] = first }
        take(.intro, Array(top.dropFirst(4).prefix(8)))
        take(.minutes, Array(top.dropFirst(1).prefix(2)))
        take(.biggestDay, [d.biggest?.topSong?.songID].compactMap { $0 })
        take(.quiz, Array(top.dropFirst(8)))
        if let a = d.topArtists.first { take(.topArtist, songs(byArtist: a.artist.id)) }
        if let g = d.genres.first {
            take(.genres, d.records.filter { $0.genre == g.name }.map(\.songID))
        }
        if let a = d.discoveries.first { take(.discoveries, songs(byArtist: a.artist.id)) }
        let cal = Calendar.current
        take(.clock, d.records.filter { cal.component(.hour, from: $0.start) == d.peakHour }.map(\.songID))
        take(.personality, Array(top.prefix(12)))
        take(.timeMachine, [d.oldest?.songID].compactMap { $0 })
        take(.streak, Array(top.dropFirst(2)))
        take(.summary, Array(top.prefix(6)))
        songFor = map
    }
}

// MARK: - Background

struct WrappedBackground: View {
    let theme: WrappedTheme
    let seed: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.colors[0]))
                for i in 0..<5 {
                    let k = Double(i + seed)
                    let x = size.width * (0.5 + 0.42 * sin(t * 0.21 + k * 1.7))
                    let y = size.height * (0.5 + 0.4 * cos(t * 0.17 + k * 2.3))
                    let r = size.width * (0.45 + 0.15 * sin(t * 0.3 + k))
                    let color = theme.colors[(i % (theme.colors.count - 1)) + 1]
                    gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(0.75)))
                }
            }
            .blur(radius: 60)
        }
        .background(theme.colors[0])
    }
}

// MARK: - Slide views

private struct Appear: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 24)
            .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay)) { shown = true } }
    }
}

extension View {
    fileprivate func appear(_ delay: Double) -> some View { modifier(Appear(delay: delay)) }
}

private struct Kicker: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.subheadline.weight(.heavy)).tracking(1.4).opacity(0.8) }
}

private struct Big: View {
    let text: String
    var size: CGFloat = 44
    var body: some View {
        Text(text).font(.system(size: size, weight: .black, design: .rounded)).lineLimit(3).minimumScaleFactor(0.5)
    }
}

private struct IntroSlide: View {
    let data: WrappedData
    let range: StatsRange
    let pick: (StatsRange) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Kicker(text: app.prefs.displayName.isEmpty ? "Hey you" : "Hey \(app.prefs.displayName)").appear(0.1)
            Big(text: "Let's look back at \(data.periodName).", size: 46).appear(0.25)
            Text("Tap to go on. Hold to pause.").opacity(0.8).appear(0.45)
            Spacer()
            HStack(spacing: 8) {
                ForEach([StatsRange.month, .year, .all]) { r in
                    Button { pick(r) } label: {
                        Text(r == .month ? "30 days" : (r == .year ? "This year" : "All time"))
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(r == range ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.white.opacity(0.18)), in: Capsule())
                            .foregroundStyle(r == range ? Color.black : Color.white)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .appear(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MinutesSlide: View {
    let data: WrappedData
    @State private var value = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Kicker(text: "You listened for").appear(0.1)
            Text("\(value)")
                .font(.system(size: 92, weight: .black, design: .rounded))
                .contentTransition(.numericText(value: Double(value)))
                .minimumScaleFactor(0.4).lineLimit(1)
            Big(text: "minutes", size: 40).appear(0.2)
            Text("That's \(Fmt.listening(data.total)) over \(data.daysListened) day\(data.daysListened == 1 ? "" : "s"), across \(data.songCount) songs.")
                .font(.title3.weight(.semibold)).appear(1.4)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).delay(0.3)) { value = Int(data.total / 60) }
        }
    }
}

private struct BiggestDaySlide: View {
    let data: WrappedData
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Kicker(text: "Your biggest day").appear(0.1)
            if let b = data.biggest {
                Big(text: b.day.formatted(.dateTime.weekday(.wide).day().month(.wide))).appear(0.25)
                Text("\(Int(b.seconds / 60)) minutes of music in one day.").font(.title2.weight(.bold)).appear(0.5)
                if let s = b.topSong {
                    HStack(spacing: 14) {
                        Artwork(url: s.artworkURL, local: Paths.songArtwork(s.songID), size: 64, seed: s.songID)
                        VStack(alignment: .leading) {
                            Text("On repeat that day").font(.caption.weight(.bold)).opacity(0.75)
                            Text(s.title).font(.headline)
                            Text(s.artist.name).opacity(0.8)
                        }
                    }
                    .appear(0.8)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuizSlide: View {
    let data: WrappedData
    @Binding var answered: Bool
    @State private var options: [StatsStore.SongStat] = []
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Kicker(text: "Quick quiz").appear(0.1)
            Big(text: "Which song did you play the most?", size: 36).appear(0.2)
            ForEach(Array(options.enumerated()), id: \.element.id) { i, s in
                Button {
                    guard picked == nil else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { picked = s.songID; answered = true }
                    AppModel.shared.haptic(s.songID == data.topSongs.first?.songID ? .success : .warning)
                } label: {
                    HStack(spacing: 12) {
                        Artwork(url: s.artworkURL, local: Paths.songArtwork(s.songID), size: 44, seed: s.songID)
                        VStack(alignment: .leading) {
                            Text(s.title).font(.headline).lineLimit(1)
                            Text(s.artist.name).font(.caption).opacity(0.8)
                        }
                        Spacer()
                        if let picked {
                            if s.songID == data.topSongs.first?.songID {
                                Image(systemName: "checkmark.circle.fill").font(.title2).transition(.scale)
                            } else if s.songID == picked {
                                Image(systemName: "xmark.circle.fill").font(.title2).transition(.scale)
                            }
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(background(s)), in: RoundedRectangle(cornerRadius: 14))
                    .scaleEffect(picked != nil && s.songID == data.topSongs.first?.songID ? 1.04 : 1)
                }
                .buttonStyle(PressStyle())
                .appear(0.35 + Double(i) * 0.1)
            }
            if let picked {
                Text(picked == data.topSongs.first?.songID ? "Nailed it. You know yourself." : "Not quite! Tap to see the full list.")
                    .font(.headline).transition(.opacity)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if options.isEmpty { options = Array(data.topSongs.prefix(4)).shuffled() }
        }
    }

    private func background(_ s: StatsStore.SongStat) -> Double {
        guard let picked else { return 0.18 }
        if s.songID == data.topSongs.first?.songID { return 0.45 }
        return s.songID == picked ? 0.08 : 0.12
    }
}

private struct TopArtistSlide: View {
    let data: WrappedData
    @State private var spin = false
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Kicker(text: "Your top artist").appear(0.1)
            if let a = data.topArtists.first {
                a.artist.picture(210)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .rotationEffect(.degrees(spin ? 0 : -8))
                    .scaleEffect(spin ? 1 : 0.6)
                    .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) { spin = true } }
                Big(text: a.artist.name).multilineTextAlignment(.center).appear(0.5)
                Text("\(Fmt.listening(a.seconds)) together · \(a.plays) plays").font(.title3.weight(.semibold)).appear(0.7)
                if data.total > 0 {
                    Text("That's \(Int(a.seconds / data.total * 100))% of everything you played.").opacity(0.85).appear(0.9)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TopSongsSlide: View {
    let data: WrappedData
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Kicker(text: "Your top songs").appear(0.1)
            ForEach(Array(data.topSongs.prefix(5).enumerated()), id: \.element.id) { i, s in
                HStack(spacing: 12) {
                    Text("\(i + 1)").font(.system(size: i == 0 ? 40 : 28, weight: .black, design: .rounded)).frame(width: 40)
                    Artwork(url: s.artworkURL, local: Paths.songArtwork(s.songID), size: i == 0 ? 72 : 52, seed: s.songID)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(i == 0 ? .title3.weight(.heavy) : .headline).lineLimit(1)
                        Text("\(s.artist.name) · \(s.plays) plays").font(.caption).opacity(0.8).lineLimit(1)
                    }
                }
                .appear(0.25 + Double(4 - i) * 0.25)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GenresSlide: View {
    let data: WrappedData
    @State private var grow = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Kicker(text: "Your sound").appear(0.1)
            if let g = data.genres.first { Big(text: g.name).appear(0.2) }
            ForEach(Array(data.genres.enumerated()), id: \.offset) { i, g in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(g.name).font(.headline); Spacer(); Text("\(Int(g.share * 100))%").font(.headline.monospacedDigit()) }
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.9)).frame(width: grow ? geo.size.width * g.share : 0)
                            }
                    }
                    .frame(height: 10)
                }
                .appear(0.3 + Double(i) * 0.12)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.5)) { grow = true } }
    }
}

private struct DiscoveriesSlide: View {
    let data: WrappedData
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Kicker(text: "New discoveries").appear(0.1)
            Big(text: "You found \(data.discoveries.count == 5 ? "lots of" : "\(data.discoveries.count)") new artist\(data.discoveries.count == 1 ? "" : "s")", size: 36).appear(0.2)
            ForEach(Array(data.discoveries.enumerated()), id: \.element.id) { i, a in
                HStack(spacing: 12) {
                    a.artist.picture(52)
                    VStack(alignment: .leading) {
                        Text(a.artist.name).font(.headline)
                        Text(Fmt.listening(a.seconds)).font(.caption).opacity(0.8)
                    }
                }
                .appear(0.4 + Double(i) * 0.12)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClockSlide: View {
    let data: WrappedData
    let ink: Color
    @State private var grow = false

    private var peakLabel: String {
        let h = data.peakHour
        switch h {
        case 5..<12: return "mornings"
        case 12..<17: return "afternoons"
        case 17..<22: return "evenings"
        default: return "late nights"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Kicker(text: "Your listening clock").appear(0.1)
            ZStack {
                let maxV = max(data.hourly.max() ?? 1, 1)
                ForEach(0..<24, id: \.self) { h in
                    let v = data.hourly[h] / maxV
                    Capsule()
                        .fill(ink.opacity(h == data.peakHour ? 1 : 0.55))
                        .frame(width: 8, height: grow ? 10 + 80 * v : 6)
                        .offset(y: -60 - (grow ? 40 * v : 3))
                        .rotationEffect(.degrees(Double(h) / 24 * 360))
                }
                VStack {
                    Text(String(format: "%02d:00", data.peakHour)).font(.system(size: 30, weight: .black, design: .rounded))
                    Text("peak hour").font(.caption.weight(.bold)).opacity(0.75)
                }
            }
            .frame(width: 300, height: 300)
            Big(text: "You live for \(peakLabel).", size: 32).multilineTextAlignment(.center).appear(0.8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.3)) { grow = true } }
    }
}

private struct PersonalitySlide: View {
    let data: WrappedData
    @State private var pop = false
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Kicker(text: "Your listening personality").appear(0.1)
            Image(systemName: data.personality.icon)
                .font(.system(size: 110))
                .scaleEffect(pop ? 1 : 0.2)
                .rotationEffect(.degrees(pop ? 0 : -40))
                .symbolEffect(.bounce, value: pop)
            Big(text: data.personality.title).multilineTextAlignment(.center).appear(0.5)
            Text(data.personality.blurb).font(.title3.weight(.semibold)).multilineTextAlignment(.center).appear(0.7)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.55).delay(0.25)) { pop = true } }
    }
}

private struct TimeMachineSlide: View {
    let data: WrappedData
    @State private var year = 2026
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Kicker(text: "Time machine").appear(0.1)
            Text("Your music's average year").font(.title3.weight(.semibold)).appear(0.2)
            Text(String(year))
                .font(.system(size: 96, weight: .black, design: .rounded))
                .contentTransition(.numericText(value: Double(year)))
            if let o = data.oldest, let y = o.releaseYear {
                Text("Oldest favorite: \(o.title) by \(o.artist.name), from \(String(y)).").font(.headline).appear(1.4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            year = Calendar.current.component(.year, from: .now)
            withAnimation(.easeInOut(duration: 1.4).delay(0.3)) { year = data.averageYear ?? year }
        }
    }
}

private struct StreakSlide: View {
    let data: WrappedData
    @State private var lit = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Kicker(text: "Longest streak").appear(0.1)
            Big(text: "\(data.streak.days) days in a row", size: 48).appear(0.2)
            if let s = data.streak.start {
                Text("Starting \(s.formatted(.dateTime.day().month(.wide))). Not a single day without music.").font(.title3.weight(.semibold)).appear(0.4)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                ForEach(0..<min(data.streak.days, 60), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 5).fill(.white.opacity(i < lit ? 0.95 : 0.18)).frame(width: 22, height: 22)
                }
            }
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            for i in 1...max(1, min(data.streak.days, 60)) {
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(.easeOut(duration: 0.2)) { lit = i }
            }
        }
    }
}

private struct SummarySlide: View {
    let data: WrappedData
    let share: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Kicker(text: "That was \(data.periodName)").appear(0.1)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top artists").font(.caption.weight(.heavy)).opacity(0.75)
                    ForEach(Array(data.topArtists.prefix(5).enumerated()), id: \.offset) { i, a in
                        Text("\(i + 1) \(a.artist.name)").font(.subheadline.weight(.bold)).lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top songs").font(.caption.weight(.heavy)).opacity(0.75)
                    ForEach(Array(data.topSongs.prefix(5).enumerated()), id: \.offset) { i, s in
                        Text("\(i + 1) \(s.title)").font(.subheadline.weight(.bold)).lineLimit(1)
                    }
                }
            }
            .appear(0.25)
            HStack(spacing: 24) {
                VStack(alignment: .leading) { Text("Minutes").font(.caption.weight(.heavy)).opacity(0.75); Text("\(Int(data.total / 60))").font(.title.weight(.black)) }
                if let g = data.genres.first {
                    VStack(alignment: .leading) { Text("Top genre").font(.caption.weight(.heavy)).opacity(0.75); Text(g.name).font(.title2.weight(.black)).lineLimit(1) }
                }
            }
            .appear(0.45)
            Spacer()
            Button(action: share) {
                Label("Share your Wrapped", systemImage: "square.and.arrow.up")
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                    .background(.white, in: Capsule()).foregroundStyle(.black)
            }
            .buttonStyle(PressStyle())
            .appear(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
