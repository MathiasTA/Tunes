import Foundation
import Observation

/// Everything except the audio files, in one JSON file.
struct BackupFile: Codable {
    var version = 1
    var createdAt = Date.now
    var prefs: PrefsData
    var library: [LibraryEntry]
    var followed: [Artist]
    var playlists: [Playlist]
    var plays: [PlayRecord]
}

@MainActor @Observable
final class BackupManager {
    private(set) var isWorking = false
    private(set) var lastError: String?
    private(set) var missingAfterRestore: [Song] = []

    // MARK: Folder

    func setFolder(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            lastError = "Couldn't use that folder."
            return
        }
        AppModel.shared.prefs.data.backupBookmark = data
        AppModel.shared.prefs.data.backupFolderName = url.lastPathComponent
        lastError = nil
    }

    private func resolveFolder() -> URL? {
        guard let data = AppModel.shared.prefs.data.backupBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            AppModel.shared.prefs.data.backupBookmark = fresh
        }
        return url
    }

    // MARK: Backing up

    func backUpNow() async {
        let app = AppModel.shared
        guard let folder = resolveFolder() else { lastError = "Choose a backup folder first."; return }
        isWorking = true
        defer { isWorking = false }
        app.stats.flush()
        var prefs = app.prefs.data
        prefs.backupBookmark = nil
        let file = BackupFile(prefs: prefs, library: app.library.entries, followed: app.library.followed,
                              playlists: app.playlists.playlists, plays: app.stats.records)
        let keep = app.prefs.data.backupKeep
        do {
            let data = try Store.encoder.encode(file)
            try await Task.detached(priority: .utility) {
                let access = folder.startAccessingSecurityScopedResource()
                defer { if access { folder.stopAccessingSecurityScopedResource() } }
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH.mm"
                let url = folder.appending(path: "Tunes Backup \(f.string(from: .now)).json")
                try data.write(to: url, options: .atomic)
                // Keep only the newest backups.
                let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
                let backups = all.filter { $0.lastPathComponent.hasPrefix("Tunes Backup ") && $0.pathExtension == "json" }
                    .sorted { $0.lastPathComponent > $1.lastPathComponent }
                for old in backups.dropFirst(max(1, keep)) { try? FileManager.default.removeItem(at: old) }
            }.value
            app.prefs.data.lastBackup = .now
            lastError = nil
        } catch {
            lastError = "Backup failed: \(error.localizedDescription)"
        }
    }

    /// Runs on launch and when the app goes to the background.
    func autoBackupIfDue() {
        let app = AppModel.shared
        let p = app.prefs.data
        guard p.autoBackup, p.backupBookmark != nil, app.network.isWiFi, !isWorking else { return }
        if let last = p.lastBackup, Date.now.timeIntervalSince(last) < p.backupFrequency.interval { return }
        Task { await backUpNow() }
    }

    // MARK: Restoring

    func restore(from url: URL) async {
        let app = AppModel.shared
        isWorking = true
        defer { isWorking = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let file = try Store.decoder.decode(BackupFile.self, from: data)
            app.player.stop()
            var prefs = file.prefs
            prefs.backupBookmark = app.prefs.data.backupBookmark
            prefs.backupFolderName = app.prefs.data.backupFolderName
            prefs.onboarded = true
            app.prefs.data = prefs
            app.library.restore(entries: file.library, followed: file.followed)
            app.playlists.replaceAll(file.playlists)
            app.stats.replaceAll(file.plays)
            missingAfterRestore = file.library.filter { !app.library.isDownloaded($0.id) && $0.id > 0 }.map(\.song)
            lastError = nil
        } catch {
            lastError = "Couldn't restore: \(error.localizedDescription)"
        }
    }

    func downloadMissing() {
        AppModel.shared.library.downloadAll(missingAfterRestore)
        missingAfterRestore = []
    }
}

/// Imports Spotify's listening history into your stats, matched to real artists.
@MainActor @Observable
final class HistoryImporter {
    enum Phase: Equatable {
        case idle
        case reading
        case matching(done: Int, total: Int)
        case finished(plays: Int, hours: Double, since: Date?, unmatched: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase { case .reading, .matching: true; default: false }
    }

    func start(files: [URL]) {
        guard !isRunning else { return }
        phase = .reading
        task = Task { await run(files) }
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    private func run(_ files: [URL]) async {
        var plays: [HistoryPlay] = []
        for url in files {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "json", let data = try? Data(contentsOf: url) else { continue }
            if let parsed = try? SpotifyImport.parseHistory(data) { plays.append(contentsOf: parsed) }
        }
        guard !plays.isEmpty else {
            phase = .failed("No listening history found. Pick the .json files from Spotify's export (open the .zip in Files first).")
            return
        }
        // Match each distinct song once.
        struct Key: Hashable { let t: String; let a: String }
        var unique: [Key: (String, String)] = [:]
        for p in plays { unique[Key(t: p.title.lowercased(), a: p.artist.lowercased())] = (p.title, p.artist) }
        var matched: [Key: Song] = [:]
        var done = 0
        let total = unique.count
        phase = .matching(done: 0, total: total)
        for (key, value) in unique {
            if Task.isCancelled { return }
            if let local = AppModel.shared.library.find(title: value.0, artist: value.1) {
                matched[key] = local.song
            } else {
                switch await CatalogMatcher.find(title: value.0, artist: value.1, duration: nil) {
                case .match(let s): matched[key] = s
                case .unsure(let best, _): matched[key] = best
                case .notFound: break
                }
            }
            done += 1
            if done % 5 == 0 || done == total { phase = .matching(done: done, total: total) }
        }
        // Skip plays already imported before (same song + start time).
        let existing = Set(AppModel.shared.stats.records.filter { $0.origin == .spotify }.map { "\($0.songID)-\(Int($0.start.timeIntervalSince1970))" })
        var records: [PlayRecord] = []
        var unmatched = 0
        for p in plays {
            guard let song = matched[Key(t: p.title.lowercased(), a: p.artist.lowercased())] else { unmatched += 1; continue }
            let key = "\(song.id)-\(Int(p.start.timeIntervalSince1970))"
            if existing.contains(key) { continue }
            records.append(PlayRecord(songID: song.id, title: song.title, artist: song.artist, others: song.featured,
                                      artworkURL: song.artworkURL, genre: song.album?.genre,
                                      releaseYear: song.album?.year.flatMap { Int($0) }, start: p.start,
                                      seconds: p.seconds, origin: .spotify))
        }
        AppModel.shared.stats.addImported(records)
        let hours = records.reduce(0) { $0 + $1.seconds } / 3600
        phase = .finished(plays: records.count, hours: hours, since: records.map(\.start).min(), unmatched: unmatched)
    }
}
