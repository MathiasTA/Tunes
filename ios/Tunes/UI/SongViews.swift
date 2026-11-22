import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Song menu

struct SongMenuView: View {
    let song: Song
    let playlistID: UUID?
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss

    private var shown: Song { app.library.resolved(song) }
    private var downloaded: Bool { app.library.isDownloaded(song.id) }
    private var playlist: Playlist? { playlistID.flatMap { app.playlists.playlist($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        shown.artwork(60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(shown.title).font(.headline).lineLimit(2)
                            Text(shown.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            if let e = app.library.entry(song.id) {
                                Text(e.needsReview ? "Check this one: the match was a guess" : "Downloaded · \(Fmt.listening(app.stats.seconds(forSong: song.id))) listened")
                                    .font(.caption).foregroundStyle(e.needsReview ? .orange : .secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
.themedRow()
                Section {
                    if downloaded {
                        row("Play", "play.fill") { app.player.play([shown], context: shown.title); dismiss() }
                    } else if shown.previewURL != nil && !app.prefs.data.offline {
                        let previewing = app.player.previewingID == song.id
                        row(previewing ? "Stop preview" : "Play preview", previewing ? "stop.fill" : "play.circle") { app.player.togglePreview(shown) }
                    }
                    let liked = app.library.isLiked(song.id)
                    row(liked ? "Liked" : "Like", liked ? "heart.fill" : "heart", tint: liked ? look.accent : nil) {
                        app.library.toggleLike(shown)
                    }
                    row("Add to playlist", "plus.square.on.square") { app.sheet = .addToPlaylist([shown]) }
                    if downloaded {
                        row("Play next", "text.line.first.and.arrowtriangle.forward") { app.player.playNext(shown); app.show("Plays next"); dismiss() }
                        row("Add to queue", "text.badge.plus") { app.player.addToQueue(shown); app.show("Added to queue"); dismiss() }
                    } else if !song.isLocalOnly {
                        row("Download", "arrow.down.circle") { app.library.download(shown); dismiss() }
                        row("Add to queue", "text.badge.plus") { app.player.addToQueue(shown); app.show("Downloading, then it joins your queue"); dismiss() }
                    }
                    if let p = playlist, p.isManual, p.songs.contains(where: { $0.id == song.id }) {
                        row("Remove from \(p.name)", "minus.circle") { app.playlists.remove(songIDs: [song.id], from: p.id); dismiss() }
                    }
                }
.themedRow()
                Section {
                    ForEach(shown.allArtists.filter { $0.id > 0 }) { a in
                        row(shown.allArtists.count > 1 ? "Go to \(a.name)" : "Go to artist", "person") { app.navigate(.artist(a)) }
                    }
                    if let album = shown.album, album.id > 0 {
                        row("Go to album", "opticaldisc") { app.navigate(.album(album)) }
                    }
                    if downloaded {
                        row("Song stats", "chart.bar") { app.navigate(.songStats(song.id)) }
                    }
                    row("Share", "square.and.arrow.up") { app.sheet = .share(shown) }
                    if !app.prefs.data.offline {
                        row("Watch video", "play.rectangle") { app.sheet = .video(shown) }
                    }
                }
.themedRow()
                if downloaded {
                    Section {
                        row("Edit song, cover & source", "pencil") { app.sheet = .edit(song.id) }
                        row("Remove download", "trash", tint: .red) {
                            app.player.removeSongs([song.id])
                            app.library.delete([song.id])
                            app.show("Download removed")
                            dismiss()
                        }
                    }
.themedRow()
                }
            }
            .themedForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ title: String, _ icon: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title).foregroundStyle(tint ?? .primary) } icon: { Image(systemName: icon).foregroundStyle(tint ?? look.accent) }
        }
    }
}

// MARK: - Share

struct ShareSongView: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @Environment(AppModel.self) private var app

    private var query: String { "\(song.artist.name) \(song.title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "" }

    private var universal: URL? {
        guard song.id > 0 else { return nil }
        return URL(string: "https://song.link/https://www.deezer.com/track/\(song.id)")
    }

    private var links: [(String, String, URL)] {
        var out: [(String, String, URL)] = []
        if song.id > 0, let u = URL(string: "https://www.deezer.com/track/\(song.id)") { out.append(("Deezer", "waveform", u)) }
        if let u = URL(string: "https://open.spotify.com/search/\(query)") { out.append(("Spotify", "dot.radiowaves.left.and.right", u)) }
        if let u = URL(string: "https://music.apple.com/search?term=\(query)") { out.append(("Apple Music", "music.note", u)) }
        if let u = URL(string: "https://music.youtube.com/search?q=\(query)") { out.append(("YouTube Music", "play.circle", u)) }
        if let id = app.library.entry(song.id)?.youTubeID, let u = URL(string: "https://youtu.be/\(id)") { out.append(("YouTube video", "play.rectangle", u)) }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        song.artwork(64)
                        VStack(alignment: .leading) {
                            Text(song.title).font(.headline)
                            Text(song.artistLine).foregroundStyle(.secondary)
                        }
                    }
                }
.themedRow()
                if let universal {
                    Section {
                        ShareLink(item: universal, subject: Text(song.title), message: Text("\(song.title) by \(song.artistLine)")) {
                            Label("Share link that works in every app", systemImage: "link")
                        }
                        Button {
                            UIPasteboard.general.url = universal
                            app.show("Link copied")
                        } label: { Label("Copy link", systemImage: "doc.on.doc") }
                    } footer: {
                        Text("Opens a page where your friend picks Spotify, Apple Music, YouTube, Deezer or whatever they use.")
                    }
.themedRow()
                }
                Section("Link for a specific app") {
                    ForEach(links, id: \.0) { item in
                        ShareLink(item: item.2) { Label(item.0, systemImage: item.1) }
                    }
                }
.themedRow()
            }
            .themedForm()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Edit song

struct EditSongView: View {
    let songID: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look

    @State private var title = ""
    @State private var albumTitle = ""
    @State private var artists: [Artist] = []
    @State private var loaded = false
    @State private var photo: PhotosPickerItem?
    @State private var coverLink = ""
    @State private var showCoverSearch = false
    @State private var showLinkArtists = false
    @State private var alternatives: [VideoCandidate] = []
    @State private var searching = false
    @State private var videoLink = ""
    @State private var pendingVideo: VideoCandidate?
    @State private var showFilePicker = false
    @State private var working = false
    @State private var error: String?
    @State private var artVersion = 0

    var body: some View {
        NavigationStack {
            if let e = app.library.entry(songID) {
                form(e)
            } else {
                ContentUnavailableView("Song removed", systemImage: "music.note")
            }
        }
    }

    private func form(_ e: LibraryEntry) -> some View {
        Form {
            if e.needsReview {
                Section {
                    Label("Tunes wasn't sure it found the right upload. Have a listen, then pick another version below if it's wrong.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.subheadline)
                    Button("It's the right song") { app.library.update(songID) { $0.needsReview = false } }
                }
.themedRow()
            }
            Section {
                HStack(spacing: 16) {
                    e.song.artwork(96).id(artVersion)
                    VStack(alignment: .leading, spacing: 10) {
                        PhotosPicker(selection: $photo, matching: .images) { Label("Choose photo", systemImage: "photo") }
                        Button { showCoverSearch = true } label: { Label("Find cover", systemImage: "magnifyingglass") }
                            .disabled(!app.network.isOnline)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                HStack {
                    TextField("Or paste an image link", text: $coverLink).textInputAutocapitalization(.never).keyboardType(.URL)
                    Button("Use") {
                        guard let u = URL(string: coverLink.trimmingCharacters(in: .whitespaces)), u.scheme?.hasPrefix("http") == true else { error = "That isn't an image link."; return }
                        Task { await app.library.setArtwork(songID, url: u); artVersion += 1; coverLink = "" }
                    }
                    .disabled(coverLink.isEmpty)
                }
            } header: { Text("Cover") }
.themedRow()

            Section("Info") {
                TextField("Title", text: $title)
                TextField("Album", text: $albumTitle)
            }
.themedRow()

            Section {
                ForEach(Array(artists.enumerated()), id: \.element.id) { i, a in
                    HStack {
                        a.picture(32)
                        Text(a.name)
                        Spacer()
                        Text(i == 0 ? "Main" : "Feature").font(.caption).foregroundStyle(.secondary)
                        if a.id < 0 { Image(systemName: "link.badge.plus").foregroundStyle(.orange) }
                    }
                }
                .onDelete { if artists.count > 1 { artists.remove(atOffsets: $0) } }
                .onMove { artists.move(fromOffsets: $0, toOffset: $1) }
                Button { showLinkArtists = true } label: { Label("Link artists", systemImage: "person.badge.plus") }
                    .disabled(!app.network.isOnline)
            } header: { Text("Artists") } footer: {
                Text("Linked artists get the listening time in your stats. The first one is the main artist.")
            }
.themedRow()

            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Now playing from").font(.caption).foregroundStyle(.secondary)
                    Text(e.sourceDescription).font(.subheadline)
                }
                if case .downloading(let p) = app.library.states[songID] {
                    ProgressView(value: p) { Text("Downloading new version…").font(.caption) }
                }
                Button { Task { await findAlternatives(e) } } label: {
                    HStack { Label("Find other versions", systemImage: "magnifyingglass"); if searching { Spacer(); ProgressView() } }
                }
                .disabled(searching || !app.network.isOnline || app.prefs.data.offline)
                ForEach(alternatives) { v in
                    Button { pendingVideo = v } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.title).foregroundStyle(.primary).lineLimit(2).font(.subheadline)
                                Text(v.channel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.time(v.duration)).font(.caption.monospacedDigit())
                                .foregroundStyle(lengthColor(v.duration, e.song.duration))
                            if v.id == e.youTubeID { Image(systemName: "checkmark").foregroundStyle(look.accent) }
                        }
                    }
                }
                HStack {
                    TextField("Paste a YouTube link", text: $videoLink).textInputAutocapitalization(.never).keyboardType(.URL)
                    Button("Use") {
                        guard let id = YouTubeSearch.videoID(from: videoLink) else { error = YouTubeError.badLink.localizedDescription; return }
                        pendingVideo = VideoCandidate(id: id, title: "Pasted link", channel: "youtu.be/\(id)", duration: nil)
                    }
                    .disabled(videoLink.isEmpty)
                }
                Button { showFilePicker = true } label: { Label("Replace with a file", systemImage: "folder") }
            } header: { Text("Audio source") } footer: {
                Text("Lengths in green match the real song. Picking one downloads it again; your stats, likes and playlists stay.")
            }
.themedRow()

            Section("Sound") {
                NavigationLink { TrimView(songID: songID) } label: {
                    HStack {
                        Label("Trim & fades", systemImage: "scissors")
                        Spacer()
                        if e.trimStart > 0 || e.trimEnd != nil || e.fadeIn > 0 || e.fadeOut > 0 {
                            Text("Edited").foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Reset trim, fades and lyrics timing") {
                    app.library.update(songID) { $0.trimStart = 0; $0.trimEnd = nil; $0.fadeIn = 0; $0.fadeOut = 0; $0.lyricsOffset = 0 }
                    app.player.reloadIfCurrent(songID)
                }
            }
.themedRow()

            Section {
                Button("Remove download", role: .destructive) {
                    app.player.removeSongs([songID])
                    app.library.delete([songID])
                    dismiss()
                }
            }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Edit song")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() }.bold() }
        }
        .disabled(working)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            title = e.song.title
            albumTitle = e.song.album?.title ?? ""
            artists = e.song.allArtists
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                   let jpg = img.preparingThumbnail(of: CGSize(width: 1000, height: 1000 * img.size.height / max(img.size.width, 1)))?.jpegData(compressionQuality: 0.85) ?? img.jpegData(compressionQuality: 0.85) {
                    app.library.setArtwork(songID, data: jpg)
                    artVersion += 1
                }
                photo = nil
            }
        }
        .sheet(isPresented: $showCoverSearch) {
            CoverSearchView(query: "\(artists.first?.name ?? "") \(albumTitle.isEmpty ? title : albumTitle)") { url in
                Task { await app.library.setArtwork(songID, url: url); artVersion += 1 }
            }
        }
        .sheet(isPresented: $showLinkArtists) {
            LinkArtistView(initial: artists.filter { $0.id > 0 }, suggestion: artists.first?.name ?? "") { picked in
                if !picked.isEmpty { artists = picked }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            do {
                try app.library.replaceAudio(songID, with: url)
                app.player.reloadIfCurrent(songID)
                app.show("Audio replaced")
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("Download this version?", isPresented: Binding(get: { pendingVideo != nil }, set: { if !$0 { pendingVideo = nil } }), titleVisibility: .visible) {
            Button("Download and replace") {
                guard let v = pendingVideo else { return }
                pendingVideo = nil
                Task {
                    do {
                        try await app.library.redownload(songID, video: v)
                        app.player.reloadIfCurrent(songID)
                        app.show("New version downloaded")
                        videoLink = ""
                    } catch { self.error = error.localizedDescription }
                }
            }
        } message: { Text(pendingVideo?.title ?? "") }
        .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func lengthColor(_ d: Double?, _ real: Double) -> Color {
        guard let d, real > 0 else { return .secondary }
        return abs(d - real) <= 4 ? .green : (abs(d - real) <= 15 ? .orange : .secondary)
    }

    private func findAlternatives(_ e: LibraryEntry) async {
        searching = true
        defer { searching = false }
        do {
            let m = try await Matcher.match(e.song)
            var list = [m.best] + m.alternatives
            var seen = Set<String>()
            list = list.filter { seen.insert($0.id).inserted }
            alternatives = Array(list.prefix(8))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let al = albumTitle.trimmingCharacters(in: .whitespaces)
        let arts = artists
        app.library.update(songID) { e in
            if !t.isEmpty { e.song.title = t }
            if let main = arts.first {
                e.song.artist = main
                e.song.featured = Array(arts.dropFirst())
            }
            if al.isEmpty {
                e.song.album = nil
            } else if var album = e.song.album {
                if album.title != al { album.title = al }
                e.song.album = album
            } else {
                e.song.album = Album(id: -abs(e.song.id), title: al, coverURL: nil, artist: arts.first)
            }
        }
        // Keep playlist copies in sync so names show the same everywhere.
        if let updated = app.library.entry(songID)?.song {
            for p in app.playlists.playlists where p.songs.contains(where: { $0.id == songID }) {
                app.playlists.update(p.id) { pl in
                    if let i = pl.songs.firstIndex(where: { $0.id == songID }) { pl.songs[i] = updated }
                }
            }
        }
    }
}

struct CoverSearchView: View {
    let query: String
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var albums: [Album] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                    ForEach(albums) { a in
                        Button {
                            if let u = a.coverURL { onPick(u); dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                a.cover(104)
                                Text(a.title).font(.caption).lineLimit(1).foregroundStyle(.primary)
                                Text(a.artist?.name ?? "").font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding()
                if loading { ProgressView() }
                if !loading && albums.isEmpty { Text("No covers found.").foregroundStyle(.secondary).padding() }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Find cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { text = query; await search() }
        }
    }

    private func search() async {
        loading = true
        albums = (try? await Catalog.searchAlbums(text, limit: 24)) ?? []
        loading = false
    }
}

// MARK: - Link artist

struct LinkArtistView: View {
    let initial: [Artist]
    let suggestion: String
    let onDone: ([Artist]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @State private var selected: [Artist] = []
    @State private var query = ""
    @State private var results: [Artist] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if !selected.isEmpty {
                    Section {
                        ForEach(Array(selected.enumerated()), id: \.element.id) { i, a in
                            HStack {
                                a.picture(36)
                                Text(a.name)
                                Spacer()
                                Text(i == 0 ? "Main artist" : "Feature").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onMove { selected.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { selected.remove(atOffsets: $0) }
                    } header: { Text("Linked (\(selected.count))") } footer: { Text("Drag to choose the main artist.") }
.themedRow()
                }
                Section {
                    ForEach(results) { a in
                        let on = selected.contains { $0.id == a.id }
                        Button {
                            withAnimation {
                                if on { selected.removeAll { $0.id == a.id } } else { selected.append(a) }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                a.picture(44)
                                VStack(alignment: .leading) {
                                    Text(a.name).foregroundStyle(.primary)
                                    if let f = a.fans { Text("\(Fmt.count(f)) fans").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                                    .foregroundStyle(on ? look.accent : .secondary)
                            }
                        }
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                } header: { Text("Search results") }
.themedRow()
            }
            .environment(\.editMode, .constant(.active))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search artists")
            .themedForm()
            .navigationTitle("Link artists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(selected); dismiss() }.bold() }
            }
            .onAppear {
                if selected.isEmpty { selected = initial }
                if query.isEmpty { query = suggestion }
            }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                loading = true
                results = (try? await Catalog.searchArtists(q, limit: 15)) ?? []
                loading = false
            }
        }
    }
}

// MARK: - Trim

struct TrimView: View {
    let songID: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var fadeIn: Double = 0
    @State private var fadeOut: Double = 0
    @State private var bars: [Float] = []
    @State private var analysis: AudioAnalysis?
    @State private var loaded = false

    private var total: Double {
        let d = analysis?.duration ?? app.library.entry(songID)?.song.duration ?? 0
        return d > 0 ? d : 1
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            HStack(alignment: .center, spacing: 2) {
                                ForEach(Array(bars.enumerated()), id: \.offset) { i, v in
                                    let t = (Double(i) + 0.5) / Double(max(bars.count, 1)) * total
                                    Capsule()
                                        .fill(t >= start && t <= end ? look.accent : Color.secondary.opacity(0.35))
                                        .frame(height: max(3, CGFloat(v) * geo.size.height))
                                }
                            }
                            .frame(maxHeight: .infinity)
                            handle(x: w * start / total, height: geo.size.height)
                                .gesture(DragGesture().onChanged { v in
                                    start = min(max(0, Double(v.location.x / w) * total), end - 5)
                                })
                            handle(x: w * end / total, height: geo.size.height)
                                .gesture(DragGesture().onChanged { v in
                                    end = max(min(total, Double(v.location.x / w) * total), start + 5)
                                })
                        }
                    }
                    .frame(height: 90)
                    HStack {
                        Text(Fmt.time(start)); Spacer(); Text("Length \(Fmt.time(end - start))").bold(); Spacer(); Text(Fmt.time(end))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                if bars.isEmpty { Text("Measuring the song…").font(.caption).foregroundStyle(.secondary) }
            } footer: { Text("Drag the handles to cut silence, intros or skits.") }
.themedRow()

            Section {
                Stepper("Start \(Fmt.time(start))", value: $start, in: 0...max(0, end - 5), step: 1)
                Stepper("End \(Fmt.time(end))", value: $end, in: min(start + 5, total)...total, step: 1)
                Button("Auto-trim silence") {
                    if let a = analysis {
                        withAnimation { start = a.leadingSilence; end = max(a.leadingSilence + 5, a.duration - a.trailingSilence) }
                    }
                }
                .disabled(analysis == nil)
            }
.themedRow()

            Section("Fades") {
                VStack(alignment: .leading) {
                    Text("Fade in: \(fadeIn, specifier: "%.1f") s")
                    Slider(value: $fadeIn, in: 0...10, step: 0.5)
                }
                VStack(alignment: .leading) {
                    Text("Fade out: \(fadeOut, specifier: "%.1f") s")
                    Slider(value: $fadeOut, in: 0...10, step: 0.5)
                }
            }
.themedRow()

            Section {
                Button { save(); play() } label: { Label("Save and play", systemImage: "play.fill") }
                Button("Reset", role: .destructive) {
                    withAnimation { start = 0; end = total; fadeIn = 0; fadeOut = 0 }
                }
            }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Trim")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() }.bold() } }
        .task {
            guard !loaded, let e = app.library.entry(songID) else { return }
            loaded = true
            var a = AnalysisCache.load(songID)
            if a == nil {
                a = await AudioAnalysis.analyze(e.fileURL)
                if let a { AnalysisCache.save(a, id: songID) }
            }
            analysis = a
            let d = total
            start = min(e.trimStart, d)
            end = min(e.trimEnd ?? d, d)
            if end <= start { end = d }
            fadeIn = e.fadeIn
            fadeOut = e.fadeOut
            withAnimation(.easeOut(duration: 0.4)) { bars = a?.waveform(bars: 64) ?? [] }
        }
    }

    private func handle(x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(Color.primary).frame(width: 4, height: height + 10)
            Circle().fill(Color.primary).frame(width: 16, height: 16).offset(y: -height / 2 - 6)
        }
        .frame(width: 34, height: height + 24)
        .contentShape(Rectangle())
        .position(x: x, y: height / 2)
    }

    private func save() {
        let s = start, e = end, fi = fadeIn, fo = fadeOut, d = total
        app.library.update(songID) { entry in
            entry.trimStart = s < 0.25 ? 0 : s
            entry.trimEnd = e >= d - 0.25 ? nil : e
            entry.fadeIn = fi
            entry.fadeOut = fo
        }
        app.player.reloadIfCurrent(songID)
    }

    private func play() {
        guard let s = app.library.entry(songID)?.song else { return }
        app.player.play([s], context: s.title)
    }
}

// MARK: - Import files

struct ImportFilesView: View {
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        var tagTitle: String
        var tagArtist: String
        var tagAlbum: String
        var duration: Double
        var artwork: Data?
        var status: Status = .looking
        var useCatalog = true
        var artists: [Artist] = []

        enum Status { case looking, match(Song), unsure(Song, [Song]), noMatch, offline }

        var suggestion: Song? {
            switch status {
            case .match(let s), .unsure(let s, _): s
            default: nil
            }
        }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @State private var items: [Item] = []
    @State private var picking = false
    @State private var linkingIndex: Int?
    @State private var choosingIndex: Int?
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Section {
                        VStack(spacing: 14) {
                            Image(systemName: "folder.badge.plus").font(.system(size: 44)).foregroundStyle(look.accent)
                            Text("Add songs from Files").font(.title3.bold())
                            Text("Pick MP3, M4A, WAV, FLAC or AIFF files. Tunes reads their tags and suggests the real song, so the listening time counts for the right artist.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button { picking = true } label: { Text("Choose files").bold().frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 20)
                    }
.themedRow()
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    Section { itemView(i, item) }
.themedRow()
                }
            }
            .themedForm()
            .navigationTitle("Import files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cleanup(); dismiss() } }
                if !items.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(importing ? "Importing…" : "Import \(items.count)") { importAll() }.bold().disabled(importing)
                    }
                    ToolbarItem(placement: .bottomBar) { Button { picking = true } label: { Label("Add more files", systemImage: "plus") } }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await add(urls) } }
            }
            .sheet(isPresented: Binding(get: { linkingIndex != nil }, set: { if !$0 { linkingIndex = nil } })) {
                if let i = linkingIndex, items.indices.contains(i) {
                    LinkArtistView(initial: items[i].artists, suggestion: items[i].tagArtist) { picked in
                        if items.indices.contains(i) { items[i].artists = picked }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { choosingIndex != nil }, set: { if !$0 { choosingIndex = nil } })) {
                if let i = choosingIndex, items.indices.contains(i) {
                    FindSongView(query: "\(items[i].tagArtist) \(items[i].tagTitle)") { song in
                        if items.indices.contains(i) { items[i].status = .match(song); items[i].useCatalog = true }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemView(_ i: Int, _ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("Tags: \(item.tagTitle) · \(item.tagArtist.isEmpty ? "Unknown artist" : item.tagArtist) · \(Fmt.time(item.duration))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        switch item.status {
        case .looking:
            HStack { ProgressView(); Text("Looking for the real song…").foregroundStyle(.secondary) }
        case .match(let s), .unsure(let s, _):
            Button { items[i].useCatalog = true } label: {
                HStack(spacing: 12) {
                    s.artwork(48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).foregroundStyle(.primary).lineLimit(1)
                        Text("\(s.artistLine) · \(s.album?.title ?? "") · \(Fmt.time(s.duration))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if case .unsure = item.status { Text("Not sure. Check it's the same song").font(.caption2).foregroundStyle(.orange) }
                    }
                    Spacer()
                    Image(systemName: item.useCatalog ? "checkmark.circle.fill" : "circle").foregroundStyle(item.useCatalog ? look.accent : .secondary).font(.title3)
                }
            }
            if case .unsure(_, let options) = item.status, options.count > 1 {
                Menu("Other matches") {
                    ForEach(options) { o in Button("\(o.title) – \(o.artistLine) (\(Fmt.time(o.duration)))") { items[i].status = .match(o); items[i].useCatalog = true } }
                }
            }
            Button { items[i].useCatalog = false } label: {
                HStack {
                    Text("Keep my file's info instead").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: !item.useCatalog ? "checkmark.circle.fill" : "circle").foregroundStyle(!item.useCatalog ? look.accent : .secondary).font(.title3)
                }
            }
        case .noMatch, .offline:
            Text(item.status.isOffline ? "You're offline, so it's imported with your file's info." : "No match in the catalog. It's imported with your file's info.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if item.suggestion == nil || !item.useCatalog {
            Button { linkingIndex = i } label: {
                Label(item.artists.isEmpty ? "Link a real artist (so stats count)" : "Linked: \(item.artists.map(\.name).joined(separator: ", "))", systemImage: "person.badge.plus")
            }
            .disabled(!app.network.isOnline)
        }
        if app.network.isOnline {
            Button { choosingIndex = i } label: { Label("Search for the song myself", systemImage: "magnifyingglass") }
        }
        Button("Don't import", role: .destructive) { items.remove(at: i) }
    }

    private func add(_ urls: [URL]) async {
        let tmpDir = Paths.makeDir(FileManager.default.temporaryDirectory.appending(path: "Import", directoryHint: .isDirectory))
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            let dest = tmpDir.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
            let copied = (try? FileManager.default.copyItem(at: url, to: dest)) != nil
            if access { url.stopAccessingSecurityScopedResource() }
            guard copied else { continue }
            let meta = await Self.readTags(dest)
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            var item = Item(url: dest, tagTitle: meta.title ?? fallbackTitle, tagArtist: meta.artist ?? "", tagAlbum: meta.album ?? "",
                            duration: meta.duration, artwork: meta.artwork)
            item.status = app.network.isOnline && !app.prefs.data.offline ? .looking : .offline
            items.append(item)
            let id = item.id
            if case .looking = item.status {
                Task {
                    let outcome = await CatalogMatcher.find(title: item.tagTitle, artist: item.tagArtist, duration: item.duration > 0 ? item.duration : nil)
                    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
                    switch outcome {
                    case .match(let s): items[i].status = .match(s)
                    case .unsure(let b, let o): items[i].status = .unsure(b, o)
                    case .notFound: items[i].status = .noMatch; items[i].useCatalog = false
                    }
                }
            }
        }
    }

    static func readTags(_ url: URL) async -> (title: String?, artist: String?, album: String?, duration: Double, artwork: Data?) {
        let asset = AVURLAsset(url: url)
        var title: String?, artist: String?, album: String?, art: Data?
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle: title = try? await item.load(.stringValue)
                case .commonKeyArtist: artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName: album = try? await item.load(.stringValue)
                case .commonKeyArtwork: art = try? await item.load(.dataValue)
                default: break
                }
            }
        }
        return (title?.nilIfBlank, artist?.nilIfBlank, album?.nilIfBlank, duration.isFinite ? duration : 0, art)
    }

    private func importAll() {
        importing = true
        var done = 0
        var failed = 0
        for (n, item) in items.enumerated() {
            do {
                if item.useCatalog, let s = item.suggestion {
                    try app.library.importFile(item.url, as: s, artworkData: nil)
                } else {
                    let localID = -(Int(Date.now.timeIntervalSince1970 * 1000) % 1_000_000_000_000 + n + 1)
                    let main = item.artists.first ?? Artist(id: -abs((item.tagArtist.isEmpty ? "Unknown" : item.tagArtist).stableHash), name: item.tagArtist.isEmpty ? "Unknown artist" : item.tagArtist)
                    let album = item.tagAlbum.isEmpty ? nil : Album(id: -abs(item.tagAlbum.stableHash), title: item.tagAlbum, artist: main)
                    let song = Song(id: localID, title: item.tagTitle, artist: main, featured: Array(item.artists.dropFirst()), album: album, duration: item.duration)
                    try app.library.importFile(item.url, as: song, artworkData: item.artwork)
                }
                done += 1
            } catch {
                failed += 1
            }
        }
        cleanup()
        app.show(failed == 0 ? "Imported \(done) song\(done == 1 ? "" : "s")" : "Imported \(done), \(failed) failed")
        dismiss()
    }

    private func cleanup() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "Import", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
    }
}

extension ImportFilesView.Item.Status {
    var isOffline: Bool { if case .offline = self { return true } else { return false } }
}

extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Same value on every launch (unlike `hashValue`).
    var stableHash: Int {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(h % 1_000_000_000) + 1
    }
}

/// Search the catalog and pick one song.
struct FindSongView: View {
    let query: String
    let onPick: (Song) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var results: [Song] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { s in
                    Button { onPick(s); dismiss() } label: {
                        HStack(spacing: 12) {
                            s.artwork(44)
                            VStack(alignment: .leading) {
                                Text(s.title).foregroundStyle(.primary).lineLimit(1)
                                Text("\(s.artistLine) · \(s.album?.title ?? "") · \(Fmt.time(s.duration))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always))
            .themedForm()
            .navigationTitle("Find the song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { if text.isEmpty { text = query } }
            .task(id: text) {
                let q = text.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                loading = true
                results = (try? await Catalog.searchSongs(q, limit: 20)) ?? []
                loading = false
            }
        }
    }
}

// MARK: - Spotify playlist import

struct SpotifyImportView: View {
    enum MatchState {
        case matched(Song), owned(Song), unsure(best: Song, options: [Song]), notFound, skipped
        var song: Song? {
            switch self {
            case .matched(let s), .owned(let s): s
            default: nil
            }
        }
    }
    struct Row: Identifiable {
        let id = UUID()
        let track: ExternalTrack
        var result: MatchState?
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @State private var link = ""
    @State private var name = ""
    @State private var rows: [Row] = []
    @State private var loading = false
    @State private var error: String?
    @State private var pickCSV = false
    @State private var findingRow: UUID?
    @State private var matchTask: Task<Void, Never>?
    /// Spotify's embed page lists at most 100 songs, so a link import of exactly that many was probably cut short.
    @State private var linkWasCapped = false
    private static let linkLimit = 100

    private var done: Int { rows.filter { $0.result != nil }.count }
    private var matching: Bool { !rows.isEmpty && done < rows.count }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty { start } else { review }
            }
            .themedForm()
            .navigationTitle("Import from Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { matchTask?.cancel(); dismiss() } }
                if !rows.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { create() }.bold().disabled(matching || rows.allSatisfy { $0.result?.song == nil })
                    }
                }
            }
            .fileImporter(isPresented: $pickCSV, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let parsed = try SpotifyImport.parseCSV(text)
                    begin(name: parsed.name.isEmpty ? url.deletingPathExtension().lastPathComponent : parsed.name, tracks: parsed.tracks)
                    linkWasCapped = false
                } catch { self.error = error.localizedDescription }
            }
            .sheet(isPresented: Binding(get: { findingRow != nil }, set: { if !$0 { findingRow = nil } })) {
                if let id = findingRow, let row = rows.first(where: { $0.id == id }) {
                    FindSongView(query: "\(row.track.artist) \(row.track.title)") { song in
                        if let i = rows.firstIndex(where: { $0.id == id }) {
                            rows[i].result = app.library.isDownloaded(song.id) ? .owned(song) : .matched(song)
                        }
                    }
                }
            }
            .onDisappear { matchTask?.cancel() }
        }
        .interactiveDismissDisabled(matching)
    }

    @ViewBuilder private var start: some View {
        Section {
            TextField("Paste a playlist link", text: $link)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button {
                Task { await fetch() }
            } label: {
                HStack { Text("Import playlist").bold(); if loading { Spacer(); ProgressView() } }
            }
            .disabled(link.isEmpty || loading || !app.network.isOnline)
        } footer: {
            Text("In Spotify: open the playlist → ··· → Share → Copy link. The playlist has to be public.")
        }
.themedRow()
        Section {
            Button { pickCSV = true } label: { Label("Choose a CSV file", systemImage: "doc.text") }
        } footer: {
            Text("Links bring in up to 100 songs. For longer or private playlists, export them as a CSV file at exportify.app, then pick the file here.")
        }
.themedRow()
        if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) }
.themedRow() }
    }

    @ViewBuilder private var review: some View {
        if linkWasCapped {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Only the first \(Self.linkLimit) songs came through", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Spotify only shares the first \(Self.linkLimit) songs of a playlist through a link. To get all of them, export the playlist as a CSV file and import that instead.")
                        .font(.footnote)
                    Text("1. Go to exportify.app and sign in with Spotify.\n2. Tap Export next to the playlist.\n3. Save the file to Files, then tap the button below.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        pickCSV = true
                    } label: {
                        Label("Import the CSV instead", systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Or tap Create to keep just these \(rows.count).")
            }
.themedRow()
        }
        Section {
            TextField("Playlist name", text: $name).font(.headline)
            if matching {
                ProgressView(value: Double(done), total: Double(max(rows.count, 1))) {
                    Text("Finding songs… \(done) of \(rows.count)").font(.caption)
                }
            } else {
                let found = rows.filter { $0.result?.song != nil }.count
                Text("\(found) of \(rows.count) songs ready. Matched songs download as the real songs, so they count for their artists.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
.themedRow()
        let unsure = rows.filter { if case .some(.unsure) = $0.result { return true } else { return false } }
        if !unsure.isEmpty {
            Section {
                ForEach(unsure) { row in unsureRow(row) }
            } header: { Text("Not sure (\(unsure.count))") } footer: { Text("Pick the right version, or skip it.") }
.themedRow()
        }
        let missing = rows.filter { if case .some(.notFound) = $0.result { return true } else { return false } }
        if !missing.isEmpty {
            Section {
                ForEach(missing) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.track.title).lineLimit(1)
                            Text(row.track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Find") { findingRow = row.id }.buttonStyle(.bordered)
                        Button("Skip") { set(row.id, .skipped) }.buttonStyle(.bordered)
                    }
                }
            } header: { Text("Not found (\(missing.count))") }
.themedRow()
        }
        let good = rows.filter { $0.result?.song != nil }
        if !good.isEmpty {
            Section {
                ForEach(good) { row in
                    if let s = row.result?.song {
                        HStack(spacing: 12) {
                            s.artwork(40)
                            VStack(alignment: .leading) {
                                Text(s.title).lineLimit(1)
                                Text(s.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if case .some(.owned) = row.result { Text("Already yours").font(.caption).foregroundStyle(look.accent) }
                        }
                        .swipeActions { Button("Skip") { set(row.id, .skipped) }.tint(.orange) }
                    }
                }
            } header: { Text("Matched (\(good.count))") }
.themedRow()
        }
        let skipped = rows.filter { if case .some(.skipped) = $0.result { return true } else { return false } }
        if !skipped.isEmpty {
            Section("Skipped (\(skipped.count))") {
                ForEach(skipped) { row in
                    HStack {
                        Text("\(row.track.title) – \(row.track.artist)").foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Find") { findingRow = row.id }.font(.caption)
                    }
                }
            }
.themedRow()
        }
    }

    private func unsureRow(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(row.track.title) – \(row.track.artist)\(row.track.duration.map { " · " + Fmt.time($0) } ?? "")")
                .font(.subheadline.weight(.semibold))
            if case .some(.unsure(let best, let options)) = row.result {
                ForEach(([best] + options.filter { $0.id != best.id }).prefix(3)) { s in
                    Button { set(row.id, app.library.isDownloaded(s.id) ? .owned(s) : .matched(s)) } label: {
                        HStack(spacing: 10) {
                            s.artwork(36)
                            VStack(alignment: .leading) {
                                Text(s.title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                Text("\(s.artistLine) · \(Fmt.time(s.duration))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(look.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Search myself") { findingRow = row.id }
                Spacer()
                Button("Skip") { set(row.id, .skipped) }
            }
            .font(.caption.bold())
            .buttonStyle(.borderless)
        }
    }

    private func set(_ id: UUID, _ result: MatchState) {
        if let i = rows.firstIndex(where: { $0.id == id }) { withAnimation { rows[i].result = result } }
    }

    private func fetch() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let p = try await SpotifyImport.fetchPlaylist(link: link)
            begin(name: p.name, tracks: p.tracks)
            linkWasCapped = p.tracks.count >= Self.linkLimit
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func begin(name: String, tracks: [ExternalTrack]) {
        guard !tracks.isEmpty else { error = SpotifyImportError.noTracks.localizedDescription; return }
        matchTask?.cancel()
        self.name = name
        rows = tracks.map { Row(track: $0) }
        let snapshot = rows
        matchTask = Task {
            await withTaskGroup(of: (UUID, MatchState).self) { group in
                var next = 0
                while next < min(4, snapshot.count) {
                    let row = snapshot[next]
                    group.addTask { await (row.id, Self.match(row.track)) }
                    next += 1
                }
                for await (id, result) in group {
                    if Task.isCancelled { group.cancelAll(); return }
                    if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].result = result }
                    if next < snapshot.count {
                        let row = snapshot[next]
                        group.addTask { await (row.id, Self.match(row.track)) }
                        next += 1
                    }
                }
            }
        }
    }

    @MainActor
    private static func match(_ t: ExternalTrack) async -> MatchState {
        if let owned = AppModel.shared.library.find(title: t.title, artist: t.artist) { return .owned(owned.song) }
        switch await CatalogMatcher.find(title: t.title, artist: t.artist, duration: t.duration) {
        case .match(let s): return AppModel.shared.library.isDownloaded(s.id) ? .owned(s) : .matched(s)
        case .unsure(let b, let o): return .unsure(best: b, options: o)
        case .notFound: return .notFound
        }
    }

    private func create() {
        var seen = Set<Int>()
        let songs = rows.compactMap { $0.result?.song }.filter { seen.insert($0.id).inserted }
        let p = app.playlists.create(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Imported playlist" : name, songs: songs)
        app.library.downloadAll(songs)
        app.show("Downloading \(songs.filter { !app.library.isDownloaded($0.id) }.count) songs")
        app.navigate(.playlist(p.id))
    }
}
