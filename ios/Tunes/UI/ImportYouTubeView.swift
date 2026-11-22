import PhotosUI
import SwiftUI

/// Adds a song from YouTube that the catalog doesn't have: find the video, fill in the details,
/// link the real artists, and download it.
struct ImportYouTubeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look

    // Finding the video
    @State private var query = ""
    @State private var results: [VideoCandidate] = []
    @State private var searching = false
    @State private var link = ""
    @State private var findError: String?

    // Details
    @State private var video: VideoCandidate?
    @State private var title = ""
    @State private var albumTitle = ""
    @State private var artists: [Artist] = []
    @State private var artistGuess = ""
    @State private var cover: Data?
    @State private var photo: PhotosPickerItem?
    @State private var linking = false
    @State private var catalogMatch: Song?
    @State private var checkingCatalog = false
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let video { details(video) } else { finder }
            }
            .themedForm()
            .navigationTitle(video == nil ? "Import from YouTube" : "Song details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if video != nil && !importing {
                        Button("Back") { withAnimation { video = nil } }
                    } else {
                        Button("Cancel") { dismiss() }.disabled(importing)
                    }
                }
            }
            .interactiveDismissDisabled(importing)
            .sheet(isPresented: $linking) {
                LinkArtistView(initial: artists, suggestion: artistGuess) { picked in artists = picked }
            }
        }
    }

    // MARK: Step 1: find the video

    private var finder: some View {
        Form {
            Section {
                HStack {
                    TextField("Search YouTube", text: $query)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    Button { Task { await search() } } label: {
                        if searching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
                if let findError { Text(findError).font(.footnote).foregroundStyle(.red) }
                ForEach(results) { v in
                    Button { choose(v) } label: {
                        HStack(spacing: 10) {
                            Thumb(videoID: v.id).frame(width: 64, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                Text(v.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.time(v.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("Search") } footer: {
                if results.isEmpty { Text("Try \"artist song\", or add \"audio\" or \"topic\" for clean album versions.") }
            }
            .themedRow()

            Section {
                TextField("Paste a YouTube link", text: $link)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Use this link") {
                    guard let id = YouTubeSearch.videoID(from: link) else { findError = YouTubeError.badLink.localizedDescription; return }
                    choose(VideoCandidate(id: id, title: "", channel: "", duration: nil))
                }
                .disabled(link.isEmpty)
            } header: { Text("Or use a link") } footer: {
                Text("In the YouTube app: Share → Copy link.")
            }
            .themedRow()
        }
    }

    // MARK: Step 2: details

    private func details(_ v: VideoCandidate) -> some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    coverView.frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: look.artRadius(size: 96)))
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $photo, matching: .images) { Label("Choose photo", systemImage: "photo") }
                        Button { Task { await loadThumbnail(v.id) } } label: { Label("Use video picture", systemImage: "play.rectangle") }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                if !v.title.isEmpty {
                    Text("From: \(v.title)\(v.channel.isEmpty ? "" : " · \(v.channel)")").font(.caption).foregroundStyle(.secondary)
                }
            }
            .themedRow()

            Section("Song") {
                TextField("Title", text: $title)
                TextField("Album (optional)", text: $albumTitle)
            }
            .themedRow()

            Section {
                ForEach(Array(artists.enumerated()), id: \.element.id) { i, a in
                    HStack {
                        a.picture(32)
                        Text(a.name)
                        Spacer()
                        Text(i == 0 ? "Main" : "Feature").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { artists.remove(atOffsets: $0) }
                Button { linking = true } label: {
                    Label(artists.isEmpty ? "Link the real artist" : "Change linked artists", systemImage: "person.badge.plus")
                }
            } header: { Text("Artists") } footer: {
                Text("Linked artists get the listening time in your stats and Wrapped, and the song shows on their page.")
            }
            .themedRow()

            if let match = catalogMatch {
                Section {
                    HStack(spacing: 12) {
                        match.artwork(44)
                        VStack(alignment: .leading) {
                            Text(match.title).lineLimit(1)
                            Text(match.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Button("Use the catalog song with this video") {
                        app.library.download(match, video: v)
                        app.show("Downloading \(match.title)")
                        dismiss()
                    }
                } header: { Text("Found in the catalog") } footer: {
                    Text("This song is in the catalog after all. Using it gets the real cover, album and artist links.")
                }
                .themedRow()
            }

            Section {
                if importing {
                    let p: Double = { if case .downloading(let x) = app.library.states[songID] { return x } else { return 0 } }()
                    ProgressView(value: p) { Text("Downloading… \(Int(p * 100))%").font(.caption) }
                } else {
                    Button { Task { await importSong(v) } } label: {
                        Label("Import song", systemImage: "arrow.down.circle.fill").font(.headline)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let importError { Text(importError).font(.footnote).foregroundStyle(.red) }
            }
            .themedRow()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { cover = Self.square(data) }
                photo = nil
            }
        }
        .task(id: title + "|" + (artists.first?.name ?? artistGuess)) {
            // Quietly check whether the catalog has this song after all.
            guard !title.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let artist = artists.first?.name ?? artistGuess
            if case .match(let s) = await CatalogMatcher.find(title: title, artist: artist, duration: v.duration) {
                catalogMatch = app.library.isDownloaded(s.id) ? nil : s
            } else {
                catalogMatch = nil
            }
        }
    }

    @ViewBuilder private var coverView: some View {
        if let cover, let img = UIImage(data: cover) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.2)
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    /// A stable, unique id for a song of your own (negative, so it never clashes with catalog songs).
    @State private var songID = -Int(Date.now.timeIntervalSince1970 * 1000) % 1_000_000_000_000

    private func choose(_ v: VideoCandidate) {
        findError = nil
        let (guessArtist, guessTitle) = Self.split(v.title, channel: v.channel)
        title = guessTitle
        artistGuess = guessArtist
        artists = []
        cover = nil
        catalogMatch = nil
        withAnimation { video = v }
        Task {
            await loadThumbnail(v.id)
            // Pre-link the artist if the catalog has an exact name match.
            if !guessArtist.isEmpty, let found = try? await Catalog.searchArtists(guessArtist, limit: 3),
               let exact = found.first(where: { $0.name.normalizedForMatching == guessArtist.normalizedForMatching }),
               artists.isEmpty {
                artists = [exact]
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            results = Array(try await YouTubeSearch.search(q).prefix(15))
            findError = results.isEmpty ? "No videos found. Try different words." : nil
        } catch {
            findError = error.localizedDescription
        }
    }

    private func loadThumbnail(_ id: String) async {
        for size in ["maxresdefault", "hqdefault"] {
            guard let url = URL(string: "https://i.ytimg.com/vi/\(id)/\(size).jpg"),
                  let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200, let sq = Self.square(result.0) else { continue }
            cover = sq
            return
        }
    }

    private func importSong(_ v: VideoCandidate) async {
        importing = true
        importError = nil
        defer { importing = false }
        let main = artists.first ?? Artist(id: -abs((artistGuess.isEmpty ? "Unknown" : artistGuess).stableHash),
                                          name: artistGuess.isEmpty ? "Unknown artist" : artistGuess)
        let t = title.trimmingCharacters(in: .whitespaces)
        let al = albumTitle.trimmingCharacters(in: .whitespaces)
        let album = al.isEmpty ? nil : Album(id: -abs(al.stableHash), title: al, artist: main)
        let song = Song(id: songID, title: t, artist: main, featured: Array(artists.dropFirst()), album: album, duration: v.duration ?? 0)
        do {
            try await app.library.importFromYouTube(v, as: song, artworkData: cover)
            app.show("Added \(t)")
            dismiss()
        } catch {
            importError = error.localizedDescription
        }
    }

    /// "Artist - Title (Official Video)" → ("Artist", "Title"). Falls back to the channel name.
    static func split(_ raw: String, channel: String) -> (String, String) {
        let cleaned = CatalogMatcher.stripExtras(raw).trimmingCharacters(in: .whitespaces)
        for sep in [" - ", " – ", " — ", " | "] {
            let parts = cleaned.components(separatedBy: sep)
            if parts.count >= 2 {
                return (parts[0].trimmingCharacters(in: .whitespaces), parts.dropFirst().joined(separator: sep).trimmingCharacters(in: .whitespaces))
            }
        }
        let artist = channel.replacingOccurrences(of: " - Topic", with: "").replacingOccurrences(of: "VEVO", with: "")
            .trimmingCharacters(in: .whitespaces)
        return (artist, cleaned)
    }

    /// Center-crops a picture to a square cover.
    static func square(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let side = min(img.size.width, img.size.height)
        let target = CGSize(width: 800, height: 800)
        let out = UIGraphicsImageRenderer(size: target).image { _ in
            let scale = target.width / max(side, 1)
            let w = img.size.width * scale, h = img.size.height * scale
            img.draw(in: CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h))
        }
        return out.jpegData(compressionQuality: 0.85)
    }
}

/// A YouTube video's picture.
private struct Thumb: View {
    let videoID: String
    var body: some View {
        AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")) { img in
            img.resizable().scaledToFill()
        } placeholder: { Color.secondary.opacity(0.2) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
