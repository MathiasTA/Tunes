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
                    sectionView(section)
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
        if trending.isEmpty || force { trending = (try? await Catalog.chartTracks(genreID: 0, limit: 20)) ?? trending }
        if releases.isEmpty || force { releases = (try? await Catalog.newReleases(limit: 20)) ?? releases }
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        if section.kind == .summary {
            summary
        } else {
            let items = self.items(for: section.kind)
            if !items.isEmpty {
                HomeSectionView(title: section.kind.title, trailing: trailing(for: section.kind),
                                layout: section.effectiveLayout, count: section.effectiveCount, items: items)
            }
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

    private func trailing(for kind: HomeSectionKind) -> AnyView? {
        guard kind == .charts else { return nil }
        return AnyView(
            NavigationLink(value: Route.browseCharts) {
                Label("Add / remove", systemImage: "plus").font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Surface.card(look), in: Capsule())
            }
        )
    }

    /// What each section shows, as generic items the chosen layout can draw.
    private func items(for kind: HomeSectionKind) -> [HomeItem] {
        let lib = app.library, stats = app.stats
        func song(_ s: Song, _ sub: String? = nil) -> HomeItem {
            HomeItem(id: "s\(s.id)", title: s.title, subtitle: sub ?? s.artistLine, art: .song(lib.resolved(s)))
        }
        switch kind {
        case .summary:
            return []
        case .madeForYou:
            return app.playlists.autos
                .filter { !$0.songs.isEmpty && (!offline || $0.songs.contains { lib.isDownloaded($0.id) }) }
                .map { HomeItem(id: "p\($0.id)", title: $0.name, subtitle: subtitle(for: $0), art: .playlist($0)) }
        case .newFromArtists:
            guard !offline, let fresh = app.playlists.autos.first(where: {
                if case .auto(let r) = $0.kind { return r.source == .newReleases } else { return false }
            }) else { return [] }
            return uniqueAlbums(fresh.songs).map {
                HomeItem(id: "a\($0.id)", title: $0.title, subtitle: $0.artist?.name, art: .album($0), badge: "NEW")
            }
        case .charts:
            guard !offline else { return [] }
            return app.prefs.data.homeCharts.map { HomeItem(id: "c\($0.id)", title: $0.name, subtitle: $0.sourceLabel, art: .chart($0)) }
        case .recentlyPlayed:
            return stats.recentSongIDs(limit: 20).compactMap { lib.entry($0)?.song }.map { song($0) }
        case .recentlyAdded:
            return lib.songs.prefix(20).map { song($0) }
        case .topArtists:
            return stats.topArtists(stats.records(.month), limit: 20).map {
                HomeItem(id: "ar\($0.artist.id)", title: $0.artist.name, subtitle: Fmt.listening($0.seconds), art: .artist($0.artist))
            }
        case .following:
            return lib.followed.map { HomeItem(id: "ar\($0.id)", title: $0.name, subtitle: nil, art: .artist($0)) }
        case .onRepeat:
            return stats.topSongs(stats.records(.month), limit: 20)
                .compactMap { st in lib.entry(st.songID).map { song($0.song, "\($0.song.artist.name) · \(st.plays) plays") } }
        case .trending:
            return offline ? [] : trending.map { song($0) }
        case .newReleases:
            return offline ? [] : releases.map { HomeItem(id: "a\($0.id)", title: $0.title, subtitle: $0.artist?.name, art: .album($0)) }
        case .yourPlaylists:
            // Liked songs first, then your own playlists (pinned first, then most recently played).
            var list: [HomeItem] = []
            if !lib.liked.isEmpty {
                list.append(HomeItem(id: "liked", title: "Liked songs", subtitle: "\(lib.liked.count) songs", art: .liked))
            }
            let own = app.playlists.manual.sorted {
                if $0.pinned != $1.pinned { return $0.pinned }
                return ($0.lastPlayedAt ?? $0.createdAt) > ($1.lastPlayedAt ?? $1.createdAt)
            }
            list += own.map { HomeItem(id: "p\($0.id)", title: $0.name, subtitle: "\($0.songs.count) songs", art: .playlist($0)) }
            return list
        case .favoriteAlbums:
            return favoriteAlbums()
        }
    }

    /// Albums you've listened to most in the last 30 days (counting every song from them).
    private func favoriteAlbums() -> [HomeItem] {
        var seconds: [Int: Double] = [:]
        var albums: [Int: Album] = [:]
        for r in app.stats.records(.month) {
            guard let song = app.library.entry(r.songID)?.song, var album = song.album, album.id > 0 else { continue }
            if album.artist == nil { album.artist = song.artist }
            seconds[album.id, default: 0] += r.seconds
            albums[album.id] = album
        }
        return seconds.filter { $0.value >= 120 }
            .sorted { $0.value > $1.value }
            .compactMap { id, secs in
                albums[id].map {
                    HomeItem(id: "fa\(id)", title: $0.title,
                             subtitle: [$0.artist?.name, Fmt.listening(secs)].compactMap { $0 }.joined(separator: " · "),
                             art: .album($0))
                }
            }
    }

    private func subtitle(for p: Playlist) -> String {
        let names = Array(NSOrderedSet(array: p.songs.map(\.artist.name))).compactMap { $0 as? String }.prefix(3)
        return names.isEmpty ? "\(p.songs.count) songs" : names.joined(separator: ", ")
    }

    private func uniqueAlbums(_ songs: [Song]) -> [Album] {
        var seen = Set<Int>()
        return songs.compactMap { s in
            guard var a = s.album, seen.insert(a.id).inserted else { return nil }
            if a.artist == nil { a.artist = s.artist }
            return a
        }
    }
}

struct ChartTile: View {
    let source: ChartSource
    var size: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChartArt(source: source, size: size)
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
