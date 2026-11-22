import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bar above the mini player

/// Shows while songs are downloading (or some failed). Tap for the full list.
struct DownloadsBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    static func isVisible(_ lib: Library) -> Bool { lib.activeCount > 0 || !lib.failedIDs.isEmpty }

    var body: some View {
        let lib = app.library
        if Self.isVisible(lib) && !app.showPlayer {
            Button { app.sheet = .downloads } label: {
                HStack(spacing: 10) {
                    if lib.activeCount > 0 {
                        ProgressRing(progress: lib.batchProgress, accent: look.accent).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Downloading \(lib.activeCount) song\(lib.activeCount == 1 ? "" : "s")")
                                .font(.subheadline.weight(.semibold))
                            Text("\(lib.batchDone) of \(lib.batchTotal) done · \(Int(lib.batchProgress * 100))%"
                                 + (lib.failedIDs.isEmpty ? "" : " · \(lib.failedIDs.count) failed"))
                                .font(.caption).foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("\(lib.failedIDs.count) download\(lib.failedIDs.count == 1 ? "" : "s") failed")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Text(lib.failedIDs.isEmpty ? "Details" : "Fix").font(.caption.weight(.bold)).foregroundStyle(look.accent)
                    Image(systemName: "chevron.up").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: look.radius(14), style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
                .padding(.horizontal, 8)
            }
            .buttonStyle(PressStyle())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: lib.batchProgress)
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let accent: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            Circle().trim(from: 0, to: max(0.02, progress))
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

// MARK: - Card at the top of Library

struct LibraryDownloadCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        let lib = app.library
        if DownloadsBar.isVisible(lib) {
            Button { app.sheet = .downloads } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(lib.activeCount > 0 ? "Downloading" : "Downloads need attention",
                              systemImage: lib.activeCount > 0 ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(lib.activeCount > 0 ? look.accent : .orange)
                        Spacer()
                        if lib.activeCount > 0 {
                            Text("\(Int(lib.batchProgress * 100))%").font(.title3.bold().monospacedDigit())
                                .contentTransition(.numericText())
                        }
                    }
                    if lib.activeCount > 0 {
                        ProgressView(value: lib.batchProgress).tint(look.accent)
                    }
                    HStack(spacing: 14) {
                        stat("\(lib.batchDone)", "done")
                        stat("\(lib.activeCount)", "to go")
                        if !lib.failedIDs.isEmpty { stat("\(lib.failedIDs.count)", "failed", color: .orange) }
                        Spacer()
                        Text("See all").font(.subheadline.weight(.semibold)).foregroundStyle(look.accent)
                    }
                }
                .padding(14)
                .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(16), style: .continuous))
            }
            .buttonStyle(PressStyle())
        }
    }

    private func stat(_ value: String, _ label: String, color: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.subheadline.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Progress for one playlist or album

/// "Downloading · 8 of 20" with a bar, shown while any of these songs are downloading.
struct ListDownloadProgress: View {
    let songs: [Song]
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        let lib = app.library
        let ids = Set(songs.map(\.id))
        let active = ids.filter { lib.states[$0]?.isActive == true }
        let failed = ids.filter { lib.failureReason($0) != nil }
        let have = ids.filter { lib.isDownloaded($0) }.count
        if !active.isEmpty || !failed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if !active.isEmpty {
                        Text("Downloading · \(have) of \(ids.count)").font(.caption.weight(.semibold))
                    } else {
                        Text("\(have) of \(ids.count) downloaded").font(.caption.weight(.semibold))
                    }
                    Spacer()
                    if !failed.isEmpty {
                        Button { app.sheet = .downloads } label: {
                            Label("\(failed.count) failed", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ProgressView(value: Double(have), total: Double(max(ids.count, 1))).tint(look.accent)
            }
            .animation(.easeInOut, value: have)
        }
    }
}

// MARK: - Downloads screen

struct DownloadsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look

    var body: some View {
        let lib = app.library
        NavigationStack {
            List {
                if lib.activeCount > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(lib.batchDone) of \(lib.batchTotal) done").font(.headline)
                                Spacer()
                                Text("\(Int(lib.batchProgress * 100))%").font(.headline.monospacedDigit())
                            }
                            ProgressView(value: lib.batchProgress).tint(look.accent)
                        }
                        .padding(.vertical, 4)
                    }
.themedRow()
                }
                let failed = lib.failedIDs
                if !failed.isEmpty {
                    Section {
                        ForEach(failed, id: \.self) { id in
                            if let song = lib.jobs[id] {
                                NavigationLink { FixDownloadView(song: song) } label: {
                                    row(song, detail: lib.failureReason(id) ?? "Failed", color: .orange)
                                }
                            }
                        }
                        Button("Try all again") { lib.retryAllFailed() }
                        Button("Clear the failed list", role: .destructive) { lib.clearFailed() }
                    } header: { Text("Failed (\(failed.count))") } footer: {
                        Text("Tap a song to see what went wrong and pick the right version yourself.")
                    }
.themedRow()
                }
                let active = lib.activeIDs
                if !active.isEmpty {
                    Section("In progress (\(active.count))") {
                        ForEach(active, id: \.self) { id in
                            if let song = lib.jobs[id] {
                                HStack {
                                    row(song, detail: detail(lib.states[id]), color: .secondary)
                                    if case .downloading(let p) = lib.states[id] {
                                        ProgressRing(progress: p, accent: look.accent).frame(width: 22, height: 22)
                                    }
                                }
                                .swipeActions {
                                    Button("Cancel", role: .destructive) { lib.cancelDownload(id) }
                                }
                            }
                        }
                    }
.themedRow()
                }
                if active.isEmpty && failed.isEmpty {
                    ContentUnavailableView("All done", systemImage: "checkmark.circle", description: Text("Nothing is downloading right now."))
                        .listRowBackground(Color.clear)
                }
            }
            .themedForm()
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ song: Song, detail: String, color: Color) -> some View {
        HStack(spacing: 12) {
            song.artwork(42)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).lineLimit(1)
                Text(song.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(color).lineLimit(2)
            }
        }
    }

    private func detail(_ state: DownloadState?) -> String {
        switch state {
        case .queued: "Waiting in line"
        case .waiting(let why): why
        case .matching: "Looking for it on YouTube…"
        case .downloading(let p): "Downloading · \(Int(p * 100))%"
        default: ""
        }
    }
}

// MARK: - Fix one download

/// Everything about one failed song, with every way to get it right.
struct FixDownloadView: View {
    let song: Song
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @State private var query = ""
    @State private var results: [VideoCandidate] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var link = ""
    @State private var linkError: String?
    @State private var pickingFile = false
    @State private var fileError: String?

    var body: some View {
        let lib = app.library
        let state = lib.states[song.id]
        Form {
            Section {
                HStack(spacing: 14) {
                    song.artwork(64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title).font(.headline).lineLimit(2)
                        Text(song.artistLine).font(.subheadline).foregroundStyle(.secondary)
                        Text([song.album?.title, song.duration > 0 ? "Real length \(Fmt.time(song.duration))" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
.themedRow()

            Section("What happened") {
                if lib.isDownloaded(song.id) {
                    Label("Downloaded. All good!", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if let state, state.isActive {
                    HStack { ProgressView(); Text("Working on it…").foregroundStyle(.secondary) }
                } else if let why = lib.failureReason(song.id) {
                    Text(why).font(.subheadline)
                    Text(explanation(step: lib.failedStep[song.id], reason: why)).font(.footnote).foregroundStyle(.secondary)
                    if let tried = lib.lastTried[song.id] {
                        LabeledContent("Tried", value: "\(tried.title) · \(tried.channel)")
                            .font(.footnote)
                    }
                }
                Button { lib.download(song) } label: { Label("Try again", systemImage: "arrow.clockwise") }
                    .disabled(lib.isDownloaded(song.id) || state?.isActive == true)
            }
.themedRow()

            Section {
                HStack {
                    TextField("Search YouTube", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    Button { Task { await search() } } label: {
                        if searching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
                if let searchError { Text(searchError).font(.footnote).foregroundStyle(.red) }
                ForEach(results) { v in
                    Button { pick(v) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                Text(v.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.time(v.duration)).font(.caption.monospacedDigit())
                                .foregroundStyle(lengthColor(v.duration))
                            if v.id == lib.lastTried[song.id]?.id {
                                Text("tried").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: { Text("Pick a YouTube version") } footer: {
                Text("Green lengths match the real song, orange are close. Tap one to download it. Searches like \"artist song topic\" or \"artist song audio\" often find clean album versions.")
            }
.themedRow()

            Section {
                TextField("Paste a YouTube link", text: $link)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Download from this link") {
                    guard let id = YouTubeSearch.videoID(from: link) else { linkError = YouTubeError.badLink.localizedDescription; return }
                    linkError = nil
                    pick(VideoCandidate(id: id, title: "Pasted link", channel: "youtu.be/\(id)", duration: nil))
                }
                .disabled(link.isEmpty)
                if let linkError { Text(linkError).font(.footnote).foregroundStyle(.red) }
            } header: { Text("Use a specific video") } footer: {
                Text("Find the song in the YouTube app or website, tap Share → Copy link, and paste it here.")
            }
.themedRow()

            Section {
                Button { pickingFile = true } label: { Label("Choose an audio file", systemImage: "folder") }
                if let fileError { Text(fileError).font(.footnote).foregroundStyle(.red) }
            } header: { Text("Use your own file") } footer: {
                Text("Have the song as a file? It's added as this exact song, so it still counts for \(song.artist.name) in your stats.")
            }
.themedRow()

            Section {
                Button("Stop trying to download this", role: .destructive) {
                    lib.cancelDownload(song.id)
                    dismiss()
                }
            }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Fix download")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            do {
                _ = try lib.importFile(url, as: song, artworkData: nil)
                app.show("Added \(song.title)")
                dismiss()
            } catch { fileError = error.localizedDescription }
        }
        .task {
            guard query.isEmpty else { return }
            query = "\(song.artist.name) \(song.title)"
            await search()
        }
        .onChange(of: lib.isDownloaded(song.id)) { _, done in
            if done { app.haptic(.success) }
        }
    }

    private func pick(_ v: VideoCandidate) {
        app.library.cancelDownload(song.id)
        app.library.download(song, video: v)
        app.haptic(.light)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            let found = try await YouTubeSearch.search(q)
            let real = song.duration > 0 ? song.duration : nil
            results = Array(found.sorted {
                Matcher.score($0, artist: song.artist.name, title: song.title, duration: real) >
                    Matcher.score($1, artist: song.artist.name, title: song.title, duration: real)
            }.prefix(10))
            searchError = results.isEmpty ? "No videos found. Try different words." : nil
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func lengthColor(_ d: Double?) -> Color {
        guard let d, song.duration > 0 else { return .secondary }
        let diff = abs(d - song.duration)
        return diff <= 4 ? .green : (diff <= 15 ? .orange : .secondary)
    }

    private func explanation(step: String?, reason: String) -> String {
        if step == "search" {
            return "Tunes couldn't find a good YouTube upload of this song. Search below with different words, or paste a link."
        }
        if reason.contains("refused") || reason.contains("403") {
            return "YouTube blocked this download. Trying again in a minute, or picking a different upload, often works."
        }
        return "Tunes found a video but couldn't get its audio. Try again, or pick a different upload below."
    }
}
