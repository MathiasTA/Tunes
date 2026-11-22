import SwiftUI

struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable { case playlists = "Playlists", songs = "Songs", artists = "Artists"; var id: String { rawValue } }
    enum Sort: String, CaseIterable { case smart = "Pinned first", az = "A–Z", played = "Most played", added = "Recently added" }
    enum Filter: String, CaseIterable { case all = "All", mine = "By you", auto = "Auto", charts = "Charts", downloaded = "Downloaded" }

    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @AppStorage("libraryMode") private var mode: Mode = .playlists
    @AppStorage("librarySort") private var sort: Sort = .smart
    @State private var filter: Filter = .all
    @State private var text = ""
    @State private var showCreate = false

    var body: some View {
        List {
            Picker("Show", selection: $mode.animation(.easeInOut(duration: 0.2))) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            chips.listRowSeparator(.hidden).listRowBackground(Color.clear)

            if DownloadsBar.isVisible(app.library) {
                LibraryDownloadCard()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }

            switch mode {
            case .playlists: playlistRows
            case .songs: songRows
            case .artists: artistRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .themeBackground()
        .navigationTitle("Library")
        .searchable(text: $text, prompt: "Filter your library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.player.play(app.library.songs, context: "Your library", shuffled: true)
                } label: { Image(systemName: "shuffle") }
                .disabled(app.library.entries.isEmpty)
                .accessibilityLabel("Shuffle all")
            }
        }
        .confirmationDialog("Create / import playlist", isPresented: $showCreate, titleVisibility: .visible) {
            Button("New playlist") { app.sheet = .createPlaylist }
            Button("Import from Spotify") { app.sheet = .spotifyImport }
            Button("New auto playlist") { app.sheet = .autoPlaylist(nil) }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    let all = Sort.allCases
                    sort = all[(all.firstIndex(of: sort)! + 1) % all.count]
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Color.secondary.opacity(0.16), in: Capsule())
                }
                .buttonStyle(PressStyle())
                if mode == .playlists {
                    ForEach(Filter.allCases, id: \.self) { f in Chip(title: f.rawValue, selected: filter == f) { filter = f } }
                }
            }
        }
    }

    // MARK: Playlists

    private var playlists: [Playlist] {
        var list = app.playlists.playlists.filter { p in
            switch filter {
            case .all: true
            case .mine: p.isManual
            case .auto: p.isAuto
            case .charts: p.isChart
            case .downloaded: p.keepDownloaded
            }
        }
        if !text.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(text) } }
        switch sort {
        case .smart: list = list.filter(\.pinned) + list.filter { !$0.pinned }
        case .az: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .played: list.sort { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .added: list.sort { $0.createdAt > $1.createdAt }
        }
        return list
    }

    @ViewBuilder private var playlistRows: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.title2.weight(.semibold)).frame(width: 54, height: 54)
                    .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(8)))
                Text("Create / import playlist").font(.headline)
            }
            .foregroundStyle(look.accent)
        }
        .buttonStyle(.plain)
        if (filter == .all || filter == .mine) && (text.isEmpty || "liked songs".contains(text.lowercased())) {
            NavigationLink(value: Route.liked) {
                HStack(spacing: 12) {
                    LikedTile(size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Liked songs").font(.body.weight(.medium))
                        Text("\(app.library.liked.count) songs").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        ForEach(playlists) { p in
            NavigationLink(value: Route.playlist(p.id)) { PlaylistRow(playlist: p) }
                .swipeActions(edge: .leading) {
                    Button { app.playlists.togglePin(p.id) } label: { Label(p.pinned ? "Unpin" : "Pin", systemImage: p.pinned ? "pin.slash" : "pin") }.tint(.orange)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { app.playlists.delete(p.id) } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu {
                    Button { app.playlists.togglePin(p.id) } label: { Label(p.pinned ? "Unpin" : "Pin to top", systemImage: "pin") }
                    Button(role: .destructive) { app.playlists.delete(p.id) } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    // MARK: Songs

    private var songs: [Song] {
        var list = app.library.entries
        if !text.isEmpty {
            list = list.filter { $0.song.title.localizedCaseInsensitiveContains(text) || $0.song.artistLine.localizedCaseInsensitiveContains(text)
                || ($0.song.album?.title.localizedCaseInsensitiveContains(text) ?? false) }
        }
        switch sort {
        case .az: list.sort { $0.song.title.localizedCaseInsensitiveCompare($1.song.title) == .orderedAscending }
        case .played: list.sort { app.stats.playCount(forSong: $0.id) > app.stats.playCount(forSong: $1.id) }
        case .smart, .added: list.sort { $0.addedAt > $1.addedAt }
        }
        return list.map(\.song)
    }

    @ViewBuilder private var songRows: some View {
        Button { app.sheet = .importFiles } label: {
            Label("Import files from phone", systemImage: "folder.badge.plus").font(.headline).foregroundStyle(look.accent)
        }
        .buttonStyle(.plain)
        let list = songs
        ForEach(list) { s in
            SongRow(song: s, queue: list, context: "Your library", likeOnTrailingSwipe: false)
                .swipeActions {
                    Button(role: .destructive) {
                        app.player.removeSongs([s.id])
                        app.library.delete([s.id])
                    } label: { Label("Remove", systemImage: "trash") }
                }
        }
        if list.isEmpty {
            Text(text.isEmpty ? "Downloaded and imported songs show up here, and play offline." : "No matches.")
                .font(.footnote).foregroundStyle(.secondary).listRowSeparator(.hidden)
        }
    }

    // MARK: Artists

    @ViewBuilder private var artistRows: some View {
        let list = app.library.artists.filter { text.isEmpty || $0.artist.name.localizedCaseInsensitiveContains(text) }
        ForEach(list) { e in
            NavigationLink(value: Route.artist(e.artist)) {
                HStack(spacing: 12) {
                    e.artist.picture(52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.artist.name)
                        Text("\(e.count) song\(e.count == 1 ? "" : "s")\(e.imported > 0 ? " (\(e.imported) imported)" : "") · \(Fmt.listening(app.stats.seconds(forArtist: e.artist.id))) listened")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 12) {
            PlaylistTile(playlist: playlist, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if playlist.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(look.accent) }
                    Text(playlist.name).font(.body.weight(.medium)).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let b = playlist.badge {
                        Text(b).font(.system(size: 9, weight: .heavy)).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if playlist.keepDownloaded {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(look.accent).font(.subheadline)
            }
        }
    }

    private var meta: String {
        if app.playlists.refreshing.contains(playlist.id) { return "Updating…" }
        let have = playlist.songs.filter { app.library.isDownloaded($0.id) }.count
        if app.prefs.data.offline { return "\(have) of \(playlist.songs.count) downloaded" }
        if !playlist.isManual, let r = playlist.refreshedAt {
            return "\(playlist.songs.count) songs · updated \(r.formatted(.relative(presentation: .named)))"
        }
        return "\(playlist.songs.count) songs"
    }
}

struct LikedSongsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        let songs = app.library.liked.map(\.song)
        List {
            VStack(spacing: 12) {
                LikedTile(size: 150)
                Text("Liked songs").font(.title2.bold())
                Text("\(songs.count) songs").foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    PillButton(title: "Play", icon: "play.fill", prominent: true) { app.player.play(songs, context: "Liked songs", shuffled: false) }
                    PillButton(title: "Shuffle", icon: "shuffle") { app.player.play(songs, context: "Liked songs", shuffled: true) }
                }
                .disabled(songs.isEmpty)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            ForEach(songs) { SongRow(song: $0, queue: songs, context: "Liked songs") }
            if songs.isEmpty {
                Text("Tap the heart on any song to add it here.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .themeBackground()
        .navigationTitle("Liked songs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CreatePlaylistView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Playlist name", text: $name).font(.title3)
            }
            .themedForm()
            .navigationTitle("New playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let p = app.playlists.create(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "My playlist" : name)
                        app.navigate(.playlist(p.id))
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct AddToPlaylistView: View {
    let songs: [Song]
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New playlist", text: $newName)
                        Button("Create") {
                            let p = app.playlists.create(name: newName.isEmpty ? "My playlist" : newName, songs: songs)
                            if p.keepDownloaded { app.library.downloadAll(songs) }
                            app.show("Added to \(p.name)")
                            dismiss()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
.themedRow()
                Section {
                    Button {
                        for s in songs where !app.library.isLiked(s.id) { app.library.toggleLike(s) }
                        app.show("Added to Liked songs")
                        dismiss()
                    } label: {
                        HStack(spacing: 12) { LikedTile(size: 44); Text("Liked songs").foregroundStyle(.primary) }
                    }
                    ForEach(app.playlists.manual) { p in
                        Button {
                            app.playlists.add(songs, to: p.id)
                            app.show("Added to \(p.name)")
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                PlaylistTile(playlist: p, size: 44)
                                VStack(alignment: .leading) {
                                    Text(p.name).foregroundStyle(.primary)
                                    Text("\(p.songs.count) songs").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
.themedRow()
            }
            .themedForm()
            .navigationTitle(songs.count == 1 ? "Add to playlist" : "Add \(songs.count) songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
