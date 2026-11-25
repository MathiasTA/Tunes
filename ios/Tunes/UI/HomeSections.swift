import SwiftUI

/// One thing shown in a Home section: a song, album, artist, playlist or chart.
struct HomeItem: Identifiable {
    enum Art {
        case song(Song), album(Album), artist(Artist), playlist(Playlist), chart(ChartSource), liked
    }
    let id: String
    let title: String
    let subtitle: String?
    let art: Art
    var badge: String? = nil

    var isArtist: Bool { if case .artist = art { true } else { false } }
    var song: Song? { if case .song(let s) = art { s } else { nil } }

    var route: Route? {
        switch art {
        case .song: nil
        case .album(let a): .album(a)
        case .artist(let a): .artist(a)
        case .playlist(let p): .playlist(p.id)
        case .chart(let c): .chart(c)
        case .liked: .liked
        }
    }
}

/// Draws a Home section's items in whichever layout the user picked.
struct HomeSectionView: View {
    let title: String
    var trailing: AnyView? = nil
    let layout: HomeLayout
    let count: Int
    let items: [HomeItem]
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    private var shown: [HomeItem] { Array(items.prefix(count)) }
    private var songs: [Song] { shown.compactMap(\.song) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                if let trailing { trailing }
            }
            .padding(.horizontal)
            switch layout {
            case .bigCovers: carousel(size: 150)
            case .smallCovers: carousel(size: 104)
            case .featured: featured
            case .compactGrid: compactGrid
            case .coverGrid: coverGrid
            case .list: rows(numbered: false)
            case .numbered: rows(numbered: true)
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func art(_ item: HomeItem, _ size: CGFloat) -> some View {
        switch item.art {
        case .song(let s): s.artwork(size)
        case .album(let a):
            a.cover(size).overlay(alignment: .topLeading) {
                if let b = item.badge {
                    Text(b).font(.system(size: max(8, size * 0.07), weight: .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(look.accent, in: Capsule()).foregroundStyle(.black).padding(6)
                }
            }
        case .artist(let a): a.picture(size)
        case .playlist(let p): PlaylistTile(playlist: p, size: size)
        case .chart(let c): ChartArt(source: c, size: size)
        case .liked: LikedTile(size: size)
        }
    }

    /// Songs open their menu; everything else opens its page.
    @ViewBuilder
    private func tappable<Content: View>(_ item: HomeItem, @ViewBuilder _ content: () -> Content) -> some View {
        if let route = item.route {
            NavigationLink(value: route) { content() }.buttonStyle(PressStyle())
        } else if let s = item.song {
            Button { app.sheet = .songMenu(s, playlistID: nil) } label: { content() }.buttonStyle(PressStyle())
        }
    }

    private func tile(_ item: HomeItem, size: CGFloat) -> some View {
        tappable(item) {
            VStack(alignment: item.isArtist ? .center : .leading, spacing: 5) {
                art(item, size)
                Text(item.title).font(size > 120 ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                    .lineLimit(1).foregroundStyle(.primary)
                if let sub = item.subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(size > 120 ? 2 : 1)
                }
            }
            .frame(width: size + (item.isArtist ? 8 : 0), alignment: item.isArtist ? .center : .leading)
        }
    }

    private func carousel(size: CGFloat, items list: [HomeItem]? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: size > 120 ? 14 : 12) {
                ForEach(list ?? shown) { tile($0, size: $0.isArtist ? size * 0.85 : size) }
            }
            .padding(.horizontal)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }

    @ViewBuilder private var featured: some View {
        if let first = shown.first {
            tappable(first) {
                HStack(spacing: 14) {
                    art(first, 120)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(first.title).font(.title3.bold()).lineLimit(2).foregroundStyle(.primary)
                        if let sub = first.subtitle { Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(18), style: .continuous))
                .padding(.horizontal)
            }
            if shown.count > 1 { carousel(size: 104, items: Array(shown.dropFirst())) }
        }
    }

    private var compactGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(shown) { item in
                tappable(item) {
                    HStack(spacing: 10) {
                        art(item, 52)
                        Text(item.title).font(.footnote.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, 6)
                    .frame(height: 52)
                    .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(8), style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: look.radius(8), style: .continuous))
                }
            }
        }
        .padding(.horizontal)
    }

    private var coverGrid: some View {
        let size = (UIScreen.main.bounds.width - 32 - 20) / 3
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 10), count: 3), alignment: .leading, spacing: 14) {
            ForEach(shown) { tile($0, size: $0.isArtist ? size - 8 : size) }
        }
        .padding(.horizontal)
    }

    private func rows(numbered: Bool) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                HStack(spacing: numbered ? 8 : 0) {
                    if numbered {
                        Text("\(i + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                    }
                    if let s = item.song {
                        SongRow(song: s, queue: songs, context: title)
                    } else {
                        tappable(item) {
                            HStack(spacing: 12) {
                                art(item, 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(1).foregroundStyle(.primary)
                                    if let sub = item.subtitle { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

/// The colored square used for charts.
struct ChartArt: View {
    let source: ChartSource
    let size: CGFloat
    @Environment(\.look) private var look

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: source.colorHex)
            VStack(alignment: .leading, spacing: 0) {
                Text(source.kind == .deezerGenre && source.ref != "0" ? "GENRE" : "TOP")
                    .font(.system(size: max(8, size * 0.08), weight: .heavy)).foregroundStyle(.white.opacity(0.8))
                Text(source.name.replacingOccurrences(of: "Top ", with: ""))
                    .font(.system(size: max(9, size * 0.13), weight: .heavy)).foregroundStyle(.white).lineLimit(2)
            }
            .padding(size * 0.07)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: look.radius(size > 60 ? 12 : 6), style: .continuous))
    }
}


// MARK: - Dice

/// A big button that plays a random song, from the source chosen in Customize Home.
struct DiceBlock: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var spin = 0.0
    @State private var face = 5

    var body: some View {
        let source = app.prefs.data.diceSource
        Button(action: roll) {
            HStack(spacing: 16) {
                Image(systemName: "die.face.\(face).fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(spin))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Roll the dice").font(.title3.weight(.heavy))
                    Label(subtitle(source), systemImage: source.icon)
                        .font(.footnote.weight(.semibold)).opacity(0.85).lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.title3).foregroundStyle(.white.opacity(0.9))
                    .padding(12).background(.white.opacity(0.18), in: Circle())
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [look.accent, look.accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: look.radius(20), style: .continuous))
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal)
        .accessibilityLabel("Roll the dice: play a random song from \(subtitle(source))")
    }

    private func subtitle(_ s: DiceSource) -> String {
        switch s {
        case .artist: return app.prefs.data.diceArtist?.name ?? "Pick an artist"
        case .playlist: return app.prefs.data.dicePlaylistID.flatMap { app.playlists.playlist($0)?.name } ?? "Pick a playlist"
        default: return s.label
        }
    }

    private func roll() {
        let pool = Self.pool(app)
        guard let pick = pool.randomElement() else {
            app.show("Nothing to roll from yet. Try another source in Customize Home.")
            app.haptic(.warning)
            return
        }
        app.haptic(.medium)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) {
            spin += 360 * 2
            face = Int.random(in: 1...6)
        }
        let rest = pool.filter { $0.id != pick.id }.shuffled().prefix(99)
        app.player.play([pick] + rest, startAt: 0, context: "Roll the dice")
        app.bump("diceRolls")
    }

    /// The songs the dice can land on.
    static func pool(_ app: AppModel) -> [Song] {
        let lib = app.library, stats = app.stats
        let prefs = app.prefs.data
        let all = lib.entries
        switch prefs.diceSource {
        case .anything:
            return all.map(\.song)
        case .favorites:
            return lib.liked.map(\.song)
        case .recentFavorites:
            let recent = stats.records(.month)
            return stats.topSongs(recent, limit: 40).compactMap { lib.entry($0.songID)?.song }
        case .pastFavorites:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
            var plays: [Int: Int] = [:], last: [Int: Date] = [:]
            for r in stats.records where r.seconds >= StatsStore.playThreshold {
                plays[r.songID, default: 0] += 1
                last[r.songID] = max(last[r.songID] ?? .distantPast, r.start)
            }
            return all.filter { (plays[$0.id] ?? 0) >= 5 && (last[$0.id] ?? .distantPast) < cutoff }.map(\.song)
        case .artist:
            guard let a = prefs.diceArtist else { return [] }
            return lib.songs(byArtist: a.id)
        case .neverPlayed:
            let played = Set(stats.records.map(\.songID))
            return all.filter { !played.contains($0.id) }.map(\.song)
        case .playlist:
            guard let id = prefs.dicePlaylistID, let p = app.playlists.playlist(id) else { return [] }
            return p.songs.filter { lib.isDownloaded($0.id) }
        }
    }
}
