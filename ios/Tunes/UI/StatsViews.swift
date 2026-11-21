import Charts
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @AppStorage("statsRange") private var range: StatsRange = .month

    var body: some View {
        let stats = app.stats
        let recs = stats.records(range)
        let artists = stats.topArtists(recs, limit: 10)
        let songs = stats.topSongs(recs, limit: 10)
        let buckets = stats.buckets(range)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WrappedCard()
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
                        ForEach(Array(artists.enumerated()), id: \.element.id) { i, a in
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
                    }
                }

                if !songs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top songs").font(.title3.bold())
                        ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
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
                    }
                }

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
        .background(Surface.background(look))
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
            Section {
                LabeledContent("Listened", value: Fmt.listening(recs.reduce(0) { $0 + $1.seconds }))
                LabeledContent("Plays", value: "\(recs.filter { $0.seconds >= StatsStore.playThreshold }.count)")
                if let f = recs.first { LabeledContent("First played", value: f.start.formatted(date: .abbreviated, time: .omitted)) }
                if let l = recs.last { LabeledContent("Last played", value: l.start.formatted(.relative(presentation: .named))) }
                if let e = entry { LabeledContent("Downloaded", value: e.addedAt.formatted(date: .abbreviated, time: .omitted)) }
                let imported = recs.filter { $0.origin == .spotify }.count
                if imported > 0 { LabeledContent("From Spotify history", value: "\(imported) plays") }
            }
            if monthly.count > 1 {
                Section("Minutes per month") {
                    Chart(monthly, id: \.0) { m in
                        BarMark(x: .value("Month", m.0, unit: .month), y: .value("Minutes", m.1)).foregroundStyle(look.accent.gradient)
                    }
                    .frame(height: 160)
                }
            }
        }
        .navigationTitle("Song stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}
