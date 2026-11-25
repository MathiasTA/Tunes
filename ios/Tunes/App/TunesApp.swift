import SwiftUI

@main
struct TunesApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var app = AppModel.shared

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 400 << 20)
    }

    var body: some Scene {
        WindowGroup {
            // Re-checked every minute, so Horizon follows the time of day.
            TimelineView(.everyMinute) { ctx in
                let look = app.prefs.look(at: ctx.date, cover: app.coverColors)
                RootView()
                    .environment(app)
                    .environment(\.look, look)
                    .tint(look.accent)
                    .toggleStyle(TunesToggleStyle())
                    .appFont(app.prefs.data.font)
                    .preferredColorScheme(app.prefs.colorScheme(for: look))
                    .dynamicTypeSize(app.prefs.data.textSize.dynamicType)
                    .transaction { t in if !app.prefs.data.animations { t.animation = nil } }
            }
            .onAppear { app.onLaunch() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.onForeground()
            case .background: app.onBackground()
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        @Bindable var app = app
        ZStack {
            TabView(selection: Binding(get: { app.tab }, set: { new in
                if new == app.tab { app.reselect(new) } else { app.tab = new }
            })) {
                NavigationStack(path: $app.homePath) { HomeView().miniPlayerSpace().withRoutes() }
                    .miniPlayerInset()
                    .solidTabBar(look)
                    .tabItem { tabLabel("Home", "house.fill") }
                    .tag(AppModel.Tab.home)
                NavigationStack(path: $app.libraryPath) { LibraryView().miniPlayerSpace().withRoutes() }
                    .miniPlayerInset()
                    .solidTabBar(look)
                    .tabItem { tabLabel("Library", "square.stack.fill") }
                    .tag(AppModel.Tab.library)
                NavigationStack(path: $app.statsPath) { StatsView().miniPlayerSpace().withRoutes() }
                    .miniPlayerInset()
                    .solidTabBar(look)
                    .tabItem { tabLabel("Stats", "chart.bar.fill") }
                    .tag(AppModel.Tab.stats)
                NavigationStack(path: $app.gamesPath) { GamesHubView().miniPlayerSpace().withRoutes() }
                    .miniPlayerInset()
                    .solidTabBar(look)
                    .tabItem { tabLabel("Games", "gamecontroller.fill") }
                    .badge(app.dailiesLeft ? Text("") : nil)
                    .tag(AppModel.Tab.games)
            }

            if app.showPlayer {
                FullPlayerView()
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }

            if let toast = app.toast {
                VStack {
                    Toast(text: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(3)
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation(.easeOut) { app.toast = nil }
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: app.showPlayer)
        .animation(.spring(duration: 0.35), value: app.toast)
        .sheet(item: $app.sheet) { sheet in
            sheetView(sheet)
                .environment(app)
                .environment(\.look, look)
                .tint(look.accent)
                .toggleStyle(TunesToggleStyle())
                .appFont(app.prefs.data.font)
                // Sheets keep their own light/dark mode, so they follow theme changes right away (e.g. in Settings).
                .preferredColorScheme(app.prefs.colorScheme(for: look))
        }
        .fullScreenCover(isPresented: Binding(get: { app.needsWelcome }, set: { _ in })) {
            WelcomeView().environment(app).environment(\.look, look).tint(look.accent)
                .preferredColorScheme(app.prefs.colorScheme(for: look))
        }
        .fullScreenCover(isPresented: $app.showWrapped) {
            WrappedView().environment(app).environment(\.look, look).tint(look.accent).toggleStyle(TunesToggleStyle())
                .preferredColorScheme(app.prefs.colorScheme(for: look))
        }
        .onChange(of: app.player.message) { _, msg in
            guard let msg else { return }
            withAnimation { app.toast = msg }
            app.player.message = nil
        }
        .onChange(of: app.network.isWiFi) { _, _ in app.library.pump() }
        .onChange(of: app.network.isOnline) { _, online in
            app.library.pump()
            if online { Task { await app.playlists.refreshAll() } }
        }
        .onChange(of: app.prefs.data.offline) { _, _ in app.library.pump() }
        .onChange(of: app.prefs.data.downloadWifiOnly) { _, _ in app.library.pump() }
        .onChange(of: app.prefs.data.homeCharts) { _, charts in app.playlists.syncHomeCharts(charts) }
    }

    @ViewBuilder
    private func tabLabel(_ title: String, _ icon: String) -> some View {
        if app.prefs.data.tabLabels { Label(title, systemImage: icon) } else { Image(systemName: icon) }
    }

    @ViewBuilder
    private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .songMenu(let song, let pid): SongMenuView(song: song, playlistID: pid)
        case .addToPlaylist(let songs): AddToPlaylistView(songs: songs)
        case .share(let song): ShareSongView(song: song)
        case .edit(let id): EditSongView(songID: id)
        case .queue: QueueView()
        case .lyrics: LyricsView()
        case .output: OutputView()
        case .video(let song): VideoPlayerView(song: song)
        case .profile: ProfileView()
        case .importFiles: ImportFilesView()
        case .importYouTube: ImportYouTubeView()
        case .spotifyImport: SpotifyImportView()
        case .createPlaylist: CreatePlaylistView()
        case .autoPlaylist(let id): AutoPlaylistEditor(playlistID: id)
        case .settings: NavigationStack { SettingsView().withRoutes() }
        case .downloads: DownloadsView()
        case .fixDownload(let song):
            NavigationStack {
                FixDownloadView(song: song)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton() } }
            }
        }
    }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
            switch route {
            case .search: SearchView()
            case .artist(let a): ArtistView(artist: a)
            case .artistMore(let a): ArtistMoreView(artist: a)
            case .discography(let a): DiscographyView(artist: a)
            case .badges: BadgesView()
            case .album(let a): AlbumView(album: a)
            case .playlist(let id): PlaylistView(playlistID: id)
            case .liked: LikedSongsView()
            case .chart(let c): ChartRouteView(source: c)
            case .browseCharts: BrowseChartsView()
            case .stats: StatsView()
            case .settings: SettingsView()
            case .songStats(let id): SongStatsView(songID: id)
            case .yourCharts: YourChartsView()
            case .songJourney(let id): SongJourneyView(songID: id)
            case .recaps: RecapsView()
            case .games: GamesHubView()
            }
            }
            .miniPlayerSpace()
        }
    }

    /// Keeps the tab bar solid. iOS makes it see-through whenever a list is scrolled to its end,
    /// which made the Home / Library / Stats buttons hard to read.
    func solidTabBar(_ look: Look) -> some View {
        toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(Surface.bar(look), for: .tabBar)
    }

    /// Floats the mini player above the tab bar. Each screen makes room for it with `miniPlayerSpace()`.
    func miniPlayerInset() -> some View {
        overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                DownloadsBar()
                MiniPlayer()
            }
        }
    }

    /// Adds empty space under a screen's content while the mini player is showing,
    /// so the last song in a list can scroll above it instead of hiding behind it.
    func miniPlayerSpace() -> some View {
        modifier(MiniPlayerSpace())
    }
}

private struct MiniPlayerSpace: ViewModifier {
    @Environment(AppModel.self) private var app
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: (app.player.currentSong != nil ? app.prefs.data.miniPlayerStyle.height : 0)
                + (DownloadsBar.isVisible(app.library) ? 58 : 0))
        }
    }
}
