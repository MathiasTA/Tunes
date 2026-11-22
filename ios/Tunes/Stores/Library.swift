import Foundation
import Observation
import UIKit

enum DownloadState: Equatable {
    case queued
    case waiting(String)
    case matching
    case downloading(Double)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .queued, .waiting, .matching, .downloading: true
        case .failed: false
        }
    }
}

/// Everything saved on the phone: downloaded and imported songs, likes, followed artists.
@MainActor @Observable
final class Library {
    private(set) var entries: [LibraryEntry] = []
    private(set) var followed: [Artist] = []
    private(set) var states: [Int: DownloadState] = [:]
    private(set) var version = 0

    /// Songs that were asked to download and haven't finished (including failed ones), so the
    /// downloads screen can show them even though they aren't in the library yet.
    private(set) var jobs: [Int: Song] = [:]
    /// The YouTube video each failed song last tried, and which step failed.
    private(set) var lastTried: [Int: VideoCandidate] = [:]
    private(set) var failedStep: [Int: String] = [:]
    /// Progress of the current batch: resets when a download starts after everything had finished.
    private(set) var batchTotal = 0
    private(set) var batchDone = 0

    @ObservationIgnored private var index: [Int: Int] = [:]
    @ObservationIgnored private var pending: [(song: Song, video: VideoCandidate?)] = []
    @ObservationIgnored private var active = 0
    private let saveDebouncer = Debouncer(.milliseconds(500))

    init() {
        entries = (Store.load([LibraryEntry].self, "library.json") ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        followed = Store.load([Artist].self, "following.json") ?? []
        reindex()
    }

    // MARK: Queries

    func entry(_ id: Int) -> LibraryEntry? { index[id].map { entries[$0] } }
    func isDownloaded(_ id: Int) -> Bool { index[id] != nil }
    var songs: [Song] { entries.map(\.song) }
    var liked: [LibraryEntry] { entries.filter(\.liked) }
    func isLiked(_ id: Int) -> Bool { entry(id)?.liked ?? false }
    func songs(byArtist id: Int) -> [Song] { entries.filter { e in e.song.allArtists.contains { $0.id == id } }.map(\.song) }
    func isFollowing(_ id: Int) -> Bool { followed.contains { $0.id == id } }

    /// The library copy of a song if we have it (it has the user's edits), else the song itself.
    func resolved(_ song: Song) -> Song { entry(song.id)?.song ?? song }

    /// Finds an already-downloaded song by title and artist (for imports).
    func find(title: String, artist: String) -> LibraryEntry? {
        let t = CatalogMatcher.stripExtras(title).normalizedForMatching, a = artist.normalizedForMatching
        return entries.first { e in
            CatalogMatcher.stripExtras(e.song.title).normalizedForMatching == t &&
                e.song.allArtists.contains { $0.name.normalizedForMatching == a }
        }
    }

    struct ArtistEntry: Identifiable, Hashable {
        let artist: Artist
        let count: Int
        let imported: Int
        var id: Int { artist.id }
    }

    var artists: [ArtistEntry] {
        var counts: [Int: (Artist, Int, Int)] = [:]
        for e in entries {
            for a in e.song.allArtists {
                let cur = counts[a.id] ?? (a, 0, 0)
                let isFile: Bool = { if case .file = e.source { return true } else { return false } }()
                counts[a.id] = (cur.0.pictureURL == nil ? a : cur.0, cur.1 + 1, cur.2 + (isFile ? 1 : 0))
            }
        }
        return counts.values.map { ArtistEntry(artist: $0.0, count: $0.1, imported: $0.2) }
            .sorted { $0.artist.name.localizedCaseInsensitiveCompare($1.artist.name) == .orderedAscending }
    }

    var reviewCount: Int { entries.filter(\.needsReview).count }

    // MARK: Download overview

    var activeCount: Int { states.values.filter(\.isActive).count }
    var failedIDs: [Int] {
        states.filter { if case .failed = $0.value { return true } else { return false } }.map(\.key).sorted()
    }
    var activeIDs: [Int] { states.compactMap { $0.value.isActive ? $0.key : nil }.sorted() }

    /// 0...1 across the whole batch, counting partial progress of songs downloading right now.
    var batchProgress: Double {
        guard batchTotal > 0 else { return 0 }
        let partial = states.values.reduce(0.0) { sum, st in
            if case .downloading(let p) = st { return sum + p } else { return sum }
        }
        return min(1, (Double(batchDone) + partial) / Double(batchTotal))
    }

    func failureReason(_ id: Int) -> String? {
        if case .failed(let why) = states[id] { return why }
        return nil
    }

    func retryAllFailed() {
        for id in failedIDs { if let song = jobs[id] { download(song) } }
    }

    func clearFailed() {
        for id in failedIDs {
            states[id] = nil
            jobs[id] = nil
            lastTried[id] = nil
            failedStep[id] = nil
        }
    }

    // MARK: Downloading

    func download(_ song: Song, video: VideoCandidate? = nil) {
        guard !isDownloaded(song.id), song.id > 0 else { return }
        if let s = states[song.id], s.isActive { return }
        if activeCount == 0 { batchTotal = 0; batchDone = 0 }
        batchTotal += 1
        jobs[song.id] = song
        failedStep[song.id] = nil
        states[song.id] = .queued
        pending.append((song, video))
        pump()
    }

    func downloadAll(_ songs: [Song]) { for s in songs where !isDownloaded(s.id) { download(s) } }

    func cancelDownload(_ id: Int) {
        let wasQueued = pending.contains { $0.song.id == id }
        pending.removeAll { $0.song.id == id }
        switch states[id] {
        case .some(.queued), .some(.waiting), .some(.failed):
            states[id] = nil
            jobs[id] = nil
            if wasQueued { batchTotal = max(batchDone, batchTotal - 1) }
        default: break
        }
    }

    /// Called when the network changes or settings change.
    func pump() {
        let app = AppModel.shared
        let net = app.network
        let prefs = app.prefs.data
        if !net.isOnline || prefs.offline {
            for p in pending { states[p.song.id] = .waiting(prefs.offline ? "Waiting: offline mode is on" : "Waiting for internet") }
            return
        }
        if prefs.downloadWifiOnly && !net.isWiFi {
            for p in pending { states[p.song.id] = .waiting("Waiting for Wi-Fi") }
            return
        }
        if prefs.storageLimitGB > 0, Paths.size(of: Paths.audioDir) > Int64(prefs.storageLimitGB) * 1_000_000_000 {
            for p in pending { states[p.song.id] = .failed("Storage limit reached") }
            pending.removeAll()
            return
        }
        while active < 3, !pending.isEmpty {
            let next = pending.removeFirst()
            active += 1
            Task {
                await perform(next.song, video: next.video)
                active -= 1
                pump()
            }
        }
    }

    private func perform(_ song: Song, video: VideoCandidate?) async {
        let id = song.id
        var step = "search"
        do {
            states[id] = .matching
            var candidate: VideoCandidate
            var confident = true
            if let video {
                candidate = video
            } else {
                let m = try await Matcher.match(song)
                candidate = m.best
                confident = m.confident
            }
            lastTried[id] = candidate
            step = "download"
            states[id] = .downloading(0)
            let fileName = "\(id).m4a"
            let dest = Paths.audioDir.appending(path: fileName)
            let prefs = AppModel.shared.prefs.data
            try await YouTubeMedia.downloadAudio(videoID: candidate.id, to: dest, saveSpace: prefs.quality == .saver,
                                                 allowRemote: prefs.allowRemoteExtraction) { p in
                Task { @MainActor in AppModel.shared.library.setProgress(id, p) }
            }
            var full = song
            if full.album?.genre == nil, let albumID = full.album?.id, albumID > 0,
               let info = try? await Catalog.album(albumID) {
                full.album?.genre = info.0.genre
                if full.album?.releaseDate == nil { full.album?.releaseDate = info.0.releaseDate }
            }
            await fetchArtwork(for: full)
            var entry = LibraryEntry(song: full, source: .youtube(videoID: candidate.id, title: "\(candidate.title) · \(candidate.channel)"), fileName: fileName)
            entry.needsReview = !confident
            insert(entry)
            states[id] = nil
            jobs[id] = nil
            lastTried[id] = nil
            batchDone += 1
            analyze(id)
            AppModel.shared.haptic(.success)
        } catch is CancellationError {
            states[id] = nil
            jobs[id] = nil
        } catch {
            failedStep[id] = step
            states[id] = .failed(error.localizedDescription)
            batchDone += 1
        }
    }

    fileprivate func setProgress(_ id: Int, _ p: Double) {
        if case .downloading = states[id] { states[id] = .downloading(p) }
    }

    /// Downloads again from a specific YouTube upload (used by "Wrong song? Change source").
    func redownload(_ id: Int, video: VideoCandidate) async throws {
        guard var e = entry(id) else { return }
        states[id] = .downloading(0)
        defer { if case .downloading = states[id] { states[id] = nil } }
        let fileName = "\(id).m4a"
        let tmp = Paths.audioDir.appending(path: "\(id)-new.m4a")
        let prefs = AppModel.shared.prefs.data
        try await YouTubeMedia.downloadAudio(videoID: video.id, to: tmp, saveSpace: prefs.quality == .saver, allowRemote: prefs.allowRemoteExtraction) { p in
            Task { @MainActor in AppModel.shared.library.setProgress(id, p) }
        }
        if e.fileName != fileName { try? FileManager.default.removeItem(at: e.fileURL) }
        let dest = Paths.audioDir.appending(path: fileName)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        e.fileName = fileName
        e.source = .youtube(videoID: video.id, title: "\(video.title) · \(video.channel)")
        e.trimStart = 0
        e.trimEnd = nil
        e.needsReview = false
        e.loudnessDB = nil
        replace(e)
        analyze(id)
    }

    // MARK: Importing files

    /// Copies an audio file into the library. `song` may be a catalog song (then it counts as that real song)
    /// or a local-only song with a negative id.
    @discardableResult
    func importFile(_ url: URL, as song: Song, artworkData: Data?) throws -> LibraryEntry {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        let fileName = "\(song.id).\(ext)"
        let dest = Paths.audioDir.appending(path: fileName)
        if let old = entry(song.id), old.fileName != fileName { try? FileManager.default.removeItem(at: old.fileURL) }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: url, to: dest)
        var e = LibraryEntry(song: song, source: .file(originalName: url.lastPathComponent), fileName: fileName)
        if let artworkData {
            try? artworkData.write(to: song.localArtworkURL, options: .atomic)
            e.hasCustomArtwork = true
        }
        if let old = entry(song.id) { e.liked = old.liked; e.addedAt = old.addedAt; replace(e) } else { insert(e) }
        states[song.id] = nil
        jobs[song.id] = nil
        lastTried[song.id] = nil
        failedStep[song.id] = nil
        if artworkData == nil { Task { await fetchArtwork(for: song) } }
        analyze(song.id)
        return e
    }

    /// Replaces a song's audio with a file the user picked.
    func replaceAudio(_ id: Int, with url: URL) throws {
        guard var e = entry(id) else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        let fileName = "\(id).\(ext)"
        let dest = Paths.audioDir.appending(path: fileName)
        try? FileManager.default.removeItem(at: e.fileURL)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: url, to: dest)
        e.fileName = fileName
        e.source = .file(originalName: url.lastPathComponent)
        e.trimStart = 0
        e.trimEnd = nil
        e.needsReview = false
        e.loudnessDB = nil
        replace(e)
        analyze(id)
    }

    // MARK: Editing

    func update(_ id: Int, _ change: (inout LibraryEntry) -> Void) {
        guard let i = index[id] else { return }
        change(&entries[i])
        version += 1
        save()
    }

    func toggleLike(_ song: Song) {
        if isDownloaded(song.id) {
            update(song.id) { $0.liked.toggle() }
        } else {
            // Liking something you don't have yet downloads it, then marks it liked.
            likeAfterDownload.insert(song.id)
            download(song)
        }
        AppModel.shared.haptic(.light)
    }

    @ObservationIgnored private var likeAfterDownload = Set<Int>()

    func setArtwork(_ id: Int, data: Data) {
        guard let e = entry(id) else { return }
        try? data.write(to: e.song.localArtworkURL, options: .atomic)
        update(id) { $0.hasCustomArtwork = true }
        ImageCache.shared.remove(e.song.localArtworkURL)
    }

    func setArtwork(_ id: Int, url: URL) async {
        guard let e = entry(id) else { return }
        try? await Net.download(from: url, to: e.song.localArtworkURL)
        update(id) { $0.hasCustomArtwork = true }
        ImageCache.shared.remove(e.song.localArtworkURL)
    }

    func delete(_ ids: [Int]) {
        for id in ids {
            guard let e = entry(id) else { continue }
            try? FileManager.default.removeItem(at: e.fileURL)
            try? FileManager.default.removeItem(at: e.song.localArtworkURL)
            LyricsService.clearCache(id)
        }
        entries.removeAll { ids.contains($0.id) }
        reindex()
        save()
    }

    func deleteAll() { delete(entries.map(\.id)) }

    func toggleFollow(_ artist: Artist) {
        if isFollowing(artist.id) {
            followed.removeAll { $0.id == artist.id }
        } else {
            followed.insert(artist, at: 0)
            if let pic = artist.pictureURL { Task { try? await Net.download(from: pic, to: artist.localPictureURL) } }
        }
        Store.save(followed, "following.json")
        AppModel.shared.haptic(.light)
    }

    /// Restores from a backup: metadata only; audio files are matched by id if still present.
    func restore(entries new: [LibraryEntry], followed f: [Artist]) {
        let present = new.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        entries = present.sorted { $0.addedAt > $1.addedAt }
        followed = f
        reindex()
        Store.saveNow(entries, "library.json")
        Store.saveNow(followed, "following.json")
    }

    // MARK: Housekeeping

    func cleanUpUnplayed(stats: StatsStore, protectedIDs: Set<Int>) {
        let cutoff = Date.now.addingTimeInterval(-90 * 86_400)
        let stale = entries.filter { e in
            guard !e.liked, !protectedIDs.contains(e.id), e.addedAt < cutoff else { return false }
            if case .file = e.source { return false }
            return (stats.lastPlayed(e.id) ?? .distantPast) < cutoff
        }.map(\.id)
        if !stale.isEmpty { delete(stale) }
    }

    var audioBytes: Int64 { Paths.size(of: Paths.audioDir) }

    // MARK: Internals

    private func insert(_ e: LibraryEntry) {
        var e = e
        if likeAfterDownload.remove(e.id) != nil { e.liked = true }
        entries.insert(e, at: 0)
        reindex()
        save()
    }

    private func replace(_ e: LibraryEntry) {
        if let i = index[e.id] { entries[i] = e } else { entries.insert(e, at: 0) }
        reindex()
        save()
    }

    private func reindex() {
        index = Dictionary(entries.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        version += 1
    }

    private func save() {
        saveDebouncer.run { [weak self] in
            guard let self else { return }
            Store.save(self.entries, "library.json")
        }
    }

    func saveNow() { Store.saveNow(entries, "library.json") }

    private func fetchArtwork(for song: Song) async {
        if let art = song.artworkURL, !FileManager.default.fileExists(atPath: song.localArtworkURL.path) {
            try? await Net.download(from: art, to: song.localArtworkURL)
        }
        for a in song.allArtists {
            if let pic = a.pictureURL, !FileManager.default.fileExists(atPath: a.localPictureURL.path) {
                try? await Net.download(from: pic, to: a.localPictureURL)
            }
        }
    }

    /// Measures loudness, the catchiest part, and silence; runs in the background.
    func analyze(_ id: Int) {
        guard let e = entry(id) else { return }
        let url = e.fileURL
        Task {
            guard let a = await AudioAnalysis.analyze(url) else { return }
            AnalysisCache.save(a, id: id)
            update(id) { entry in
                entry.loudnessDB = a.loudnessDB
                entry.highlightStart = a.highlightStart
                if a.duration > 0 && entry.song.duration <= 0 { entry.song.duration = a.duration }
            }
        }
    }

    /// Re-analyzes songs that never got analyzed (e.g. after an update).
    func analyzeMissing() {
        for e in entries where e.loudnessDB == nil { analyze(e.id) }
    }
}

/// Keeps waveform data for the trim screen.
enum AnalysisCache {
    private static func url(_ id: Int) -> URL {
        Paths.makeDir(Paths.cacheDir.appending(path: "Analysis", directoryHint: .isDirectory)).appending(path: "\(id).json")
    }
    static func save(_ a: AudioAnalysis, id: Int) {
        if let d = try? JSONEncoder().encode(a) { try? d.write(to: url(id)) }
    }
    static func load(_ id: Int) -> AudioAnalysis? {
        (try? Data(contentsOf: url(id))).flatMap { try? JSONDecoder().decode(AudioAnalysis.self, from: $0) }
    }
}
