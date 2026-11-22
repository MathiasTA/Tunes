import PhotosUI
import SwiftUI

struct PlaylistView: View {
    let playlistID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var renaming = false
    @State private var newName = ""
    @State private var editing = false
    @State private var exportFile: ExportFile?
    @State private var pickingCover = false
    @State private var coverItem: PhotosPickerItem?

    var body: some View {
        if let p = app.playlists.playlist(playlistID) {
            content(p)
        } else {
            ContentUnavailableView("Playlist deleted", systemImage: "music.note.list")
        }
    }

    private func content(_ p: Playlist) -> some View {
        let offline = app.prefs.data.offline || !app.network.isOnline
        let songs = offline ? p.songs.filter { app.library.isDownloaded($0.id) } : p.songs
        let downloadedCount = p.songs.filter { app.library.isDownloaded($0.id) }.count
        var deleteAction: ((IndexSet) -> Void)? = nil
        var moveAction: ((IndexSet, Int) -> Void)? = nil
        if p.isManual {
            let store = app.playlists
            let id = p.id
            deleteAction = { offsets in store.remove(songIDs: Set(offsets.map { songs[$0].id }), from: id) }
            if !offline { moveAction = { from, to in store.move(in: id, from: from, to: to) } }
        }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom, spacing: 16) {
                        Button { pickingCover = true } label: {
                            PlaylistTile(playlist: p, size: 140)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.fill").font(.caption.weight(.bold))
                                        .padding(7).background(.black.opacity(0.45), in: Circle()).foregroundStyle(.white)
                                        .padding(6)
                                }
                        }
                        .buttonStyle(PressStyle())
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                        .accessibilityLabel("Change cover photo")
                        VStack(alignment: .leading, spacing: 6) {
                            if let b = p.badge {
                                Text(b).font(.system(size: 10, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                            }
                            Text(p.name).font(.title2.bold()).lineLimit(3)
                            Text(description(p)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Button { app.playlists.setKeepDownloaded(p.id, !p.keepDownloaded) } label: {
                            Image(systemName: p.keepDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.title2).foregroundStyle(p.keepDownloaded ? look.accent : .secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(p.keepDownloaded ? "Stop keeping downloaded" : "Keep downloaded")
                        Menu {
                            menuItems(p)
                        } label: {
                            Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44).foregroundStyle(.secondary)
                        }
                        Text(p.keepDownloaded ? "Keeps every song downloaded" : "\(downloadedCount) of \(p.songs.count) downloaded")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { app.player.play(songs, context: p.name, playlistID: p.id, shuffled: true) } label: {
                            Image(systemName: "shuffle").font(.title3).frame(width: 44, height: 44)
                        }
                        .buttonStyle(PressStyle())
                        .disabled(downloadedCount == 0)
                        .accessibilityLabel("Shuffle")
                        Button { app.player.play(songs, context: p.name, playlistID: p.id, shuffled: false) } label: {
                            Image(systemName: "play.fill").font(.title2).foregroundStyle(.black)
                                .frame(width: 56, height: 56).background(look.accent, in: Circle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(downloadedCount == 0)
                        .accessibilityLabel("Play")
                    }
                    ListDownloadProgress(songs: p.songs)
                    if downloadedCount == 0 && !p.songs.isEmpty {
                        Button { app.library.downloadAll(p.songs) } label: {
                            Label("Download all \(p.songs.count) songs to play them", systemImage: "arrow.down.circle").font(.subheadline.weight(.semibold))
                        }
                    }
                    if let err = app.playlists.errors[p.id] {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 0) {
                        if p.isChart {
                            Text("\(i + 1)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary).frame(width: 30)
                        }
                        SongRow(song: s, queue: songs, context: p.name, playlistID: p.id, likeOnTrailingSwipe: !p.isManual)
                    }
                }
                .onDelete(perform: deleteAction)
                .onMove(perform: moveAction)
                if songs.isEmpty {
                    Text(emptyText(p)).font(.footnote).foregroundStyle(.secondary).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .themeBackground()
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .navigationTitle(p.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if p.isManual && !p.songs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "Done" : "Edit") { withAnimation { editing.toggle() } }
                }
            }
        }
        .refreshable { await app.playlists.refresh(p.id, force: true) }
        .task { await app.playlists.refresh(p.id) }
        .sheet(item: $exportFile) { f in ActivityView(items: [f.url]).ignoresSafeArea() }
        .photosPicker(isPresented: $pickingCover, selection: $coverItem, matching: .images)
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { setCover(data, for: p) }
                coverItem = nil
            }
        }
        .alert("Rename playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { app.playlists.update(p.id) { $0.name = newName } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func menuItems(_ p: Playlist) -> some View {
        Button { app.playlists.togglePin(p.id) } label: { Label(p.pinned ? "Unpin" : "Pin to top", systemImage: "pin") }
        Button { newName = p.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
        Button { pickingCover = true } label: { Label(p.coverVersion == nil ? "Add cover photo" : "Change cover photo", systemImage: "photo") }
        if p.coverVersion != nil {
            Button { setCover(nil, for: p) } label: { Label("Remove cover photo", systemImage: "photo.badge.minus") }
        }
        if case .auto = p.kind {
            Button { app.sheet = .autoPlaylist(p.id) } label: { Label("Change rules", systemImage: "slider.horizontal.3") }
        }
        if !p.isManual {
            Button { Task { await app.playlists.refresh(p.id, force: true) } } label: { Label("Update now", systemImage: "arrow.clockwise") }
            Button { app.playlists.create(name: "\(p.name) (copy)", songs: p.songs); app.show("Saved as your own playlist") } label: {
                Label("Save a copy as my playlist", systemImage: "square.on.square")
            }
        }
        Button { app.sheet = .addToPlaylist(p.songs) } label: { Label("Add all to another playlist", systemImage: "plus.square.on.square") }
        Menu {
            Button { exportFile = PlaylistExport.csv(p) } label: { Label("CSV file (works with Tunes & Exportify)", systemImage: "doc.text") }
            Button {
                UIPasteboard.general.string = PlaylistExport.text(p)
                app.show("Copied \(p.songs.count) songs")
            } label: { Label("Copy as text", systemImage: "doc.on.doc") }
        } label: { Label("Export playlist", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { app.playlists.delete(p.id); app.navigateBack() } label: { Label("Delete playlist", systemImage: "trash") }
    }

    /// Saves (or removes, with nil) a playlist's own cover photo, cropped square.
    private func setCover(_ data: Data?, for p: Playlist) {
        if let old = p.coverVersion { try? FileManager.default.removeItem(at: Paths.playlistCover(p.id, old)) }
        guard let data, let img = UIImage(data: data) else {
            app.playlists.update(p.id) { $0.coverVersion = nil }
            return
        }
        let side = min(img.size.width, img.size.height)
        let target = CGSize(width: 800, height: 800)
        let renderer = UIGraphicsImageRenderer(size: target)
        let square = renderer.image { _ in
            let scale = target.width / max(side, 1)
            let w = img.size.width * scale, h = img.size.height * scale
            img.draw(in: CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h))
        }
        let version = (p.coverVersion ?? 0) + 1
        guard let jpg = square.jpegData(compressionQuality: 0.85),
              (try? jpg.write(to: Paths.playlistCover(p.id, version), options: .atomic)) != nil else {
            app.show("Couldn't save the photo")
            return
        }
        withAnimation { app.playlists.update(p.id) { $0.coverVersion = version } }
        app.haptic(.success)
    }

    private func description(_ p: Playlist) -> String {
        switch p.kind {
        case .manual: return "\(p.songs.count) songs"
        case .chart(let c):
            let when = p.refreshedAt.map { "updated \($0.formatted(.relative(presentation: .named)))" } ?? "updates when you're online"
            return "\(c.sourceLabel) · \(p.songs.count) songs · \(when)"
        case .auto(let r):
            let when = p.refreshedAt.map { "updated \($0.formatted(.relative(presentation: .named)))" } ?? "not updated yet"
            return "\(r.source.title) · \(p.songs.count) songs · \(when)"
        }
    }

    private func emptyText(_ p: Playlist) -> String {
        if app.playlists.refreshing.contains(p.id) { return "Updating…" }
        switch p.kind {
        case .manual: return "Add songs with the ··· menu on any song."
        case .chart: return "Couldn't load this chart yet. Pull down to try again."
        case .auto(let r):
            switch r.source {
            case .mostPlayed: return "Listen to some downloaded songs and your most played show up here."
            case .forgotten: return "Songs you loved but haven't played in two months show up here."
            case .newReleases: return "New songs from artists you listen to and follow show up here."
            case .similar: return "Pull down to find artists like yours."
            case .dailyMix: return "Listen to a few artists and your daily mixes fill up. They change every day."
            case .chart: return "Pull down to load the chart."
            }
        }
    }
}

extension AppModel {
    func navigateBack() {
        switch tab {
        case .home: if !homePath.isEmpty { homePath.removeLast() }
        case .library: if !libraryPath.isEmpty { libraryPath.removeLast() }
        case .stats: if !statsPath.isEmpty { statsPath.removeLast() }
        }
    }
}

/// Opens the playlist behind a chart (creating it the first time).
struct ChartRouteView: View {
    let source: ChartSource
    @Environment(AppModel.self) private var app
    @State private var id: UUID?

    var body: some View {
        Group {
            if let id { PlaylistView(playlistID: id) } else { ProgressView() }
        }
        .onAppear { id = app.playlists.ensureChart(source).id }
    }
}

struct BrowseChartsView: View {
    enum Tab: String, CaseIterable { case countries = "Countries", genres = "Genres", editors = "Editors" }
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var tab: Tab = .countries
    @State private var genres: [Catalog.Genre] = []
    @State private var editors: [Catalog.PlaylistInfo] = []
    @State private var query = ""

    var body: some View {
        @Bindable var prefs = app.prefs
        List {
            Section {
                ForEach(prefs.data.homeCharts) { c in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: c.colorHex)).frame(width: 36, height: 36)
                            .overlay(Text(c.tag).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name)
                            Text(c.sourceLabel).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { prefs.data.homeCharts.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    let removed = offsets.map { prefs.data.homeCharts[$0] }
                    prefs.data.homeCharts.remove(atOffsets: offsets)
                    for c in removed { app.playlists.removeChart(c) }
                }
            } header: {
                SectionLabel(text: "On your Home (\(prefs.data.homeCharts.count))")
            } footer: {
                Text("Drag to reorder, swipe to remove.")
            }
.themedRow()

            Section {
                Picker("Type", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                ForEach(items, id: \.id) { c in
                    let added = prefs.data.homeCharts.contains { $0.id == c.id }
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: c.colorHex)).frame(width: 40, height: 40)
                            .overlay(Text(c.tag).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name)
                            Text(c.sourceLabel).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            withAnimation {
                                if added {
                                    prefs.data.homeCharts.removeAll { $0.id == c.id }
                                    app.playlists.removeChart(c)
                                } else {
                                    prefs.data.homeCharts.append(c)
                                }
                            }
                            app.haptic(.light)
                        } label: {
                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle").font(.title2)
                                .foregroundStyle(added ? look.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(added ? "Remove \(c.name)" : "Add \(c.name)")
                    }
                }
                if tab != .countries && items.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            }
.themedRow()
        }
        .environment(\.editMode, .constant(.active))
        .themedForm()
        .navigationTitle("Charts")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Find a country, genre or playlist")
        .task {
            if genres.isEmpty { genres = (try? await Catalog.genres()) ?? [] }
            if editors.isEmpty { editors = (try? await Catalog.chartPlaylists(limit: 40)) ?? [] }
        }
    }

    private var items: [ChartSource] {
        let list: [ChartSource]
        switch tab {
        case .countries: list = [ChartCatalog.worldwide] + ChartCatalog.countries.map(ChartCatalog.country)
        case .genres: list = genres.map { ChartCatalog.genre(id: $0.id, name: $0.name) }
        case .editors: list = editors.map(ChartCatalog.editorial)
        }
        return query.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

struct AutoPlaylistEditor: View {
    let playlistID: UUID?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @State private var name = "My mix"
    @State private var rule = AutoRule(source: .similar)
    @State private var keepDownloaded = false
    @State private var artistQuery = ""
    @State private var artistResults: [Artist] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Name", text: $name) }
.themedRow()
                Section("Songs come from") {
                    Picker("Source", selection: $rule.source) {
                        ForEach(AutoRule.Source.allCases) { s in
                            VStack(alignment: .leading) { Text(s.title); Text(s.detail).font(.caption).foregroundStyle(.secondary) }.tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
.themedRow()
                Section("Rules") {
                    Stepper("Max songs: \(rule.maxSongs)", value: $rule.maxSongs, in: 10...200, step: 10)
                    if rule.source == .dailyMix {
                        Stepper("Built around your #\(rule.mix ?? 1) artist", value: Binding(get: { rule.mix ?? 1 }, set: { rule.mix = $0 }), in: 1...6)
                    }
                    if rule.source == .newReleases {
                        Stepper("Released within \(rule.withinWeeks) week\(rule.withinWeeks == 1 ? "" : "s")", value: $rule.withinWeeks, in: 1...26)
                    }
                    if rule.source == .newReleases || rule.source == .similar {
                        Toggle("Include live versions & remixes", isOn: $rule.includeLiveAndRemixes)
                    }
                    Toggle("Keep downloaded", isOn: $keepDownloaded)
                }
.themedRow()
                if rule.source == .newReleases || rule.source == .similar {
                    Section {
                        if rule.artists.isEmpty {
                            Text(rule.source == .similar ? "Using your top 10 artists" : "Using your top artists and the ones you follow")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(rule.artists) { a in
                            HStack { a.picture(32); Text(a.name) }
                        }
                        .onDelete { rule.artists.remove(atOffsets: $0) }
                        TextField("Add an artist…", text: $artistQuery)
                        ForEach(artistResults) { a in
                            Button {
                                if !rule.artists.contains(where: { $0.id == a.id }) { rule.artists.append(a) }
                                artistQuery = ""
                                artistResults = []
                            } label: { HStack { a.picture(32); Text(a.name).foregroundStyle(.primary) } }
                        }
                    } header: { Text("Artists") } footer: { Text("Leave empty to follow your listening automatically.") }
.themedRow()
                }
                if rule.source == .chart {
                    Section("Chart") {
                        Picker("Chart", selection: Binding(get: { rule.chart?.id ?? "" }, set: { id in
                            rule.chart = chartChoices.first { $0.id == id }
                        })) {
                            Text("Choose…").tag("")
                            ForEach(chartChoices, id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
.themedRow()
                }
                if let id = playlistID {
                    Section {
                        Button("Delete playlist", role: .destructive) { app.playlists.delete(id); dismiss(); app.navigateBack() }
                    }
.themedRow()
                }
            }
            .themedForm()
            .navigationTitle(playlistID == nil ? "New auto playlist" : "Auto playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .task(id: artistQuery) {
                let q = artistQuery.trimmingCharacters(in: .whitespaces)
                guard q.count >= 2 else { artistResults = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                artistResults = (try? await Catalog.searchArtists(q, limit: 5)) ?? []
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var chartChoices: [ChartSource] {
        var list = app.prefs.data.homeCharts
        for c in [ChartCatalog.worldwide] + ChartCatalog.countries.map(ChartCatalog.country) where !list.contains(where: { $0.id == c.id }) {
            list.append(c)
        }
        return list
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        guard let id = playlistID, let p = app.playlists.playlist(id), case .auto(let r) = p.kind else { return }
        name = p.name
        rule = r
        keepDownloaded = p.keepDownloaded
    }

    private func save() {
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? rule.source.title : name
        if let id = playlistID {
            app.playlists.update(id) {
                $0.name = finalName
                $0.kind = .auto(rule)
                $0.refreshedAt = nil
            }
            app.playlists.setKeepDownloaded(id, keepDownloaded)
            Task { await app.playlists.refresh(id, force: true) }
            dismiss()
        } else {
            let p = app.playlists.createAuto(name: finalName, rule: rule, keepDownloaded: keepDownloaded)
            app.navigate(.playlist(p.id))
        }
    }
}


struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Turns a playlist into a CSV file (same columns as Exportify, so Tunes and other apps can import it) or plain text.
enum PlaylistExport {
    static func csv(_ p: Playlist) -> ExportFile? {
        func field(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["Track Name,Artist Name(s),Album Name,Duration (ms)"]
        for s in p.songs {
            lines.append([field(s.title), field(s.allArtists.map(\.name).joined(separator: ", ")),
                          field(s.album?.title ?? ""), String(Int(s.duration * 1000))].joined(separator: ","))
        }
        let safe = p.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let dir = FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "\(safe.isEmpty ? "Playlist" : safe).csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return ExportFile(url: url)
        } catch {
            return nil
        }
    }

    static func text(_ p: Playlist) -> String {
        ([p.name, ""] + p.songs.enumerated().map { "\($0.offset + 1). \($0.element.artistLine) – \($0.element.title)" })
            .joined(separator: "\n")
    }
}

/// The iOS share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
