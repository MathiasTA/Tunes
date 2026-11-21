import SwiftUI

/// Remembers recent searches (shared by every search field in the app).
enum SearchHistory {
    static let key = "recentSearches"
    static func remember(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let old = (UserDefaults.standard.string(forKey: key) ?? "").split(separator: "\n").map(String.init)
        let list = [t] + old.filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        UserDefaults.standard.set(list.prefix(8).joined(separator: "\n"), forKey: key)
    }
}

/// Search pushed as its own page (kept for links into search from elsewhere).
struct SearchView: View {
    @State private var query = ""
    @Environment(AppModel.self) private var app

    var body: some View {
        let offline = app.prefs.data.offline || !app.network.isOnline
        SearchResultsList(query: $query)
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: offline ? "Your downloads" : "Artists, songs, albums")
            .onSubmit(of: .search) { SearchHistory.remember(query) }
    }
}

/// The results part of search: recent searches, library matches and catalog results.
struct SearchResultsList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @Binding var query: String
    @State private var results = Catalog.SearchResults()
    @State private var loading = false
    @State private var error: String?
    @AppStorage(SearchHistory.key) private var recentData = ""

    private var offline: Bool { app.prefs.data.offline || !app.network.isOnline }
    private var recents: [String] { recentData.split(separator: "\n").map(String.init) }

    private var localSongs: [Song] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return app.library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.artistLine.localizedCaseInsensitiveContains(q)
                || ($0.album?.title.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        List {
            if offline {
                OfflineBanner().listRowSeparator(.hidden)
            }
            if query.isEmpty && !recents.isEmpty {
                Section {
                    ForEach(recents, id: \.self) { r in
                        Button { query = r } label: {
                            Label(r, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                        }
                    }
                    Button("Clear recent searches", role: .destructive) { recentData = "" }.font(.footnote)
                } header: { SectionLabel(text: "Recent") }
            }
            if !localSongs.isEmpty {
                Section {
                    ForEach(localSongs.prefix(offline ? 50 : 4)) { SongRow(song: $0, queue: localSongs, context: "Your library") }
                } header: { SectionLabel(text: "In your library") }
            }
            if !offline {
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if !results.artists.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(results.artists) { a in
                                    NavigationLink(value: Route.artist(a)) {
                                        ArtistCircle(artist: a, size: 84, caption: a.fans.map { "\(Fmt.count($0)) fans" })
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: { SectionLabel(text: "Artists") }
                }
                if !results.songs.isEmpty {
                    Section {
                        ForEach(results.songs) { SongRow(song: $0, queue: results.songs, context: "Search") }
                    } header: { SectionLabel(text: "Songs") }
                }
                if !results.albums.isEmpty {
                    Section {
                        ForEach(results.albums) { a in NavigationLink(value: Route.album(a)) { AlbumRow(album: a) } }
                    } header: { SectionLabel(text: "Albums") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Surface.background(look))
        .overlay {
            if loading && results.isEmpty { ProgressView() }
            else if query.isEmpty && recents.isEmpty {
                ContentUnavailableView(offline ? "Search your downloads" : "Find music", systemImage: "magnifyingglass",
                                       description: Text(offline ? "You're offline, so only downloaded songs show up." : "Tap a song to hear a preview, or the arrow to download it."))
            }
        }
        .task(id: query) { await search() }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !offline else { results = .init(); error = nil; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            let found = try await Catalog.search(q)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { results = found }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

}
