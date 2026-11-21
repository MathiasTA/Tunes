import SwiftUI
import UIKit

// MARK: - Global sheets

enum AppSheet: Identifiable {
    case songMenu(Song, playlistID: UUID?)
    case addToPlaylist([Song])
    case share(Song)
    case edit(Int)
    case queue
    case lyrics
    case output
    case video(Song)
    case profile
    case importFiles
    case spotifyImport
    case createPlaylist
    case autoPlaylist(UUID?)
    case settings

    var id: String {
        switch self {
        case .songMenu(let s, _): "menu-\(s.id)"
        case .addToPlaylist(let s): "add-\(s.map(\.id))"
        case .share(let s): "share-\(s.id)"
        case .edit(let id): "edit-\(id)"
        case .queue: "queue"
        case .lyrics: "lyrics"
        case .output: "output"
        case .video(let s): "video-\(s.id)"
        case .profile: "profile"
        case .importFiles: "import"
        case .spotifyImport: "spotify"
        case .createPlaylist: "create"
        case .autoPlaylist(let id): "auto-\(id?.uuidString ?? "new")"
        case .settings: "settings"
        }
    }
}

// MARK: - Images

/// Memory cache + downsampling, so lists scroll smoothly.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 400 }

    func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func remove(_ url: URL) {
        for size in [48, 96, 144, 240, 400, 600, 900, 1200] { cache.removeObject(forKey: "\(url.absoluteString)@\(size)" as NSString) }
    }

    func image(local: URL?, remote: URL?, maxPixel: CGFloat) async -> UIImage? {
        let bucket = [48, 96, 144, 240, 400, 600, 900, 1200].first { CGFloat($0) >= maxPixel } ?? 1200
        if let local {
            let key = "\(local.absoluteString)@\(bucket)"
            if let hit = cached(key) { return hit }
            if FileManager.default.fileExists(atPath: local.path) {
                let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let full = UIImage(contentsOfFile: local.path) else { return nil }
                    return full.preparingThumbnail(of: Self.fit(full.size, CGFloat(bucket))) ?? full
                }.value
                if let img { cache.setObject(img, forKey: key as NSString); return img }
            }
        }
        guard let remote else { return nil }
        let key = "\(remote.absoluteString)@\(bucket)"
        if let hit = cached(key) { return hit }
        guard let result = try? await URLSession.shared.data(from: remote) else { return nil }
        let data = result.0
        let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let full = UIImage(data: data) else { return nil }
            return full.preparingThumbnail(of: Self.fit(full.size, CGFloat(bucket))) ?? full
        }.value
        if let img { cache.setObject(img, forKey: key as NSString) }
        return img
    }

    private static func fit(_ size: CGSize, _ maxPixel: CGFloat) -> CGSize {
        let scale = min(1, maxPixel / max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

struct Artwork: View {
    var url: URL?
    var local: URL? = nil
    var size: CGFloat
    var circle = false
    var seed = 0
    var symbol = "music.note"
    @Environment(\.look) private var look
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Palette.color(for: seed).opacity(0.55)
                Image(systemName: circle ? "person.fill" : symbol)
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: circle ? size / 2 : look.artRadius(size: size), style: .continuous))
        .task(id: "\(local?.path ?? "")|\(url?.absoluteString ?? "")|\(Int(size))") {
            if let hit = await ImageCache.shared.image(local: local, remote: url, maxPixel: size * scale) {
                withAnimation(.easeOut(duration: 0.2)) { image = hit }
            }
        }
    }
}

extension Song {
    func artwork(_ size: CGFloat) -> Artwork { Artwork(url: artworkURL, local: localArtworkURL, size: size, seed: id) }
}

extension Artist {
    func picture(_ size: CGFloat) -> Artwork { Artwork(url: pictureURL, local: localPictureURL, size: size, circle: true, seed: id) }
}

extension Album {
    func cover(_ size: CGFloat) -> Artwork { Artwork(url: coverURL, size: size, seed: id, symbol: "opticaldisc") }
}

/// A playlist tile: its own color with a few words, like the mockup.
struct PlaylistTile: View {
    let playlist: Playlist
    var size: CGFloat
    @Environment(\.look) private var look

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: playlist.colorHex)
            if size > 70 {
                Text(playlist.name)
                    .font(.system(size: size * 0.13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(size * 0.08)
            } else {
                Image(systemName: playlist.isChart ? "list.number" : (playlist.isAuto ? "sparkles" : "music.note.list"))
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let badge = playlist.badge, size > 70 {
                Text(badge)
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(7)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: look.artRadius(size: size) == size / 2 ? 12 : look.artRadius(size: size), style: .continuous))
    }
}

struct LikedTile: View {
    var size: CGFloat
    @Environment(\.look) private var look
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#9D174D"), Color(hex: "#6D28D9")], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "heart.fill").font(.system(size: size * 0.38)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: look.radius(8), style: .continuous))
    }
}

// MARK: - Song row

/// Tap plays (if downloaded) or plays the 30-second preview; the arrow downloads; ··· opens the menu.
struct SongRow: View {
    let song: Song
    var queue: [Song] = []
    var context = ""
    var playlistID: UUID? = nil
    var trackNumber: Int? = nil
    var showArtwork = true
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    private var downloaded: Bool { app.library.isDownloaded(song.id) }
    private var isCurrent: Bool { app.player.currentID == song.id }
    private var isPreviewing: Bool { app.player.previewingID == song.id }
    private var shown: Song { app.library.resolved(song) }

    var body: some View {
        HStack(spacing: 12) {
            if let trackNumber {
                Text("\(trackNumber)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 26)
            } else if showArtwork {
                shown.artwork(48)
                    .overlay {
                        if isPreviewing {
                            RoundedRectangle(cornerRadius: look.artRadius(size: 48)).fill(.black.opacity(0.5))
                            Image(systemName: "waveform").foregroundStyle(.white).symbolEffect(.variableColor.iterative)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(shown.title).lineLimit(1)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(look.accent) : AnyShapeStyle(.primary))
                    if shown.explicit { Image(systemName: "e.square.fill").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(subtitle).font(.caption).lineLimit(1)
                    .foregroundStyle(isPreviewing ? AnyShapeStyle(look.accent) : AnyShapeStyle(.secondary))
                if case .failed(let msg) = app.library.states[song.id] {
                    Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if isCurrent && app.player.isPlaying {
                Image(systemName: "waveform").foregroundStyle(look.accent).symbolEffect(.variableColor.iterative)
            }
            DownloadButton(song: song)
            Button { app.sheet = .songMenu(shown, playlistID: playlistID) } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 30, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More options for \(shown.title)")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .contextMenu { SongContextMenu(song: shown, playlistID: playlistID) }
    }

    private var subtitle: String {
        if isPreviewing { return "Playing preview…" }
        switch app.library.states[song.id] {
        case .some(.queued): return "Waiting to download…"
        case .some(.waiting(let why)): return why
        case .some(.matching): return "Finding the song…"
        case .some(.downloading(let p)): return p > 0.02 ? "Downloading… \(Int(p * 100))%" : "Downloading…"
        default: break
        }
        if trackNumber != nil { return Fmt.time(shown.duration) }
        return "\(shown.artistLine) · \(Fmt.time(shown.duration))"
    }

    private func tap() {
        if downloaded {
            let source = queue.isEmpty ? [song] : queue
            app.player.play(source, startAt: source.firstIndex { $0.id == song.id } ?? 0, context: context.isEmpty ? song.title : context, playlistID: playlistID)
        } else if app.prefs.data.offline {
            app.show("Offline mode is on")
        } else {
            app.player.togglePreview(shown)
        }
    }
}

struct SongContextMenu: View {
    let song: Song
    var playlistID: UUID? = nil
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.library.isDownloaded(song.id) {
            Button { app.player.playNext(song) } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { app.player.addToQueue(song) } label: { Label("Add to queue", systemImage: "text.badge.plus") }
        } else {
            Button { app.library.download(song) } label: { Label("Download", systemImage: "arrow.down.circle") }
        }
        Button { app.sheet = .addToPlaylist([song]) } label: { Label("Add to playlist", systemImage: "plus.square.on.square") }
        Button { app.library.toggleLike(song) } label: {
            Label(app.library.isLiked(song.id) ? "Remove from Liked" : "Like", systemImage: app.library.isLiked(song.id) ? "heart.slash" : "heart")
        }
        Button { app.sheet = .share(song) } label: { Label("Share", systemImage: "square.and.arrow.up") }
    }
}

struct DownloadButton: View {
    let song: Song
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        Group {
            if app.library.isDownloaded(song.id) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(look.accent).transition(.scale.combined(with: .opacity))
            } else {
                switch app.library.states[song.id] {
                case .some(.downloading(let p)):
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2.5)
                        Circle().trim(from: 0, to: max(0.05, p)).stroke(look.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.3), value: p)
                    }
                    .frame(width: 20, height: 20)
                case .some(.queued), .some(.matching):
                    ProgressView().controlSize(.small)
                case .some(.waiting):
                    Image(systemName: "clock").foregroundStyle(.secondary)
                case .some(.failed):
                    Button { app.library.download(song) } label: { Image(systemName: "arrow.clockwise.circle").foregroundStyle(.orange) }
                        .buttonStyle(.plain)
                case .none:
                    Button { app.library.download(song) } label: { Image(systemName: "arrow.down.circle").foregroundStyle(look.accent) }
                        .buttonStyle(.plain)
                        .disabled(song.id < 0)
                }
            }
        }
        .font(.title3)
        .frame(width: 34, height: 44)
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.35), value: app.library.isDownloaded(song.id))
        .accessibilityLabel(app.library.isDownloaded(song.id) ? "Downloaded" : "Download")
    }
}

// MARK: - Tiles & shelves

struct SongCard: View {
    let song: Song
    var size: CGFloat = 140
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                song.artwork(size)
                Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(song.artistLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
        }
        .buttonStyle(PressStyle())
    }
}

struct ArtistCircle: View {
    let artist: Artist
    var size: CGFloat = 96
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            artist.picture(size)
            Text(artist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(width: size + 8)
    }
}

struct AlbumTile: View {
    let album: Album
    var size: CGFloat = 140
    var badge: String? = nil
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            album.cover(size)
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge).font(.system(size: 10, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(look.accent, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.black).padding(8)
                    }
                }
            Text(album.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text([album.artist?.name, album.year, album.recordType?.capitalized].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size, alignment: .leading)
    }
}

struct AlbumRow: View {
    let album: Album
    var body: some View {
        HStack(spacing: 12) {
            album.cover(52)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).lineLimit(1)
                Text([album.artist?.name, album.year].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct Shelf<Content: View>: View {
    let title: String
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                if let trailing { trailing }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) { content }
                    .padding(.horizontal)
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// Buttons shrink a little when pressed, so everything feels responsive.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct PillButton: View {
    let title: String
    var icon: String? = nil
    var prominent = false
    let action: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.subheadline.weight(prominent ? .bold : .semibold))
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(prominent ? AnyShapeStyle(look.accent) : AnyShapeStyle(Color.secondary.opacity(0.18)), in: Capsule())
            .foregroundStyle(prominent ? AnyShapeStyle(Color.black) : AnyShapeStyle(.primary))
        }
        .buttonStyle(PressStyle())
    }
}

struct Chip: View {
    let title: String
    var selected: Bool
    let action: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).frame(height: 32)
                .background(selected ? AnyShapeStyle(look.accent) : AnyShapeStyle(Color.secondary.opacity(0.16)), in: Capsule())
                .foregroundStyle(selected ? AnyShapeStyle(Color.black) : AnyShapeStyle(.primary))
        }
        .buttonStyle(PressStyle())
        .animation(.spring(duration: 0.25), value: selected)
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 8, y: 3)
    }
}

/// A banner when the user is offline or in offline mode.
struct OfflineBanner: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        if app.prefs.data.offline || !app.network.isOnline {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash").foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.prefs.data.offline ? "Offline mode" : "You're offline").font(.subheadline.bold())
                    Text("Only your \(app.library.entries.count) downloaded songs are shown").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if app.prefs.data.offline {
                    Button("Go online") { withAnimation { app.prefs.data.offline = false } }
                        .font(.subheadline.bold()).buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                }
            }
            .padding(12)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: look.radius(14)))
            .overlay(RoundedRectangle(cornerRadius: look.radius(14)).stroke(Color.yellow.opacity(0.35)))
        }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary).tracking(0.6)
    }
}
