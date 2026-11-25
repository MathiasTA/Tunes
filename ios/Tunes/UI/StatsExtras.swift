import Charts
import SwiftUI

// MARK: - Song cards (song of the day / week)

/// A big card for one song. Tapping opens the song's menu; the round button plays it.
struct BigSongCard: View {
    let kicker: String
    let song: Song
    let subtitle: String
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 14) {
                song.artwork(84)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kicker.uppercased()).font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.8)
                    Text(song.title).font(.title3.weight(.bold)).lineLimit(2)
                    Text(song.artistLine).font(.subheadline).opacity(0.85).lineLimit(1)
                    Text(subtitle).font(.caption.weight(.semibold)).opacity(0.7).lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button { app.player.play([song], context: kicker) } label: {
                    Image(systemName: "play.fill").font(.title3).foregroundStyle(.black)
                        .frame(width: 46, height: 46).background(.white, in: Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Play \(song.title)")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                song.artwork(400).blur(radius: 40).saturation(1.4)
                Color.black.opacity(0.35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: look.radius(20), style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { app.sheet = .songMenu(song, playlistID: nil) }
        .accessibilityAddTraits(.isButton)
    }
}

struct SongOfTheDayCard: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let e = app.songOfTheDay {
            BigSongCard(kicker: "Song of the day", song: e.song,
                        subtitle: e.liked ? "One of your liked songs" : "Picked for you today")
        }
    }
}

struct SongOfTheWeekCard: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let s = app.stats.songOfTheWeek(), let e = app.library.entry(s.songID) {
            BigSongCard(kicker: "Song of the week", song: e.song, subtitle: "\(s.plays) plays last week")
        }
    }
}

// MARK: - On this day

struct OnThisDayCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        if let day = app.stats.onThisDay() {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(day.label, systemImage: "clock.arrow.circlepath").font(.headline)
                    Spacer()
                }
                ForEach(day.songs) { s in
                    Button {
                        if let e = app.library.entry(s.songID) { app.sheet = .songMenu(e.song, playlistID: nil) }
                    } label: {
                        HStack(spacing: 12) {
                            Artwork(url: s.artworkURL, local: Paths.songArtwork(s.songID), size: 44, seed: s.songID)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(s.artist.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text("\(max(1, s.plays))×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
        }
    }
}

// MARK: - Fun stats

struct FunStatsSection: View {
    let records: [PlayRecord]
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        let stats = app.stats
        let facts: [(String, String, StatsStore.SongFact?, (Int) -> String)] = [
            ("Longest binge", "repeat", stats.binge(records), { "\($0) times in a row" }),
            ("Ride or die", "heart.circle", stats.rideOrDie(records), { "Played on \($0) days" }),
            ("The comeback", "arrow.uturn.backward.circle", stats.comeback(records), { "Back after \($0) days" }),
            ("Most skipped", "forward.end", stats.mostSkipped(records), { "Skipped \($0) times" }),
        ]
        let albums = stats.albumsCompleted(records, library: app.library)
        let shown = facts.filter { $0.2 != nil }
        if !shown.isEmpty || stats.firstSong != nil || !albums.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fun stats").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(shown, id: \.0) { f in
                        if let fact = f.2 { card(f.0, f.1, title: fact.title, detail: f.3(fact.value), id: fact.songID, art: fact.artworkURL) }
                    }
                    if let first = stats.firstSong {
                        card("Where it began", "flag", title: first.title,
                             detail: "Your first song, \(first.start.formatted(date: .abbreviated, time: .omitted))", id: first.songID, art: first.artworkURL)
                    }
                }
                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Played start to finish", systemImage: "opticaldisc").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(albums) { a in
                                    NavigationLink(value: Route.album(a)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Artwork(url: a.coverURL, size: 90, seed: a.id)
                                            Text(a.title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).frame(width: 90, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(14)))
                }
            }
        }
    }

    private func card(_ label: String, _ icon: String, title: String, detail: String, id: Int, art: URL?) -> some View {
        Button {
            if let e = app.library.entry(id) { app.sheet = .songMenu(e.song, playlistID: nil) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(label, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    Artwork(url: art, local: Paths.songArtwork(id), size: 36, seed: id)
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(2)
                }
                Text(detail).font(.caption).foregroundStyle(look.accent).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(14)))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Your charts

struct ChartsLinkCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        NavigationLink(value: Route.yourCharts) {
            HStack(spacing: 14) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2.weight(.bold)).foregroundStyle(look.accent)
                    .frame(width: 48, height: 48).background(look.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your charts").font(.headline).foregroundStyle(.primary)
                    Text("Your weekly top 20 and the rank race").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
        }
        .buttonStyle(PressStyle())
    }
}

struct YourChartsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var mode = 0
    @State private var charts: [StatsStore.WeeklyChart] = []
    @State private var week = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("View", selection: $mode.animation(.easeInOut)) {
                    Text("Weekly chart").tag(0)
                    Text("Rank race").tag(1)
                }
                .pickerStyle(.segmented)
                if mode == 0 { weekly } else { RankRace() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themeBackground()
        .navigationTitle("Your charts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            charts = app.stats.weeklyCharts()
            week = max(0, charts.count - 1)
        }
    }

    @ViewBuilder private var weekly: some View {
        if charts.isEmpty {
            Text("Listen for a week and your first chart shows up here.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            let c = charts[min(week, charts.count - 1)]
            HStack {
                Button { withAnimation { week = max(0, week - 1) } } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                    .disabled(week == 0)
                Spacer()
                VStack(spacing: 2) {
                    Text("Week of \(c.weekStart.formatted(.dateTime.day().month(.wide)))").font(.headline)
                    Text(week == charts.count - 1 ? "This week so far" : c.weekStart.formatted(.dateTime.year())).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { withAnimation { week = min(charts.count - 1, week + 1) } } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                    .disabled(week >= charts.count - 1)
            }
            .font(.headline)
            VStack(spacing: 0) {
                ForEach(c.entries) { e in row(e) }
            }
            .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
            .id(c.id)
            .transition(.opacity)
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                withAnimation {
                    if v.translation.width < -50 { week = min(charts.count - 1, week + 1) }
                    if v.translation.width > 50 { week = max(0, week - 1) }
                }
            })
        }
    }

    private func row(_ e: StatsStore.ChartEntry) -> some View {
        let entry = app.library.entry(e.songID)
        let rec = entry == nil ? app.stats.records.last(where: { $0.songID == e.songID }) : nil
        return NavigationLink(value: Route.songJourney(e.songID)) {
            HStack(spacing: 12) {
                Text("\(e.rank)").font(.title3.weight(.heavy).monospacedDigit()).frame(width: 30)
                move(e.move).frame(width: 40)
                Artwork(url: entry?.song.artworkURL ?? rec?.artworkURL, local: Paths.songArtwork(e.songID), size: 42, seed: e.songID)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry?.song.title ?? rec?.title ?? "Song").font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(entry?.song.artistLine ?? rec?.artist.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(e.plays) plays").font(.caption.monospacedDigit())
                    Text("\(e.weeks) wk\(e.weeks == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func move(_ m: StatsStore.ChartEntry.Move) -> some View {
        switch m {
        case .new: Text("NEW").font(.caption2.weight(.heavy)).foregroundStyle(look.accent)
        case .back: Text("BACK").font(.caption2.weight(.heavy)).foregroundStyle(.orange)
        case .same: Image(systemName: "minus").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        case .up(let n): Label("\(n)", systemImage: "arrowtriangle.up.fill").font(.caption.weight(.bold)).foregroundStyle(.green).labelStyle(TightLabel())
        case .down(let n): Label("\(n)", systemImage: "arrowtriangle.down.fill").font(.caption.weight(.bold)).foregroundStyle(.red).labelStyle(TightLabel())
        }
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.icon.font(.system(size: 8)); configuration.title }
    }
}

/// Your top 10 songs of the last months as crossing lines: who overtook whom.
struct RankRace: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var highlighted: Int?
    @State private var data: [(id: Int, title: String, points: [(Date, Int)])] = []
    @State private var span = ""
    @State private var tooShort = false

    static let colors: [Color] = [.pink, .orange, .yellow, .green, .teal, .cyan, .blue, .indigo, .purple, .red]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your top 10 songs \(span). Tap a song to follow it.").font(.footnote).foregroundStyle(.secondary)
            if tooShort || data.isEmpty {
                Text("The race starts after a couple of days of listening.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.element.id) { i, s in
                        ForEach(s.points, id: \.0) { p in
                            LineMark(x: .value("Day", p.0), y: .value("Rank", p.1), series: .value("Song", "\(s.id)"))
                                .foregroundStyle(Self.colors[i % Self.colors.count])
                                .lineStyle(StrokeStyle(lineWidth: highlighted == s.id ? 4 : 2.2, lineCap: .round))
                                .interpolationMethod(.monotone)
                                .opacity(highlighted == nil || highlighted == s.id ? 1 : 0.15)
                            PointMark(x: .value("Day", p.0), y: .value("Rank", p.1))
                                .foregroundStyle(Self.colors[i % Self.colors.count])
                                .symbolSize(highlighted == s.id ? 50 : 22)
                                .opacity(highlighted == nil || highlighted == s.id ? 1 : 0.15)
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartYAxis { AxisMarks(position: .leading, values: [1, 5, 10, 15, 20]) { v in AxisGridLine(); AxisValueLabel { if let r = v.as(Int.self) { Text("#\(r)") } } } }
                .frame(height: 280)
                .padding(12)
                .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
                VStack(spacing: 0) {
                    ForEach(Array(data.enumerated()), id: \.element.id) { i, s in
                        Button { withAnimation(.easeInOut) { highlighted = highlighted == s.id ? nil : s.id } } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Self.colors[i % Self.colors.count]).frame(width: 10, height: 10)
                                Text(s.title).font(.subheadline.weight(highlighted == s.id ? .bold : .regular)).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                if let r = s.points.last?.1 { Text("#\(r)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
            }
        }
        .onAppear(perform: build)
    }

    private func build() {
        let stats = app.stats
        let now = Date.now
        guard let first = stats.records.first?.start else { tooShort = true; return }
        let history = now.timeIntervalSince(first)
        guard history >= 2 * 86_400 else { tooShort = true; return }
        // Fit the race to your history: daily checks for the first 16 weeks, weekly after that.
        let daily = history < 16 * 7 * 86_400
        let step: TimeInterval = daily ? 86_400 : 7 * 86_400
        let start = daily ? first : now.addingTimeInterval(-16 * 7 * 86_400)
        let days = Int(now.timeIntervalSince(start) / 86_400)
        span = daily ? "over the last \(max(2, days)) days" : "over the last 16 weeks"
        let top = Array(stats.ranking(stats.playCounts(from: start, to: now)).prefix(10))
        var series: [Int: [(Date, Int)]] = [:]
        var t = start.addingTimeInterval(step)
        while t <= now.addingTimeInterval(step - 1) {
            let at = min(t, now)
            let window = min(28 * 86_400, at.timeIntervalSince(first))
            let ranks = stats.ranking(stats.playCounts(from: at.addingTimeInterval(-window), to: at))
            for id in top {
                if let r = ranks.firstIndex(of: id), r < 20 { series[id, default: []].append((at, r + 1)) }
            }
            t = t.addingTimeInterval(step)
        }
        data = top.compactMap { id in
            guard let pts = series[id], !pts.isEmpty else { return nil }
            let title = app.library.entry(id)?.song.title ?? stats.records.last(where: { $0.songID == id })?.title ?? "Song"
            return (id: id, title: title, points: pts)
        }
    }
}

/// One song's climb up (and down) your charts.
struct SongJourneyView: View {
    let songID: Int
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var points: [(date: Date, rank: Int?)] = []
    @State private var selected: (date: Date, rank: Int)?

    var body: some View {
        let entry = app.library.entry(songID)
        let rec = app.stats.records.last(where: { $0.songID == songID })
        let ranked = points.compactMap { p in p.rank.map { (p.date, $0) } }
        let peak = ranked.min { $0.1 < $1.1 }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Artwork(url: entry?.song.artworkURL ?? rec?.artworkURL, local: Paths.songArtwork(songID), size: 72, seed: songID)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry?.song.title ?? rec?.title ?? "Song").font(.title3.bold()).lineLimit(2)
                        Text(entry?.song.artistLine ?? rec?.artist.name ?? "").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 10) {
                    stat("Peak", peak.map { "#\($0.1)" } ?? "–")
                    stat("Weeks in top 10", "\(ranked.filter { $0.1 <= 10 }.count)")
                    stat("Now", points.last?.rank.map { "#\($0)" } ?? "Off chart")
                }
                if ranked.count < 2 {
                    Text("Keep listening: this song's journey shows up after a couple of weeks.").foregroundStyle(.secondary)
                        .padding(.vertical, 30)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selected.map { "Week of \($0.date.formatted(.dateTime.day().month(.abbreviated))) · #\($0.rank)" } ?? "Drag across to read a week")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(selected == nil ? .secondary : .primary)
                            .contentTransition(.numericText())
                        chart(ranked, peak: peak)
                    }
                    .padding(14)
                    .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
                    Text("Rank is where the song placed among your songs by plays over 4 weeks, checked every week. The line only shows while it's in your top 50.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .themeBackground()
        .navigationTitle("Chart history")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { points = app.stats.journey(of: songID) }
    }

    private func chart(_ ranked: [(Date, Int)], peak: (Date, Int)?) -> some View {
        let first = ranked.first
        return Chart {
            ForEach(ranked, id: \.0) { p in
                LineMark(x: .value("Week", p.0), y: .value("Rank", p.1))
                    .foregroundStyle(look.accent).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Week", p.0), yStart: .value("Rank", p.1), yEnd: .value("Bottom", 50))
                    .foregroundStyle(LinearGradient(colors: [look.accent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            if let f = first {
                PointMark(x: .value("Week", f.0), y: .value("Rank", f.1)).foregroundStyle(.secondary).symbolSize(60)
                    .annotation(position: .bottom) { Text("First").font(.caption2).foregroundStyle(.secondary) }
            }
            if let p = peak {
                PointMark(x: .value("Week", p.0), y: .value("Rank", p.1)).foregroundStyle(look.accent).symbolSize(110)
                    .annotation(position: .top) { Text("Peak #\(p.1)").font(.caption2.weight(.bold)).foregroundStyle(look.accent) }
            }
            if let s = selected {
                RuleMark(x: .value("Week", s.date)).foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisValueLabel { if let r = v.as(Int.self) { Text("#\(r)") } } } }
        .chartOverlay { proxy in
            GeometryReader { g in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard let frame = proxy.plotFrame else { return }
                            let x = v.location.x - g[frame].origin.x
                            guard let d: Date = proxy.value(atX: x) else { return }
                            if let near = ranked.min(by: { abs($0.0.timeIntervalSince(d)) < abs($1.0.timeIntervalSince(d)) }) {
                                if selected?.date != near.0 { app.haptic(.selection) }
                                selected = (near.0, near.1)
                            }
                        }
                        .onEnded { _ in withAnimation { selected = nil } })
            }
        }
        .frame(height: 240)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(14)))
    }
}

// MARK: - Recaps

/// The recap block on Home: shows for a few days after a week (Mon–Wed) or month (1st–3rd) ends.
struct RecapCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    private var which: Bool? {
        let cal = Calendar.current
        if cal.component(.day, from: .now) <= 3, let m = StatsStore.lastMonth(), !app.stats.records(in: m).isEmpty { return false }
        let wd = cal.component(.weekday, from: .now) // 1 = Sunday
        if (2...4).contains(wd), let w = StatsStore.lastWeek(), !app.stats.records(in: w).isEmpty { return true }
        return nil
    }

    var body: some View {
        if let weekly = which {
            Button { app.openRecap(weekly: weekly) } label: {
                HStack(spacing: 14) {
                    Image(systemName: weekly ? "calendar" : "calendar.badge.clock").font(.system(size: 30, weight: .bold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(weekly ? "YOUR WEEK IN MUSIC" : "YOUR MONTH IN MUSIC").font(.caption2.weight(.heavy)).tracking(1.2).opacity(0.85)
                        Text(weekly ? "Last week, wrapped" : (StatsStore.lastMonth()?.start.formatted(.dateTime.month(.wide)) ?? "Last month") + ", wrapped")
                            .font(.title3.weight(.black))
                    }
                    Spacer()
                    Image(systemName: "play.fill").padding(12).background(.white.opacity(0.22), in: Circle())
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(LinearGradient(colors: [Color(hex: "#7C3AED"), Color(hex: "#EC4899")], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: look.radius(20), style: .continuous))
            }
            .buttonStyle(PressStyle())
        }
    }
}

/// Every past week and month, to replay as a recap.
struct RecapsView: View {
    @Environment(AppModel.self) private var app

    private static func periods(_ stats: StatsStore) -> (weeks: [DateInterval], months: [DateInterval]) {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let weeks: [DateInterval] = (1...12).compactMap { k in
            guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start,
                  let s = cal.date(byAdding: .weekOfYear, value: -k, to: thisWeek),
                  let e = cal.date(byAdding: .weekOfYear, value: 1, to: s) else { return nil }
            return DateInterval(start: s, end: e)
        }.filter { !stats.records(in: $0).isEmpty }
        let months: [DateInterval] = (1...12).compactMap { k in
            guard let thisMonth = cal.dateInterval(of: .month, for: .now)?.start,
                  let s = cal.date(byAdding: .month, value: -k, to: thisMonth),
                  let e = cal.date(byAdding: .month, value: 1, to: s) else { return nil }
            return DateInterval(start: s, end: e)
        }.filter { !stats.records(in: $0).isEmpty }
        return (weeks, months)
    }

    var body: some View {
        let stats = app.stats
        let (weeks, months) = Self.periods(stats)
        List {
            if weeks.isEmpty && months.isEmpty {
                Text("Your first recap shows up after your first full week of listening.").foregroundStyle(.secondary)
            }
            if !months.isEmpty {
                Section("Months") {
                    ForEach(months, id: \.start) { m in
                        recapRow(m.start.formatted(.dateTime.month(.wide).year()), stats.total(stats.records(in: m))) {
                            app.openRecap(weekly: false, interval: m)
                        }
                    }
                }
                .themedRow()
            }
            if !weeks.isEmpty {
                Section("Weeks") {
                    ForEach(weeks, id: \.start) { w in
                        recapRow("Week of \(w.start.formatted(.dateTime.day().month(.abbreviated)))", stats.total(stats.records(in: w))) {
                            app.openRecap(weekly: true, interval: w)
                        }
                    }
                }
                .themedRow()
            }
        }
        .themedForm()
        .navigationTitle("Recaps")
    }

    private func recapRow(_ title: String, _ seconds: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(Fmt.listening(seconds)).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "play.circle.fill").foregroundStyle(.tint)
            }
        }
    }
}
