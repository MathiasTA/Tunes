import Charts
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @AppStorage("statsRange") private var range: StatsRange = .month
    @State private var allArtists = false
    @State private var allSongs = false

    var body: some View {
        let stats = app.stats
        let recs = stats.records(range)
        let artists = stats.topArtists(recs, limit: 10)
        let songs = stats.topSongs(recs, limit: 10)
        let buckets = stats.buckets(range)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WrappedCard()
                SongOfTheDayCard()
                SongOfTheWeekCard()
                OnThisDayCard()
                Picker("Range", selection: $range.animation(.easeInOut)) {
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    tile("Listened", Fmt.listening(stats.total(recs)), "clock.fill")
                    tile("Plays", "\(stats.plays(recs))", "play.fill")
                    tile("Artists", "\(Set(recs.flatMap { $0.allArtists.map(\.id) }).count)", "person.2.fill")
                    tile("Songs", "\(Set(recs.map(\.songID)).count)", "music.note")
                }

                if !buckets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minutes per \(range.bucket == .day ? "day" : "month")").font(.headline)
                        Chart(buckets) { b in
                            BarMark(x: .value("Date", b.date, unit: range.bucket), y: .value("Minutes", b.minutes))
                                .foregroundStyle(look.accent.gradient)
                                .cornerRadius(3)
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 170)
                        .animation(.easeInOut, value: range)
                    }
                    .padding(14)
                    .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
                }

                ListeningCalendar()

                if recs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No listening yet in this period").font(.headline)
                        Text("Play your downloaded songs and your stats build up here. You can also bring in your Spotify history from Settings → Backup & import.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                }

                if !artists.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top artists").font(.title3.bold())
                        ForEach(Array(artists.prefix(allArtists ? 10 : 5).enumerated()), id: \.element.id) { i, a in
                            NavigationLink(value: Route.artist(a.artist)) {
                                HStack(spacing: 12) {
                                    Text("\(i + 1)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                                    a.artist.picture(46)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.artist.name).foregroundStyle(.primary)
                                        Text("\(Fmt.listening(a.seconds)) · \(a.plays) plays").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .disabled(a.artist.id < 0)
                        }
                        if artists.count > 5 { ShowMoreButton(expanded: $allArtists) }
                    }
                }

                ChartsLinkCard()

                if !songs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top songs").font(.title3.bold())
                        ForEach(Array(songs.prefix(allSongs ? 10 : 5).enumerated()), id: \.element.id) { i, s in
                            NavigationLink(value: Route.songStats(s.songID)) {
                                HStack(spacing: 12) {
                                    Text("\(i + 1)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                                    Artwork(url: s.artworkURL, local: Paths.songArtwork(s.songID), size: 46, seed: s.songID)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title).foregroundStyle(.primary).lineLimit(1)
                                        Text("\(s.artist.name) · \(s.plays) plays").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(Fmt.listening(s.seconds)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if songs.count > 5 { ShowMoreButton(expanded: $allSongs) }
                    }
                }


                NavigationLink(value: Route.recaps) {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles.rectangle.stack.fill").font(.title2).foregroundStyle(look.accent).frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recaps").font(.headline).foregroundStyle(.primary)
                            Text("Replay any past week or month").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
                }
                .buttonStyle(PressStyle())

                let genres = stats.topGenres(recs)
                if !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top genres").font(.title3.bold())
                        ForEach(genres, id: \.name) { g in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(g.name); Spacer(); Text("\(Int(g.share * 100))%").foregroundStyle(.secondary) }.font(.subheadline)
                                GeometryReader { geo in
                                    Capsule().fill(Color.secondary.opacity(0.2))
                                        .overlay(alignment: .leading) { Capsule().fill(look.accent).frame(width: geo.size.width * g.share) }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themeBackground()
        .navigationTitle("Stats")
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(14)))
    }
}

struct WrappedCard: View {
    @Environment(AppModel.self) private var app
    @State private var phase = false

    var body: some View {
        Button { app.player.pause(); app.showWrapped = true } label: {
            ZStack(alignment: .leading) {
                LinearGradient(colors: [Color(hex: "#7C3AED"), Color(hex: "#EC4899"), Color(hex: "#F59E0B")],
                               startPoint: phase ? .topLeading : .bottomLeading, endPoint: phase ? .bottomTrailing : .topTrailing)
                Circle().fill(.white.opacity(0.15)).frame(width: 140).offset(x: 230, y: phase ? -30 : 20)
                Circle().fill(.black.opacity(0.12)).frame(width: 90).offset(x: 280, y: phase ? 40 : -10)
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR WRAPPED").font(.caption.weight(.heavy)).tracking(1.5).opacity(0.85)
                    Text("Your year in music").font(.title2.weight(.black))
                    HStack(spacing: 6) {
                        Text(app.stats.records.isEmpty ? "Listen to some music first" : "Play it")
                        Image(systemName: "play.fill")
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.white.opacity(0.22), in: Capsule())
                    .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(app.stats.records.isEmpty)
        .onAppear { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { phase = true } }
    }
}

struct SongStatsView: View {
    let songID: Int
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        let recs = app.stats.records.filter { $0.songID == songID }
        let entry = app.library.entry(songID)
        let title = entry?.song.title ?? recs.last?.title ?? "Song"
        let cal = Calendar.current
        let monthly: [(Date, Double)] = Dictionary(grouping: recs) { cal.dateInterval(of: .month, for: $0.start)?.start ?? $0.start }
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.seconds } / 60) }
            .sorted { $0.0 < $1.0 }
        List {
            Section {
                VStack(spacing: 10) {
                    if let s = entry?.song { s.artwork(150) } else {
                        Artwork(url: recs.last?.artworkURL, local: Paths.songArtwork(songID), size: 150, seed: songID)
                    }
                    Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                    Text(entry?.song.artistLine ?? recs.last?.artist.name ?? "").foregroundStyle(.secondary)
                    if let s = entry?.song {
                        PillButton(title: "Play", icon: "play.fill", prominent: true) { app.player.play([s], context: s.title) }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
.themedRow()
            Section {
                LabeledContent("Listened", value: Fmt.listening(recs.reduce(0) { $0 + $1.seconds }))
                LabeledContent("Plays", value: "\(recs.filter { $0.seconds >= StatsStore.playThreshold }.count)")
                if let f = recs.first { LabeledContent("First played", value: f.start.formatted(date: .abbreviated, time: .omitted)) }
                if let l = recs.last { LabeledContent("Last played", value: l.start.formatted(.relative(presentation: .named))) }
                if let e = entry { LabeledContent("Downloaded", value: e.addedAt.formatted(date: .abbreviated, time: .omitted)) }
                let imported = recs.filter { $0.origin == .spotify }.count
                if imported > 0 { LabeledContent("From Spotify history", value: "\(imported) plays") }
            }
.themedRow()
            Section {
                NavigationLink(value: Route.songJourney(songID)) {
                    Label("Chart history", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
.themedRow()
            if monthly.count > 1 {
                Section("Minutes per month") {
                    Chart(monthly, id: \.0) { m in
                        BarMark(x: .value("Month", m.0, unit: .month), y: .value("Minutes", m.1)).foregroundStyle(look.accent.gradient)
                    }
                    .frame(height: 160)
                }
.themedRow()
            }
        }
        .themedForm()
        .navigationTitle("Song stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// A year of listening as a calendar heat map: one square per day, brighter the more you listened.
/// Tap a day to see how long you listened and what you played most.
struct ListeningCalendar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var selected: Date?

    private let weeks = 53
    private let cell: CGFloat = 12
    private let gap: CGFloat = 3

    var body: some View {
        let cal = Calendar.current
        let daily = app.stats.daily()
        let today = cal.startOfDay(for: .now)
        // Columns are weeks (Monday first), the last column holds today.
        let weekday = (cal.component(.weekday, from: today) + 5) % 7 // Monday = 0
        let start = cal.date(byAdding: .day, value: -(weekday + 7 * (weeks - 1)), to: today) ?? today
        let peak = max(daily.values.max() ?? 1, 60)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Listening calendar").font(.headline)
                Spacer()
                Text("\(daily.keys.filter { $0 >= start }.count) days with music").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<weeks, id: \.self) { w in
                            VStack(spacing: gap) {
                                monthLabel(cal.date(byAdding: .day, value: w * 7, to: start) ?? start, week: w)
                                ForEach(0..<7, id: \.self) { d in
                                    let day = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                                    square(day: day, seconds: daily[day] ?? 0, peak: peak, future: day > today)
                                }
                            }
                            .id(w)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(weeks - 1, anchor: .trailing) }
            }
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2.5).fill(color(Double(i) / 4)).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
            if let day = selected { dayDetail(day, seconds: daily[day] ?? 0) }
        }
        .padding(14)
        .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16)))
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    private func monthLabel(_ weekStart: Date, week: Int) -> some View {
        let cal = Calendar.current
        let day = cal.component(.day, from: weekStart)
        let show = week == 0 ? day <= 21 : day <= 7
        return Text(show ? weekStart.formatted(.dateTime.month(.abbreviated)) : " ")
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            .fixedSize()
            .frame(width: cell, height: 11, alignment: .leading)
    }

    private func color(_ level: Double) -> Color {
        level <= 0 ? Color.secondary.opacity(0.15) : look.accent.opacity(0.25 + 0.75 * level)
    }

    private func square(day: Date, seconds: Double, peak: Double, future: Bool) -> some View {
        // Square root so a few huge days don't make everything else look empty.
        let level = seconds > 0 ? max(0.08, sqrt(seconds / peak)) : 0
        let isSelected = selected == day
        return RoundedRectangle(cornerRadius: 2.5)
            .fill(future ? Color.clear : color(level))
            .frame(width: cell, height: cell)
            .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(isSelected ? Color.primary : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
            .onTapGesture {
                guard !future else { return }
                selected = isSelected ? nil : day
                app.haptic(.selection)
            }
            .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)): \(Fmt.listening(seconds))")
    }

    private func dayDetail(_ day: Date, seconds: Double) -> some View {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let recs = app.stats.records(in: DateInterval(start: day, end: end))
        let top = app.stats.topSongs(recs, limit: 3)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline.weight(.semibold))
                Spacer()
                Text(seconds > 0 ? Fmt.listening(seconds) : "No music").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(top) { s in
                HStack(spacing: 10) {
                    Artwork(url: s.artworkURL, local: Paths.songArtwork(s.songID), size: 34, seed: s.songID)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title).font(.footnote.weight(.semibold)).lineLimit(1)
                        Text(s.artist.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(max(s.plays, 1))×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
        .transition(.opacity)
    }
}


/// "Show top 10" / "Show less" under a top-5 list.
struct ShowMoreButton: View {
    @Binding var expanded: Bool
    @Environment(\.look) private var look
    var body: some View {
        Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() } } label: {
            HStack(spacing: 4) {
                Text(expanded ? "Show less" : "Show top 10")
                Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(look.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
