import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Mini player

struct MiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        if let song = app.player.currentSong, !app.showPlayer {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    song.artwork(42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(song.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    Button { app.player.togglePlayPause() } label: {
                        Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2).frame(width: 44, height: 44)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(app.player.isPlaying ? "Pause" : "Play")
                    Button { app.player.next() } label: { Image(systemName: "forward.fill").font(.title3).frame(width: 40, height: 44) }
                        .disabled(!app.player.hasNext)
                        .accessibilityLabel("Next song")
                }
                .foregroundStyle(.primary)
                .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 8)
                GeometryReader { geo in
                    Capsule().fill(look.accent)
                        .frame(width: geo.size.width * progress, height: 2)
                }
                .frame(height: 2)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: look.radius(14), style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { app.showPlayer = true }
            .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                if v.translation.height < -30 { app.showPlayer = true }
                else if v.translation.width < -50 { app.player.next() }
                else if v.translation.width > 50 { app.player.previous() }
            })
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var progress: CGFloat {
        let d = app.player.duration
        return d > 0 ? CGFloat(min(1, app.player.elapsed / d)) : 0
    }
}

// MARK: - Full player

struct FullPlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var scrub: Double?
    @State private var dragOffset: CGFloat = 0
    @State private var coverColor: Color = .gray
    @State private var lyrics: Lyrics = .none

    var body: some View {
        GeometryReader { geo in
            let artSize = min(geo.size.width - 48, geo.size.height * 0.4)
            ZStack {
                background
                if let entry = app.player.current {
                    VStack(spacing: 0) {
                        topBar
                        Spacer(minLength: 12)
                        entry.song.artwork(artSize)
                            .scaleEffect(app.player.isPlaying ? 1 : 0.88)
                            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: app.player.isPlaying)
                            .id(entry.id)
                            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                        Spacer(minLength: 16)
                        titleRow(entry.song)
                        scrubber.padding(.top, 14)
                        controls.padding(.top, 4)
                        bottomRow.padding(.top, 8)
                        if app.prefs.data.lyricsEnabled && !lyrics.lines.isEmpty { lyricsPeek.padding(.top, 10) }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, geo.safeAreaInsets.top > 0 ? 0 : 20)
                }
            }
            .offset(y: max(0, dragOffset))
            .gesture(
                DragGesture()
                    .onChanged { v in if v.translation.height > 0 { dragOffset = v.translation.height } }
                    .onEnded { v in
                        if v.translation.height > 140 || v.predictedEndTranslation.height > 300 {
                            app.showPlayer = false
                        }
                        withAnimation(.spring(duration: 0.35)) { dragOffset = 0 }
                    }
            )
        }
        .animation(.spring(duration: 0.4), value: app.player.currentID)
        .task(id: app.player.currentID) { await loadForCurrent() }
    }

    private func loadForCurrent() async {
        guard let e = app.player.current else { return }
        if let c = await DominantColor.color(for: e.song) { withAnimation(.easeInOut(duration: 0.6)) { coverColor = c } }
        lyrics = .none
        if app.prefs.data.lyricsEnabled {
            if let cached = LyricsService.cached(e.id) { lyrics = cached }
            else if app.network.isOnline && !app.prefs.data.offline { lyrics = await LyricsService.fetch(e.song) }
        }
    }

    @ViewBuilder private var background: some View {
        switch look.playerBackground {
        case .coverColor:
            LinearGradient(colors: [coverColor.opacity(0.85), Surface.background(look)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        case .blur:
            ZStack {
                Surface.background(look)
                if let s = app.player.currentSong {
                    s.artwork(500).blur(radius: 60).opacity(0.6).ignoresSafeArea()
                }
            }
            .ignoresSafeArea()
        case .plain:
            Surface.background(look).ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            Button { app.showPlayer = false } label: { Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("Close player")
            Spacer()
            VStack(spacing: 1) {
                Text("PLAYING FROM").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.6)
                Text(app.player.contextName).font(.footnote.weight(.bold)).lineLimit(1)
            }
            .onTapGesture {
                if let id = app.player.contextPlaylistID { app.navigate(.playlist(id)) }
            }
            Spacer()
            Button {
                if let s = app.player.currentSong { app.sheet = .songMenu(s, playlistID: nil) }
            } label: { Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("Song options")
        }
        .foregroundStyle(.primary)
    }

    private func titleRow(_ song: Song) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(.title2.bold()).lineLimit(1)
                Button { app.navigate(.artist(song.artist)) } label: {
                    Text(song.artistLine).font(.body).foregroundStyle(.secondary).lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            .contentTransition(.opacity)
            Spacer()
            let liked = app.library.isLiked(song.id)
            Button { app.library.toggleLike(song) } label: {
                Image(systemName: liked ? "heart.fill" : "heart").font(.title2)
                    .foregroundStyle(liked ? look.accent : .primary)
                    .symbolEffect(.bounce, value: liked)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(liked ? "Remove from Liked songs" : "Like")
        }
    }

    private var scrubber: some View {
        let p = app.player
        let shown = scrub ?? p.elapsed
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let frac = p.duration > 0 ? CGFloat(min(1, max(0, shown / p.duration))) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.2)).frame(height: scrub == nil ? 4 : 8)
                    Capsule().fill(Color.primary).frame(width: geo.size.width * frac, height: scrub == nil ? 4 : 8)
                    Circle().fill(Color.primary).frame(width: scrub == nil ? 12 : 18, height: scrub == nil ? 12 : 18)
                        .offset(x: geo.size.width * frac - (scrub == nil ? 6 : 9))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = min(1, max(0, v.location.x / max(geo.size.width, 1)))
                        withAnimation(.spring(duration: 0.2)) { scrub = Double(f) * p.duration }
                    }
                    .onEnded { _ in
                        if let s = scrub { p.seek(to: p.start + s) }
                        app.haptic(.selection)
                        withAnimation(.spring(duration: 0.25)) { scrub = nil }
                    })
            }
            .frame(height: 22)
            HStack {
                Text(Fmt.time(shown))
                Spacer()
                Text("-" + Fmt.time(max(0, p.duration - shown)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(Fmt.time(shown)) of \(Fmt.time(p.duration))")
        .accessibilityAdjustableAction { dir in
            p.seek(to: p.position + (dir == .increment ? 10 : -10))
        }
    }

    private var controls: some View {
        let p = app.player
        return HStack {
            Button { p.toggleShuffle() } label: {
                Image(systemName: "shuffle").font(.title3).foregroundStyle(p.shuffle ? look.accent : .primary)
                    .overlay(alignment: .bottom) { if p.shuffle { Circle().fill(look.accent).frame(width: 4, height: 4).offset(y: 10) } }
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(p.shuffle ? "Shuffle on" : "Shuffle off")
            Spacer()
            Button { p.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 30)).frame(width: 56, height: 56) }
                .accessibilityLabel("Previous")
            Spacer()
            Button { p.togglePlayPause(); app.haptic(.light) } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32)).foregroundStyle(Surface.background(look))
                    .frame(width: 76, height: 76)
                    .background(Color.primary, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(p.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { p.next() } label: { Image(systemName: "forward.fill").font(.system(size: 30)).frame(width: 56, height: 56) }
                .disabled(!p.hasNext)
                .accessibilityLabel("Next")
            Spacer()
            Button { p.cycleRepeat() } label: {
                Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat").font(.title3)
                    .foregroundStyle(p.repeatMode == .off ? .primary : look.accent)
                    .overlay(alignment: .bottom) { if p.repeatMode != .off { Circle().fill(look.accent).frame(width: 4, height: 4).offset(y: 10) } }
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel("Repeat \(p.repeatMode.rawValue)")
        }
        .foregroundStyle(.primary)
    }

    private var bottomRow: some View {
        HStack(spacing: 4) {
            Button { app.sheet = .output } label: {
                Label(app.player.routeName, systemImage: app.player.outputKind == .headphones ? "headphones" : (app.player.outputKind == .speakers ? "hifispeaker.fill" : "iphone"))
                    .font(.footnote.weight(.semibold)).lineLimit(1)
                    .foregroundStyle(app.player.outputKind == .phone ? AnyShapeStyle(.secondary) : AnyShapeStyle(look.accent))
            }
            Spacer()
            if let sleep = app.player.sleepAt {
                Text(sleep, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(look.accent)
            }
            Button { app.sheet = .lyrics } label: { Image(systemName: "quote.bubble").frame(width: 44, height: 44) }
                .accessibilityLabel("Lyrics")
            Button { if let s = app.player.currentSong { app.sheet = .video(s) } } label: { Image(systemName: "play.rectangle").frame(width: 44, height: 44) }
                .accessibilityLabel("Watch video")
            Button { app.sheet = .queue } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }
                .accessibilityLabel("Queue")
        }
        .font(.title3)
        .foregroundStyle(.primary)
    }

    private var lyricsPeek: some View {
        let offset = app.player.current?.lyricsOffset ?? 0
        let idx = lyrics.index(at: app.player.position + offset) ?? -1
        let lines = lyrics.lines
        let first = max(0, idx)
        return Button { app.sheet = .lyrics } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lyrics").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(0..<2, id: \.self) { k in
                    let i = first + k
                    if i < lines.count {
                        Text(lines[i].text.isEmpty ? "♪" : lines[i].text)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(k == 0 && idx >= 0 ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(coverColor.opacity(0.35), in: RoundedRectangle(cornerRadius: look.radius(14)))
            .animation(.easeInOut(duration: 0.3), value: idx)
        }
        .buttonStyle(PressStyle())
    }
}

/// Average color of a song's artwork, for the player background.
enum DominantColor {
    @MainActor private static var cache: [Int: Color] = [:]

    @MainActor
    static func color(for song: Song) async -> Color? {
        if let c = cache[song.id] { return c }
        guard let img = await ImageCache.shared.image(local: song.localArtworkURL, remote: song.artworkURL, maxPixel: 96),
              let cg = img.cgImage else { return nil }
        let color = await Task.detached(priority: .utility) { () -> Color? in
            let ci = CIImage(cgImage: cg)
            let f = CIFilter.areaAverage()
            f.inputImage = ci
            f.extent = ci.extent
            guard let out = f.outputImage else { return nil }
            var px = [UInt8](repeating: 0, count: 4)
            CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return Color(red: Double(px[0]) / 255, green: Double(px[1]) / 255, blue: Double(px[2]) / 255)
        }.value
        if let color { cache[song.id] = color }
        return color
    }
}

// MARK: - Queue

struct QueueView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @State private var savedName = ""
    @State private var showSave = false

    var body: some View {
        let p = app.player
        NavigationStack {
            List {
                if let s = p.currentSong {
                    Section {
                        HStack(spacing: 12) {
                            s.artwork(48)
                            VStack(alignment: .leading) {
                                Text(s.title).foregroundStyle(look.accent).lineLimit(1)
                                Text(s.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if p.isPlaying { Image(systemName: "waveform").foregroundStyle(look.accent).symbolEffect(.variableColor.iterative) }
                        }
                    } header: { SectionLabel(text: "Now playing") }
                }
                if !p.userQueue.isEmpty {
                    Section {
                        ForEach(Array(p.userQueue.enumerated()), id: \.offset) { i, id in
                            if let s = app.library.entry(id)?.song { queueRow(s) }
                        }
                        .onDelete { $0.sorted(by: >).forEach { p.removeFromQueue(userIndex: $0) } }
                        .onMove { p.moveUserQueue(from: $0, to: $1) }
                    } header: {
                        HStack { SectionLabel(text: "Next in queue"); Spacer(); Button("Clear") { p.clearUserQueue() }.font(.caption.bold()) }
                    }
                }
                Section {
                    ForEach(Array(p.upcomingContext.enumerated()), id: \.offset) { i, id in
                        if let s = app.library.entry(id)?.song {
                            queueRow(s).contentShape(Rectangle()).onTapGesture { p.jumpToContext(offset: i) }
                        }
                    }
                    .onMove { p.moveContext(from: $0, to: $1) }
                    if p.upcomingContext.isEmpty { Text("Nothing more after this.").font(.footnote).foregroundStyle(.secondary) }
                } header: { SectionLabel(text: "Next from: \(p.contextName)") }
            }
            .environment(\.editMode, .constant(.active))
            .themedForm()
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom) { controls }
            .alert("Save queue as playlist", isPresented: $showSave) {
                TextField("Name", text: $savedName)
                Button("Save") {
                    let ids = (p.currentID.map { [$0] } ?? []) + p.userQueue + p.upcomingContext
                    let songs = ids.compactMap { app.library.entry($0)?.song }
                    app.playlists.create(name: savedName.isEmpty ? "Saved queue" : savedName, songs: songs)
                    app.show("Saved as a playlist")
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func queueRow(_ s: Song) -> some View {
        HStack(spacing: 12) {
            s.artwork(44)
            VStack(alignment: .leading) {
                Text(s.title).lineLimit(1)
                Text(s.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var controls: some View {
        let p = app.player
        return HStack {
            control(p.shuffle ? "Shuffle on" : "Shuffle", "shuffle", on: p.shuffle) { p.toggleShuffle() }
            control(p.repeatMode == .off ? "Repeat" : (p.repeatMode == .one ? "Repeat 1" : "Repeat all"), p.repeatMode == .one ? "repeat.1" : "repeat", on: p.repeatMode != .off) { p.cycleRepeat() }
            Menu {
                Button("Off") { p.setSleep(minutes: nil) }
                Button("End of song") { p.setSleepAtEndOfSong() }
                ForEach([5, 15, 30, 45, 60, 90], id: \.self) { m in Button("\(m) minutes") { p.setSleep(minutes: m) } }
            } label: {
                controlLabel(p.sleepAt != nil ? "Sleep on" : (p.sleepAtEndOfSong ? "End of song" : "Sleep"), "moon.zzz", on: p.sleepAt != nil || p.sleepAtEndOfSong)
            }
            control("Save as playlist", "text.badge.plus", on: false) { savedName = ""; showSave = true }
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }

    private func control(_ title: String, _ icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { controlLabel(title, icon, on: on) }.buttonStyle(.plain)
    }

    private func controlLabel(_ title: String, _ icon: String, on: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(on ? look.accent : .primary)
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}

// MARK: - Lyrics

struct LyricsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @State private var lyrics: Lyrics?
    @State private var color: Color = .indigo

    private func lineOpacity(_ i: Int, current: Int?, synced: Bool) -> Double {
        guard synced, let current else { return synced ? 0.45 : 1 }
        if i == current { return 1 }
        return i < current ? 0.45 : 0.3
    }

    var body: some View {
        let p = app.player
        let offset = p.current?.lyricsOffset ?? 0
        let current = lyrics?.index(at: p.position + offset)
        ZStack {
            color.opacity(0.9).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    if let s = p.currentSong {
                        s.artwork(44)
                        VStack(alignment: .leading) {
                            Text(s.title).font(.headline).lineLimit(1)
                            Text(s.artistLine).font(.subheadline).opacity(0.75).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.bold()).frame(width: 44, height: 44) }
                        .accessibilityLabel("Close lyrics")
                }
                if let lyrics {
                    if lyrics.instrumental {
                        Spacer(); Text("Instrumental").font(.title.bold()); Spacer()
                    } else if lyrics.lines.isEmpty {
                        Spacer(); Text("No lyrics found for this song.").font(.title3.bold()); Spacer()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 18) {
                                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                                        Text(line.text.isEmpty ? "• • •" : line.text)
                                            .font(.system(size: 28, weight: .heavy))
                                            .opacity(lineOpacity(i, current: current, synced: lyrics.synced))
                                            .scaleEffect(i == current ? 1.0 : 0.97, anchor: .leading)
                                            .id(i)
                                            .onTapGesture { if let t = line.time { p.seek(to: t - offset) } }
                                    }
                                }
                                .padding(.vertical, 120)
                                .animation(.spring(duration: 0.4), value: current)
                            }
                            .onChange(of: current) { _, new in
                                if let new { withAnimation(.spring(duration: 0.6)) { proxy.scrollTo(new, anchor: .center) } }
                            }
                        }
                        if lyrics.synced, let id = p.currentID {
                            HStack {
                                Text(lyrics.synced ? "Synced lyrics · LRCLIB" : "Lyrics · LRCLIB").font(.caption2).opacity(0.7)
                                Spacer()
                                Button("−0.5s") { app.library.update(id) { $0.lyricsOffset -= 0.5 } }
                                Text(String(format: "%+.1fs", offset)).font(.caption.monospacedDigit()).frame(width: 50)
                                Button("+0.5s") { app.library.update(id) { $0.lyricsOffset += 0.5 } }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Spacer(); ProgressView().tint(.white); Spacer()
                }
            }
            .padding(.horizontal, 22).padding(.top, 16)
            .foregroundStyle(.white)
        }
        .task(id: p.currentID) {
            guard let s = p.currentSong else { lyrics = Lyrics.none; return }
            if let c = await DominantColor.color(for: s) { withAnimation { color = c } }
            if let cached = LyricsService.cached(s.id) { lyrics = cached; return }
            if app.network.isOnline && !app.prefs.data.offline { lyrics = await LyricsService.fetch(s) } else { lyrics = Lyrics.none }
        }
    }
}

// MARK: - Output picker

struct RoutePicker: UIViewRepresentable {
    var tint: UIColor
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        v.activeTintColor = tint
        v.tintColor = .label
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { uiView.activeTintColor = tint }
}

struct OutputView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: app.player.outputKind == .headphones ? "headphones" : (app.player.outputKind == .speakers ? "hifispeaker.2.fill" : "iphone"))
                            .font(.title2).foregroundStyle(.black).frame(width: 48, height: 48).background(look.accent, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Playing on").font(.caption).foregroundStyle(.secondary)
                            Text(app.player.routeName).font(.headline)
                        }
                        Spacer()
                    }
                }
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose a device").font(.headline)
                            Text("AirPods, Bluetooth headphones and speakers, AirPlay").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        RoutePicker(tint: UIColor(look.accent)).frame(width: 44, height: 44)
                    }
                } footer: {
                    Text("Google Home and Nest speakers work over Bluetooth: pair them once in the Google Home app, then pick them here.")
                }
                Section {
                    NavigationLink {
                        SoundSettingsView()
                    } label: {
                        HStack {
                            Text("Sound profile for \(app.player.outputKind.label.lowercased())")
                            Spacer()
                            Text(app.prefs.data.eqProfile(app.player.outputKind).preset.label).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .themedForm()
            .navigationTitle("Play on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { app.player.updateRoute() }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Video

struct VideoPlayerView: View {
    let song: Song
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var askData = false
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    Color.black
                    if let player {
                        VideoPlayer(player: player)
                    } else if loading {
                        ProgressView().tint(.white)
                    } else if let error {
                        Text(error).foregroundStyle(.white).padding()
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.title3.bold())
                    Text(song.artistLine).foregroundStyle(.secondary)
                    Text("Streamed from YouTube in standard quality, never saved. Your music pauses while you watch.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                Spacer()
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Play video on mobile data?", isPresented: $askData) {
                Button("Play video") { Task { await load() } }
                Button("Not now", role: .cancel) { dismiss() }
            } message: {
                Text("You're not on Wi-Fi. A music video uses roughly \(estimate) MB.")
            }
            .task {
                if app.network.onMobileData { askData = true } else { await load() }
            }
            .onDisappear { player?.pause() }
        }
    }

    private var estimate: Int { max(5, Int((song.duration > 0 ? song.duration : 220) * 0.07)) }

    private func load() async {
        guard app.network.isOnline && !app.prefs.data.offline else { error = "You're offline."; return }
        loading = true
        defer { loading = false }
        app.player.pause()
        do {
            var videoID = app.library.entry(song.id)?.youTubeID
            if videoID == nil { videoID = try await Matcher.match(song).best.id }
            guard let id = videoID else { throw YouTubeError.noVideo }
            let url = try await YouTubeMedia.videoURL(videoID: id, allowRemote: app.prefs.data.allowRemoteExtraction)
            let p = AVPlayer(url: url)
            player = p
            p.play()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
