import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var trending: [Song] = []
    @State private var releases: [Album] = []
    @State private var showCustomize = false
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Namespace private var ns

    private var offline: Bool { app.prefs.data.offline || !app.network.isOnline }
    private let searchSpring = Animation.spring(response: 0.48, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .top) {
            ThemeBackground().ignoresSafeArea()
            if searching {
                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                    SearchResultsList(query: $query)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 40)), removal: .opacity))
                }
            } else {
                home
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -30)),
                                            removal: .offset(y: 320).combined(with: .opacity)))
            }
        }
        .toolbar(searching ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { app.sheet = .profile } label: { ProfileAvatar(size: 34) }
                    .accessibilityLabel("Your profile")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCustomize = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Customize home")
            }
        }
        .sheet(isPresented: $showCustomize) {
            NavigationStack { CustomizeHomeView(asSheet: true) }.environment(app).environment(\.look, look).tint(look.accent)
        }
        .task { await loadDiscovery() }
        .onChange(of: app.homeReselect) { _, _ in if searching { endSearch() } }
    }

    private var home: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header.id("top")
                if offline {
                    OfflineBanner().padding(.horizontal)
                }
                ForEach(app.prefs.data.home.filter(\.visible)) { section in
                    sectionView(section.kind)
                }
                if app.library.entries.isEmpty && app.stats.records.isEmpty && !offline {
                    tip
                }
                Color.clear.frame(height: 12)
            }
            .padding(.top, 4)
        }
        .themeBackground()
        .onChange(of: app.homeReselect) { _, _ in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { proxy.scrollTo("top", anchor: .top) }
        }
        .refreshable {
            await app.playlists.refreshAll(force: true)
            await loadDiscovery(force: true)
        }
        }
    }

    private func startSearch() {
        app.haptic(.light)
        withAnimation(searchSpring) { searching = true }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            searchFocused = true
        }
    }

    private func endSearch() {
        searchFocused = false
        withAnimation(searchSpring) {
            searching = false
            query = ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(greeting).font(.largeTitle.bold()).contentTransition(.opacity)
            searchButton
        }
        .padding(.horizontal)
    }

    /// The bar in the Home header. Tapping it lifts it to the top, where it becomes the real search field.
    private var searchButton: some View {
        Button(action: startSearch) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                Text(offline ? "Search your downloads" : "Search artists, songs, albums")
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).frame(height: 46)
            .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(12), style: .continuous))
            .matchedGeometryEffect(id: "searchBar", in: ns)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Search")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(offline ? "Search your downloads" : "Artists, songs, albums", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { SearchHistory.remember(query) }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(12), style: .continuous))
            .matchedGeometryEffect(id: "searchBar", in: ns)
            Button("Cancel", action: endSearch)
                .font(.body.weight(.medium))
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return app.prefs.displayName.isEmpty ? part : "\(part), \(app.prefs.displayName)"
    }

    private var tip: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(look.accent)
            Text("Home fills up with your own music as you listen. Tap \(Image(systemName: "slider.horizontal.3")) to change it any time.")
                .font(.footnote)
        }
        .padding(14)
        .background(look.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: look.radius(14)))
        .padding(.horizontal)
    }

    private func loadDiscovery(force: Bool = false) async {
        guard !offline else { return }
        if trending.isEmpty || force { trending = (try? await Catalog.chartTracks(genreID: 0, limit: 15)) ?? trending }
        if releases.isEmpty || force { releases = (try? await Catalog.newReleases(limit: 15)) ?? releases }
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionView(_ kind: HomeSectionKind) -> some View {
        switch kind {
        case .summary: summary
        case .madeForYou: madeForYou
        case .newFromArtists: newFromArtists
        case .charts: charts
        case .recentlyPlayed: recentlyPlayed
        case .recentlyAdded: recentlyAdded
        case .topArtists: topArtists
        case .following: following
        case .onRepeat: onRepeat
        case .trending: trendingSection
        case .newReleases: newReleasesSection
        }
    }

    @ViewBuilder private var summary: some View {
        let recs = app.stats.records(.week)
        let total = app.stats.total(recs)
        if total > 60 {
            NavigationLink(value: Route.stats) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last 7 days").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(Fmt.listening(total)).font(.system(size: 28, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(app.stats.plays(recs)) plays")
                        if let top = app.stats.topArtists(recs, limit: 1).first { Text("Most played: \(top.artist.name)").lineLimit(1) }
                    }
                    .font(.footnote)
                }
                .padding(16)
                .background(look.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: look.radius(16), style: .continuous))
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal)
        }
    }

    @ViewBuilder private var madeForYou: some View {
        let autos = app.playlists.autos.filter { !$0.songs.isEmpty && (!offline || $0.songs.contains { app.library.isDownloaded($0.id) }) }
        if !autos.isEmpty {
            Shelf(title: "Made for you") {
                ForEach(autos) { p in
                    NavigationLink(value: Route.playlist(p.id)) {
                        VStack(alignment: .leading, spacing: 6) {
                            PlaylistTile(playlist: p, size: 140)
                            Text(subtitle(for: p)).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(width: 140, alignment: .leading)
                        }
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private func subtitle(for p: Playlist) -> String {
        let names = Array(NSOrderedSet(array: p.songs.map(\.artist.name))).compactMap { $0 as? String }.prefix(3)
        return names.isEmpty ? "\(p.songs.count) songs" : names.joined(separator: ", ")
    }

    @ViewBuilder private var newFromArtists: some View {
        if !offline, let fresh = app.playlists.autos.first(where: { if case .auto(let r) = $0.kind { return r.source == .newReleases } else { return false } }),
           !fresh.songs.isEmpty {
            let albums = uniqueAlbums(fresh.songs)
            if !albums.isEmpty {
                Shelf(title: "New from your artists") {
                    ForEach(albums) { album in
                        NavigationLink(value: Route.album(album)) { AlbumTile(album: album, badge: "NEW") }.buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    private func uniqueAlbums(_ songs: [Song]) -> [Album] {
        var seen = Set<Int>()
        return songs.compactMap { s in
            guard var a = s.album, seen.insert(a.id).inserted else { return nil }
            if a.artist == nil { a.artist = s.artist }
            return a
        }
    }

    @ViewBuilder private var charts: some View {
        if !offline {
            Shelf(title: "Charts", trailing: AnyView(
                NavigationLink(value: Route.browseCharts) {
                    Label("Add / remove", systemImage: "plus").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Surface.card(look), in: Capsule())
                }
            )) {
                ForEach(app.prefs.data.homeCharts) { c in
                    NavigationLink(value: Route.chart(c)) { ChartTile(source: c) }.buttonStyle(PressStyle())
                }
                NavigationLink(value: Route.browseCharts) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.title2)
                        Text("Browse charts").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 140, height: 140)
                    .overlay(RoundedRectangle(cornerRadius: look.radius(12)).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(.secondary))
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    @ViewBuilder private var recentlyPlayed: some View {
        let songs = app.stats.recentSongIDs(limit: 15).compactMap { app.library.entry($0)?.song }
        if !songs.isEmpty {
            Shelf(title: "Recently played") {
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    SongCard(song: s)
                }
            }
        }
    }

    @ViewBuilder private var recentlyAdded: some View {
        let songs = Array(app.library.songs.prefix(15))
        if !songs.isEmpty {
            Shelf(title: "Recently downloaded") {
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    SongCard(song: s)
                }
            }
        }
    }

    @ViewBuilder private var topArtists: some View {
        let top = app.stats.topArtists(app.stats.records(.month), limit: 12)
        if !top.isEmpty {
            Shelf(title: "Your top artists") {
                ForEach(top) { s in
                    NavigationLink(value: Route.artist(s.artist)) { ArtistCircle(artist: s.artist, caption: Fmt.listening(s.seconds)) }
                        .buttonStyle(PressStyle())
                }
            }
        }
    }

    @ViewBuilder private var following: some View {
        if !app.library.followed.isEmpty {
            Shelf(title: "Following") {
                ForEach(app.library.followed) { a in
                    NavigationLink(value: Route.artist(a)) { ArtistCircle(artist: a) }.buttonStyle(PressStyle())
                }
            }
        }
    }

    @ViewBuilder private var onRepeat: some View {
        let top = app.stats.topSongs(app.stats.records(.month), limit: 5).filter { app.library.isDownloaded($0.songID) }
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("On repeat").font(.title2.bold())
                ForEach(Array(top.enumerated()), id: \.element.id) { i, stat in
                    if let song = app.library.entry(stat.songID)?.song {
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                            song.artwork(44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).lineLimit(1)
                                Text("\(song.artist.name) · \(stat.plays) plays").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let songs = top.compactMap { app.library.entry($0.songID)?.song }
                            app.player.play(songs, startAt: i, context: "On repeat")
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder private var trendingSection: some View {
        if !offline && !trending.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trending now").font(.title2.bold()).padding(.bottom, 6)
                ForEach(trending.prefix(8)) { s in SongRow(song: s, queue: trending, context: "Trending now") }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder private var newReleasesSection: some View {
        if !offline && !releases.isEmpty {
            Shelf(title: "New releases") {
                ForEach(releases) { album in
                    NavigationLink(value: Route.album(album)) { AlbumTile(album: album) }.buttonStyle(PressStyle())
                }
            }
        }
    }
}

struct ChartTile: View {
    let source: ChartSource
    var size: CGFloat = 140
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Color(hex: source.colorHex)
                VStack(alignment: .leading, spacing: 0) {
                    Text(source.kind == .deezerGenre && source.ref != "0" ? "GENRE" : "TOP").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.8))
                    Text(source.name.replacingOccurrences(of: "Top ", with: "")).font(.title3.weight(.heavy)).foregroundStyle(.white).lineLimit(2)
                }
                .padding(10)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: look.radius(12), style: .continuous))
            Text(source.sourceLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size, alignment: .leading)
    }
}

struct ProfileAvatar: View {
    var size: CGFloat
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.prefs.data.hasAvatarPhoto, let img = UIImage(contentsOfFile: Paths.avatar.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(hex: app.prefs.data.avatarHex)
                    Text(app.prefs.initial).font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(.black.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
