import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var prefs = app.prefs
        List {
            Section {
                Toggle(isOn: $prefs.data.offline) {
                    Label { VStack(alignment: .leading) { Text("Offline mode"); Text("Only show downloaded music").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "airplane") }
                }
                NavigationLink { AppearanceView() } label: { Label("Appearance", systemImage: "paintbrush") }
                NavigationLink { ConnectionsView() } label: { Label("Connections", systemImage: "link") }
            } header: { Text("General") }
.themedRow()
            Section {
                NavigationLink { SoundSettingsView() } label: { Label("Sound, EQ & crossfade", systemImage: "slider.vertical.3") }
                Toggle(isOn: $prefs.data.lyricsEnabled) { Label("Show lyrics", systemImage: "quote.bubble") }
            } header: { Text("Playback") } footer: {
                Text("Show lyrics: adds the lyrics card under the player and lets Tunes look up lyrics online.")
            }
.themedRow()
            Section("Your music") {
                NavigationLink { StorageView() } label: { Label("Storage & downloads", systemImage: "internaldrive") }
                NavigationLink { BackupView() } label: { Label("Backup & import", systemImage: "externaldrive.badge.icloud") }
                NavigationLink { CustomizeHomeView() } label: { Label("Customize Home", systemImage: "house") }
            }
.themedRow()
            Section {
                Toggle("Download only on Wi-Fi", isOn: $prefs.data.downloadWifiOnly)
                Toggle("Play previews on mobile data", isOn: $prefs.data.previewsOnCellular)
                Toggle("Ask before loading artist extras", isOn: $prefs.data.askBeforeExtras)
            } header: { Text("Mobile data") } footer: {
                Text("Download only on Wi-Fi: songs you download on mobile data wait in line and start when you're on Wi-Fi. Previews: the 30-second clips you hear when tapping a song you don't have. Artist extras: shows, similar artists and bio on artist pages; when this is on, they stay blurred on mobile data until you tap Load.")
            }
.themedRow()
            Section {
                Toggle("Backup download method", isOn: $prefs.data.allowRemoteExtraction)
            } header: { Text("Advanced") } footer: {
                Text("If a song won't download, this lets Tunes ask a helper server for the audio link. Off by default.")
            }
.themedRow()
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                LabeledContent("Songs downloaded", value: "\(app.library.entries.count)")
                LabeledContent("Catalog", value: "Deezer")
                LabeledContent("Lyrics", value: "LRCLIB")
            }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sound

struct SoundSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var output: OutputKind = .phone

    var body: some View {
        @Bindable var prefs = app.prefs
        let profile = prefs.data.eqProfile(output)
        Form {
            Section {
                Picker("Output", selection: $output) { ForEach(OutputKind.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                Toggle("Equalizer", isOn: $prefs.data.eqEnabled)
                if prefs.data.eqEnabled {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(EQPreset.allCases) { p in
                                Chip(title: p.label, selected: profile.preset == p) { setProfile { $0.preset = p } }
                            }
                        }
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<10, id: \.self) { i in
                            VStack(spacing: 6) {
                                Text(String(format: "%+.0f", profile.gains[i])).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                                EQSlider(value: Binding(get: { profile.gains[i] }, set: { v in
                                    setProfile { p in
                                        if p.preset != .custom { p.custom = p.gains; p.preset = .custom }
                                        p.custom[i] = v
                                    }
                                }), accent: look.accent)
                                .frame(height: 150)
                                Text(EQProfile.labels[i]).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } header: { Text("Sound profile") } footer: {
                Text("Each output keeps its own sound. Tunes switches automatically when you plug in headphones or connect a speaker. Now playing on: \(app.player.routeName).")
            }
.themedRow()
            Section {
                Picker("Volume leveling", selection: $prefs.data.normalization) { ForEach(Normalization.allCases) { Text($0.label).tag($0) } }
            } footer: { Text("Evens out loud and quiet songs. Normal suits most people; Loud is best in noisy places.") }
.themedRow()
            Section {
                Toggle("Gapless playback", isOn: $prefs.data.gapless)
                VStack(alignment: .leading) {
                    Text(prefs.data.crossfade == 0 ? "Crossfade: off" : "Crossfade: \(prefs.data.crossfade) s")
                    Slider(value: Binding(get: { Double(prefs.data.crossfade) }, set: { prefs.data.crossfade = Int($0.rounded()) }), in: 0...12, step: 1)
                }
                Toggle("Never crossfade inside albums", isOn: $prefs.data.noCrossfadeInAlbums)
            } header: { Text("Transitions") }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { output = app.player.outputKind }
        .onChange(of: prefs.data.eqEnabled) { _, _ in app.player.applySound() }
        .onChange(of: prefs.data.normalization) { _, _ in app.player.applySound() }
    }

    private func setProfile(_ change: (inout EQProfile) -> Void) {
        var p = app.prefs.data.eqProfile(output)
        change(&p)
        app.prefs.data.eq[output.rawValue] = p
        app.player.applySound()
    }
}

struct EQSlider: View {
    @Binding var value: Float
    let accent: Color
    private let range: ClosedRange<Float> = -12...12

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let frac = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.secondary.opacity(0.2)).frame(width: 4)
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 12, height: 1).offset(y: -h / 2)
                Circle().fill(accent).frame(width: 18, height: 18).offset(y: -(frac * (h - 18)))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = 1 - min(max(0, g.location.y / h), 1)
                let v = range.lowerBound + Float(f) * (range.upperBound - range.lowerBound)
                value = (v * 2).rounded() / 2
            })
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(value)) decibels")
        .accessibilityAdjustableAction { dir in value = min(12, max(-12, value + (dir == .increment ? 1 : -1))) }
    }
}

// MARK: - Storage

struct StorageView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var sizes: [(String, Int64, Color)] = []
    @State private var free: Int64 = 0
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var prefs = app.prefs
        let total = max(sizes.reduce(0) { $0 + $1.1 }, 1)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Fmt.bytes(sizes.reduce(0) { $0 + $1.1 })).font(.title.bold())
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(sizes, id: \.0) { s in
                                Rectangle().fill(s.2).frame(width: max(2, geo.size.width * CGFloat(Double(s.1) / Double(total))))
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 14)
                    ForEach(sizes, id: \.0) { s in
                        HStack { Circle().fill(s.2).frame(width: 10); Text(s.0); Spacer(); Text(Fmt.bytes(s.1)).foregroundStyle(.secondary) }.font(.subheadline)
                    }
                    Text("\(Fmt.bytes(free)) free on this iPhone").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
.themedRow()
            Section {
                Picker("Download quality", selection: $prefs.data.quality) {
                    Text("Best").tag(DownloadQuality.best)
                    Text("Save space").tag(DownloadQuality.saver)
                }
                Picker("Storage limit", selection: $prefs.data.storageLimitGB) {
                    Text("No limit").tag(0)
                    ForEach([2, 5, 10, 20, 50], id: \.self) { Text("\($0) GB").tag($0) }
                }
            } footer: { Text("Best is about 4 MB per song, Save space about half. When the limit is reached, new downloads wait.") }
.themedRow()
            Section {
                Toggle("Remove songs not played in 3 months", isOn: $prefs.data.autoRemoveUnplayed)
                Button("Clean up now") {
                    let before = app.library.entries.count
                    app.library.cleanUpUnplayed(stats: app.stats, protectedIDs: app.playlists.protectedSongIDs)
                    app.show("Removed \(before - app.library.entries.count) songs")
                    measure()
                }
            } footer: { Text("Liked songs and songs in playlists you keep downloaded are never removed.") }
.themedRow()
            Section {
                Button("Clear cache") {
                    try? FileManager.default.removeItem(at: Paths.cacheDir)
                    Paths.makeDir(Paths.cacheDir)
                    URLCache.shared.removeAllCachedResponses()
                    measure()
                    app.show("Cache cleared")
                }
                Button("Remove all downloads", role: .destructive) { confirmDeleteAll = true }
            }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { measure() }
        .confirmationDialog("Remove all \(app.library.entries.count) downloads?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Remove all", role: .destructive) {
                app.player.stop()
                app.library.deleteAll()
                measure()
            }
        } message: { Text("Your playlists, likes and stats stay. You can download the songs again later.") }
    }

    private func measure() {
        let accent = look.accent
        Task.detached(priority: .utility) {
            let audio = Paths.size(of: Paths.audioDir)
            let art = Paths.size(of: Paths.artDir)
            let cache = Paths.size(of: Paths.cacheDir)
            let data = Paths.size(of: Paths.dataDir)
            let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
            await MainActor.run {
                sizes = [("Music", audio, accent), ("Artwork", art, .orange), ("Cache", cache, .blue), ("Stats & settings", data, .purple)]
                free = freeBytes
            }
        }
    }
}

// MARK: - Backup

struct BackupView: View {
    @Environment(AppModel.self) private var app
    /// One file picker for the whole screen: SwiftUI only honors one `.fileImporter` per view.
    enum PickMode { case folder, restore, history }
    @State private var pickMode: PickMode = .folder
    @State private var picking = false
    @State private var restoreURL: URL?
    @State private var confirmReset = false

    var body: some View {
        @Bindable var prefs = app.prefs
        let backup = app.backup
        Form {
            Section {
                Button { pick(.folder) } label: {
                    LabeledContent("Backup folder", value: prefs.data.backupFolderName ?? "Choose…")
                }
                Button {
                    Task { await backup.backUpNow(); if backup.lastError == nil { app.show("Backed up") } }
                } label: {
                    HStack { Text("Back up now"); if backup.isWorking { Spacer(); ProgressView() } }
                }
                .disabled(prefs.data.backupBookmark == nil || backup.isWorking)
                if let last = prefs.data.lastBackup {
                    LabeledContent("Last backup", value: last.formatted(.relative(presentation: .named)))
                }
                if let err = backup.lastError { Text(err).font(.footnote).foregroundStyle(.red) }
            } header: { Text("Backup") } footer: {
                Text("Pick a folder in iCloud Drive or On My iPhone. Backups hold your library info, playlists, stats and settings, plus whatever you include below.")
            }
.themedRow()
            Section {
                Toggle("Back up automatically on Wi-Fi", isOn: $prefs.data.autoBackup)
                if prefs.data.autoBackup {
                    Picker("How often", selection: $prefs.data.backupFrequency) {
                        Text("Daily").tag(BackupFrequency.daily)
                        Text("Weekly").tag(BackupFrequency.weekly)
                    }
                    Stepper("Keep last \(prefs.data.backupKeep) backups", value: $prefs.data.backupKeep, in: 1...30)
                }
            }
.themedRow()
            Section {
                Toggle("Include my pictures", isOn: $prefs.data.backupImages)
                Toggle("Include songs from my files", isOn: $prefs.data.backupOwnFiles)
            } header: { Text("What to include") } footer: {
                Text("Pictures: your profile photo, playlist cover photos and covers you changed. Turn off to keep backups small. Songs from my files: the audio of songs you imported from your phone, saved in a \"Tunes Imported Songs\" folder next to the backups. They can't be downloaded again, so leave this on unless you have them elsewhere. Downloaded songs are never included; they download again after a restore.")
            }
.themedRow()
            Section {
                Button("Restore from a backup…") { pick(.restore) }
                if !backup.missingAfterRestore.isEmpty {
                    Button("Download \(backup.missingAfterRestore.count) missing songs") { backup.downloadMissing() }
                }
            } footer: { Text("Restoring replaces what's on this iPhone now.") }
.themedRow()

            Section {
                switch app.history.phase {
                case .idle:
                    Button("Import Spotify listening history…") { pick(.history) }
                case .reading:
                    HStack { ProgressView(); Text("Reading files…") }
                case .matching(let done, let total):
                    VStack(alignment: .leading) {
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                        Text("Matching songs to real artists… \(done) of \(total)").font(.caption)
                    }
                    Button("Cancel", role: .destructive) { app.history.cancel() }
                case .finished(let plays, let hours, let since, let unmatched):
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Imported \(plays) plays (\(Int(hours)) hours)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if let since { Text("Going back to \(since.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
                        if unmatched > 0 { Text("\(unmatched) plays couldn't be matched and were left out.").font(.caption).foregroundStyle(.secondary) }
                    }
                    Button("Import more") { pick(.history) }
                case .failed(let msg):
                    Text(msg).font(.footnote).foregroundStyle(.red)
                    Button("Try again") { pick(.history) }
                }
            } header: { Text("Spotify history") } footer: {
                Text("Request \"Extended streaming history\" at spotify.com → Account → Privacy. When the email arrives, save the .zip to Files, open it, and pick the Streaming_History_Audio .json files here. Plays count for the real artists. Importing twice won't double count.")
            }
.themedRow()
            Section {
                Button("Reset all stats", role: .destructive) { confirmReset = true }
            }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Backup & import")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: pickMode == .folder ? [.folder] : [.json],
                      allowsMultipleSelection: pickMode == .history) { r in
            guard case .success(let urls) = r, let first = urls.first else { return }
            switch pickMode {
            case .folder: backup.setFolder(first)
            case .restore: restoreURL = first
            case .history: app.history.start(files: urls)
            }
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { restoreURL != nil }, set: { if !$0 { restoreURL = nil } }), titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                guard let url = restoreURL else { return }
                restoreURL = nil
                app.player.stop()
                Task { await backup.restore(from: url) }
            }
        } message: { Text("Your current library info, playlists, stats and settings get replaced.") }
        .confirmationDialog("Reset all stats?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { app.stats.reset(); app.show("Stats reset") }
        } message: { Text("Listening time, plays and Wrapped start from zero. This can't be undone unless you restore a backup.") }
    }
}

extension BackupView {
    fileprivate func pick(_ mode: PickMode) {
        pickMode = mode
        picking = true
    }
}

// MARK: - Appearance

enum AppIcons {
    static let all: [(name: String, colors: [String])] = [
        ("Classic", ["#0B0B0F", "#34D399"]), ("Midnight", ["#1E1B4B", "#818CF8"]), ("Paper", ["#F5F5F4", "#1C1917"]),
        ("Sunset", ["#F97316", "#DB2777"]), ("Ocean", ["#0369A1", "#22D3EE"]), ("Vinyl", ["#111111", "#EF4444"]),
        ("Lime", ["#A3E635", "#14532D"]), ("Retro", ["#FDE68A", "#B45309"]), ("Grape", ["#7C3AED", "#F0ABFC"]),
        ("Mono", ["#FFFFFF", "#000000"]), ("Butter", ["#FEF3C7", "#F59E0B"]), ("Neon", ["#0F172A", "#FF00FF"])
    ]
}

struct AppearanceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    static let accents = ["#34D399", "#60A5FA", "#A78BFA", "#F472B6", "#F87171", "#FB923C", "#FACC15", "#E5E7EB"]

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                ThemeGrid()
                    .padding(.vertical, 6)
            } header: { Text("Theme") } footer: {
                Text("Dynamic takes its colors from the cover that's playing. Horizon follows the sky through the day: dawn, sunrise, day, golden hour, sunset, dusk and night. Gradient and animated themes pick a matching accent color, which you can change below (Dynamic and Horizon always use their own). Black is pure black, which saves battery on most iPhones. Animated themes hold still when Animations is off.")
            }
.themedRow()
            Section {
                HStack {
                    ColorPicker("Custom", selection: Binding(get: { Color(hex: prefs.data.accentHex) },
                                                             set: { prefs.data.accentHex = $0.hexString }), supportsOpacity: false)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Custom accent color")
                    ForEach(Self.accents, id: \.self) { hex in
                        Button { withAnimation { prefs.data.accentHex = hex }; app.haptic(.selection) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                                .overlay { if prefs.data.accentHex == hex { Circle().stroke(Color.primary, lineWidth: 2.5).padding(-4) } }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Accent \(hex)")
                    }
                }
                .padding(.vertical, 6)
            } header: { Text("Accent color") } footer: {
                Text("Used for buttons, switches, progress bars and highlights all over the app. The rainbow circle picks any color you like.")
            }
.themedRow()
            Section {
                StylePicker(title: "Player", options: PlayerStyle.allCases, selection: $prefs.data.playerStyle) { o in
                    Label(o.label, systemImage: o.icon)
                }
                StylePicker(title: "Progress bar", options: ProgressStyle.allCases, selection: $prefs.data.progressStyle) { o in
                    VStack(spacing: 6) {
                        ProgressBarArt(style: o, fraction: 0.6).frame(width: 64, height: 18)
                        Text(o.label).font(.caption2)
                    }
                }
                StylePicker(title: "Mini player", options: MiniPlayerStyle.allCases, selection: $prefs.data.miniPlayerStyle) { o in
                    Text(o.label)
                }
                StylePicker(title: "Font", options: AppFont.allCases, selection: $prefs.data.font) { o in
                    Text(o.label).font(.subheadline.weight(.semibold)).fontDesign(o.design).fontWidth(o.width)
                }
            } header: { Text("Style") } footer: {
                Text("Player: Vinyl spins while playing, and you can drag the record backwards or forwards to rewind or skip ahead. Cassette turns its reels. Minimal shows big text. Lyrics first fills the screen with lyrics. Mini player: the bar above the tabs while music plays.")
            }
            .themedRow()
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                    ForEach(AppIcons.all, id: \.name) { icon in
                        Button { setIcon(icon.name) } label: {
                            VStack(spacing: 5) {
                                Group {
                                    if let img = UIImage(named: "Preview\(icon.name)") {
                                        Image(uiImage: img).resizable()
                                    } else {
                                        LinearGradient(colors: icon.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    }
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    if prefs.data.appIcon == icon.name {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(look.accent, lineWidth: 3).padding(-4)
                                    }
                                }
                                Text(icon.name).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: { Text("App icon") } footer: {
                Text("Changes the icon on your Home Screen. iOS shows a short message confirming the change.")
            }
.themedRow()
            Section {
                Picker("Corners", selection: $prefs.data.corners) { ForEach(CornerStyle.allCases) { Text($0.label).tag($0) } }
                Picker("Artwork", selection: $prefs.data.artShape) { ForEach(ArtShape.allCases) { Text($0.label).tag($0) } }
                Picker("Text size", selection: $prefs.data.textSize) {
                    Text("Small").tag(TextSize.small); Text("Medium").tag(TextSize.medium); Text("Large").tag(TextSize.large)
                }
                Picker("Player background", selection: $prefs.data.playerBackground) { ForEach(PlayerBackground.allCases) { Text($0.label).tag($0) } }
            } header: { Text("Shapes & size") } footer: {
                Text("Corners: how round cards, tiles and panels are. Artwork: the shape of song and album covers. Text size: makes all text in Tunes bigger or smaller. Player background: what's behind the full-screen player (a color taken from the cover, a blurred cover, or plain).")
            }
.themedRow()
            Section {
                Toggle("Tab bar labels", isOn: $prefs.data.tabLabels)
                Toggle("Haptics", isOn: $prefs.data.haptics)
                Toggle("Animations", isOn: $prefs.data.animations)
            } header: { Text("Feel") } footer: {
                Text("Tab bar labels: shows the words Home, Library and Stats under the icons at the bottom. Haptics: the small vibrations when you tap buttons, like a song, flip a switch or finish a download. Animations: turn off for instant screen changes with no sliding or fading.")
            }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setIcon(_ name: String) {
        guard UIApplication.shared.supportsAlternateIcons else { app.show("Icons can't be changed on this install"); return }
        UIApplication.shared.setAlternateIconName(name == "Classic" ? nil : name) { error in
            Task { @MainActor in
                if let error { app.show("Couldn't change icon: \(error.localizedDescription)") }
                else { app.prefs.data.appIcon = name }
            }
        }
    }
}

/// Theme swatches in groups: a mini preview of each theme's background, a card and its accent.
struct ThemeGrid: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(ThemeMode.groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.0.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                        ForEach(group.1) { theme in cell(theme) }
                    }
                }
            }
        }
    }

    private func cell(_ theme: ThemeMode) -> some View {
        let selected = app.prefs.data.theme == theme
        return Button {
            withAnimation(.easeInOut(duration: 0.35)) {
                app.prefs.data.theme = theme
                if let a = theme.suggestedAccent { app.prefs.data.accentHex = a }
            }
            if theme == .dynamic { app.coverChanged() }
            app.mark("theme:\(theme.rawValue)")
            app.haptic(.selection)
        } label: {
            VStack(spacing: 5) {
                ThemeSwatch(theme: theme)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? look.accent : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1)
                            .padding(selected ? -3 : 0)
                    }
                Text(subtitle(theme)).font(.caption2.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.label) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func subtitle(_ t: ThemeMode) -> String {
        t == .horizon ? "Horizon · \(HorizonPhase.at(.now).label)" : t.label
    }
}

/// A tiny preview of a theme.
struct ThemeSwatch: View {
    let theme: ThemeMode
    @Environment(AppModel.self) private var app

    private var palette: ThemePalette? {
        switch theme {
        case .horizon: return HorizonPhase.at(.now).palette
        case .dynamic: return nil
        default: return theme.palette
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            sample
        }
    }

    @ViewBuilder private var backdrop: some View {
        switch theme {
        case .dark: Color(white: 0.075)
        case .black: Color.black
        case .light: Color(white: 0.97)
        case .auto: HStack(spacing: 0) { Color(white: 0.97); Color(white: 0.075) }
        case .dynamic: rainbow
        default:
            if let p = palette { paletteBackdrop(p) } else { Color.gray }
        }
    }

    /// A rainbow of covers, since Dynamic changes with every song.
    private var rainbow: some View {
        let hexes = ["#F43F5E", "#F59E0B", "#22C55E", "#06B6D4", "#8B5CF6", "#F43F5E"]
        return AngularGradient(colors: hexes.map { Color(hex: $0) }, center: .center)
            .blur(radius: 8)
            .overlay(Color.black.opacity(0.35))
    }

    @ViewBuilder private func paletteBackdrop(_ p: ThemePalette) -> some View {
        ZStack {
            if p.lights.count >= 2 {
                p.colors.first ?? .black
                Circle().fill(p.lights[0].opacity(0.65)).frame(width: 50).blur(radius: 14).offset(x: -14, y: -14)
                Circle().fill(p.lights[1].opacity(0.65)).frame(width: 44).blur(radius: 14).offset(x: 16, y: 6)
            } else {
                LinearGradient(colors: p.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let g = p.glow.first {
                    Circle().fill(g.opacity(0.5)).frame(width: 40).blur(radius: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            if p.stars { starDots }
            if p.grid { gridLines(p.glow.last ?? .cyan) }
        }
    }

    private var starDots: some View {
        let xs: [CGFloat] = [-22, -8, 6, 18, -16, 24]
        let ys: [CGFloat] = [-20, 12, -14, 18, 4, -4]
        return ZStack {
            ForEach(0..<6, id: \.self) { i in
                Circle().fill(.white).frame(width: 2, height: 2).offset(x: xs[i], y: ys[i])
            }
        }
    }

    private func gridLines(_ c: Color) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { _ in Rectangle().fill(c.opacity(0.5)).frame(height: 1) }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
    }

    private var sample: some View {
        let light = (palette?.scheme ?? theme.scheme) == .light
        let accent = palette?.accent ?? Color(hex: app.prefs.data.accentHex)
        return HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill((light ? Color.black : Color.white).opacity(0.18)).frame(width: 26, height: 8)
            Circle().fill(accent).frame(width: 9, height: 9)
        }
        .padding(7)
    }
}

/// A row of choices shown as tappable chips with a little preview each.
struct StylePicker<Option: Hashable & Identifiable, Preview: View>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    @ViewBuilder let preview: (Option) -> Preview
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { o in
                        let on = o == selection
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = o }
                            AppModel.shared.haptic(.selection)
                        } label: {
                            preview(o)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(minHeight: 40)
                                .background(on ? look.accent.opacity(0.22) : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? look.accent : .clear, lineWidth: 2))
                                .foregroundStyle(on ? look.accent : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Connections

struct ConnectionsView: View {
    @Environment(AppModel.self) private var app
    @State private var key = ""

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                comingLater("Discord", "gamecontroller.fill", "Show what you're listening to on your Discord profile.")
                comingLater("Last.fm", "dot.radiowaves.left.and.right", "Scrobble your plays to Last.fm.")
            } header: { Text("Sharing") } footer: {
                Text("These need a sign-in that isn't in this version yet. Private listening in your profile will control them once they arrive.")
            }
.themedRow()
            Section {
                SecureField("Ticketmaster API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { prefs.data.ticketmasterKey = key.trimmingCharacters(in: .whitespaces) }
                if key != prefs.data.ticketmasterKey {
                    Button("Save key") { prefs.data.ticketmasterKey = key.trimmingCharacters(in: .whitespaces); app.show("Saved") }
                }
                Picker("Your city", selection: $prefs.data.concertCity) {
                    ForEach(ConcertCity.all) { Text($0.name).tag($0) }
                }
                Stepper("Within \(prefs.data.concertRadiusKm) km", value: $prefs.data.concertRadiusKm, in: 25...2000, step: 25)
            } header: { Text("Shows on artist pages") } footer: {
                Text("Get a free key at developer.ticketmaster.com (My Apps → Consumer Key). It's stored only on this iPhone.")
            }
.themedRow()
        }
        .themedForm()
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { key = app.prefs.data.ticketmasterKey }
    }

    private func comingLater(_ name: String, _ icon: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Coming later").font(.caption.bold()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Customize Home

struct CustomizeHomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// True when shown on its own from Home (adds a Done button); false when pushed from Settings.
    var asSheet = false

    var body: some View {
        @Bindable var prefs = app.prefs
            List {
                Section {
                    ForEach($prefs.data.home) { $s in
                        HomeSectionRow(section: $s)
                    }
                    .onMove { prefs.data.home.move(fromOffsets: $0, toOffset: $1) }
                } footer: { Text("Drag to reorder. Turn off what you don't want to see. Tap the layout under a section's name to change how it looks and how many items it shows.") }
.themedRow()
                Section {
                    NavigationLink { BrowseChartsView() } label: {
                        LabeledContent("Charts on Home", value: "\(prefs.data.homeCharts.count)")
                    }
                }
.themedRow()
                Section {
                    Button("Reset to default") {
                        withAnimation { prefs.data.home = HomeSectionKind.allCases.map { HomeSection(kind: $0, visible: true) } }
                    }
                }
.themedRow()
            }
            .environment(\.editMode, .constant(.active))
            .themedForm()
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if asSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
    }
}

/// One Home section in Customize Home: on/off, plus a menu for its layout and size.
struct HomeSectionRow: View {
    @Binding var section: HomeSection
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.kind.icon).foregroundStyle(look.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.kind.title).foregroundStyle(section.visible ? Color.primary : Color.secondary).lineLimit(1)
                if section.kind.hasLayouts {
                    Menu {
                        Picker("Layout", selection: Binding(get: { section.effectiveLayout }, set: { section.layout = $0; section.count = nil })) {
                            ForEach(HomeLayout.allCases) { l in
                                Label { Text(l.label); Text(l.detail) } icon: { Image(systemName: l.icon) }.tag(l)
                            }
                        }
                        Picker("Show", selection: Binding(get: { section.effectiveCount }, set: { section.count = $0 })) {
                            ForEach(HomeLayout.countChoices, id: \.self) { Text("\($0) items").tag($0) }
                        }
                        .pickerStyle(.menu)
                        if section.layout != nil || section.count != nil {
                            Button("Back to default") { section.layout = nil; section.count = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: section.effectiveLayout.icon)
                            Text("\(section.effectiveLayout.label) · \(section.effectiveCount)")
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(look.accent)
                        .lineLimit(1)
                        .fixedSize()
                    }
                    .disabled(!section.visible)
                }
            }
            Spacer()
            SwitchKnob(isOn: $section.visible)
                .accessibilityLabel("Show \(section.kind.title)")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Profile

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @State private var photo: PhotosPickerItem?
    @State private var name = ""

    var body: some View {
        @Bindable var prefs = app.prefs
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            ProfileAvatar(size: 92).overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill").font(.title2).foregroundStyle(.white, look.accent)
                            }
                        }
                        TextField("Your name", text: $name)
                            .font(.title2.bold()).multilineTextAlignment(.center)
                            .onSubmit { prefs.data.name = name }
                        HStack(spacing: 8) {
                            ForEach(["#34D399", "#60A5FA", "#A78BFA", "#F472B6", "#FB923C", "#FACC15"], id: \.self) { hex in
                                Button {
                                    prefs.data.avatarHex = hex
                                    prefs.data.hasAvatarPhoto = false
                                } label: { Circle().fill(Color(hex: hex)).frame(width: 22, height: 22) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
.themedRow()
                Section {
                    HStack {
                        quickStat(Fmt.listening(app.stats.total(app.stats.records)), "listened")
                        quickStat("\(app.library.entries.count)", "songs")
                        quickStat("\(app.library.followed.count)", "following")
                    }
                    if let top = app.stats.topArtists(app.stats.records(.month), limit: 1).first {
                        Button { app.navigate(.artist(top.artist)) } label: {
                            HStack(spacing: 10) {
                                top.artist.picture(34)
                                VStack(alignment: .leading) {
                                    Text("Top artist this month").font(.caption).foregroundStyle(.secondary)
                                    Text(top.artist.name).foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    Button { app.sheet = nil; app.tab = .stats } label: { Label("See all your stats", systemImage: "chart.bar") }
                }
.themedRow()
                Section {
                    BadgeShelf(size: 56)
                    NavigationLink { BadgesView() } label: { Label("All badges", systemImage: "medal.fill") }
                } header: { Text("Badges") }
                .themedRow()
                Section {
                    Picker(selection: Binding(get: { privateChoice }, set: { setPrivate($0) })) {
                        Text("Off").tag(0); Text("1 hour").tag(1); Text("8 hours").tag(2); Text("Until tomorrow").tag(3); Text("Always").tag(4)
                    } label: {
                        Label("Private listening", systemImage: "eye.slash")
                    }
                    if case .until(let d) = prefs.data.privateMode, d > .now {
                        Text("Private until \(d.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Also leave it out of my stats", isOn: $prefs.data.privateSkipsStats)
                        .disabled(prefs.data.privateMode == .off)
                } footer: {
                    Text("While private, nothing you play is shared with connections. With the second switch on, it doesn't count in your stats or Wrapped either.")
                }
.themedRow()
                Section("Quick settings") {
                    Toggle(isOn: $prefs.data.offline) { Label("Offline mode", systemImage: "airplane") }
                    Toggle(isOn: $prefs.data.downloadWifiOnly) { Label("Download only on Wi-Fi", systemImage: "wifi") }
                    Toggle(isOn: $prefs.data.haptics) { Label("Haptics", systemImage: "hand.tap") }
                }
.themedRow()
                Section {
                    NavigationLink { ConnectionsView() } label: { Label("Connections", systemImage: "link") }
                    NavigationLink { AppearanceView() } label: { Label("Appearance", systemImage: "paintbrush") }
                    NavigationLink { BackupView() } label: { Label("Backup & import", systemImage: "externaldrive.badge.icloud") }
                    NavigationLink { SettingsView() } label: { Label("All settings", systemImage: "gearshape") }
                }
.themedRow()
            }
            .themedForm()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { prefs.data.name = name; dismiss() } } }
            .onAppear { name = prefs.data.name }
            .onDisappear { if prefs.data.name != name { prefs.data.name = name } }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                       let thumb = img.preparingThumbnail(of: CGSize(width: 400, height: 400 * img.size.height / max(img.size.width, 1))),
                       let jpg = thumb.jpegData(compressionQuality: 0.85) {
                        try? jpg.write(to: Paths.avatar, options: .atomic)
                        app.prefs.data.hasAvatarPhoto = true
                    }
                    photo = nil
                }
            }
        }
    }

    private var privateChoice: Int {
        switch app.prefs.data.privateMode {
        case .off: 0
        case .always: 4
        case .until(let d):
            if d <= .now { 0 } else if d.timeIntervalSinceNow <= 3_600 { 1 } else if d.timeIntervalSinceNow <= 8 * 3_600 { 2 } else { 3 }
        }
    }

    private func setPrivate(_ choice: Int) {
        let cal = Calendar.current
        switch choice {
        case 1: app.prefs.data.privateMode = .until(.now.addingTimeInterval(3_600))
        case 2: app.prefs.data.privateMode = .until(.now.addingTimeInterval(8 * 3_600))
        case 3:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now.addingTimeInterval(86_400)
            app.prefs.data.privateMode = .until(tomorrow)
        case 4: app.prefs.data.privateMode = .always
        default: app.prefs.data.privateMode = .off
        }
    }

    private func quickStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var name = ""
    @State private var step = 0
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            WrappedBackground(theme: WrappedTheme.all[2], seed: 3).ignoresSafeArea().opacity(0.9)
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                if step == 0 {
                    Group {
                        Image(systemName: "music.note.house.fill").font(.system(size: 56))
                        Text("Welcome to Tunes").font(.system(size: 44, weight: .black, design: .rounded))
                        Text("Search any song, download it, and it stays linked to the real artist, so your stats and Wrapped are actually yours.")
                            .font(.title3.weight(.medium)).opacity(0.9)
                        Label("Everything is customizable: Home, colors, icons, sound. Tap around.", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold)).opacity(0.85)
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    Group {
                        Text("What should we call you?").font(.system(size: 36, weight: .black, design: .rounded))
                        TextField("Your name", text: $name)
                            .font(.title2.bold())
                            .padding(16)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(finish)
                        Text("Only used for greetings and your Wrapped. It never leaves this iPhone.").font(.footnote).opacity(0.8)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
                Spacer()
                Button {
                    if step == 0 {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { step = 1 }
                        focused = true
                    } else { finish() }
                } label: {
                    Text(step == 0 ? "Get started" : (name.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Let's go"))
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 56)
                        .background(.white, in: Capsule()).foregroundStyle(.black)
                }
                .buttonStyle(PressStyle())
            }
            .foregroundStyle(.white)
            .padding(28)
        }
        .preferredColorScheme(.dark)
    }

    private func finish() {
        app.prefs.data.name = name.trimmingCharacters(in: .whitespaces)
        withAnimation { app.prefs.data.onboarded = true }
        app.haptic(.success)
    }
}
