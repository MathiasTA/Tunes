import Foundation
import Observation

/// Your playlists, auto playlists and charts.
@MainActor @Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    private(set) var refreshing: Set<UUID> = []
    private(set) var errors: [UUID: String] = [:]

    private let saveDebouncer = Debouncer(.milliseconds(500))
    static let colors = ["#334155", "#7C2D12", "#1E3A8A", "#14532D", "#6D28D9", "#9D174D", "#0E7490", "#A16207", "#3730A3", "#B91C1C"]

    init() {
        playlists = Store.load([Playlist].self, "playlists.json") ?? []
    }

    // MARK: Lookup

    func playlist(_ id: UUID) -> Playlist? { playlists.first { $0.id == id } }

    func chartPlaylist(_ source: ChartSource) -> Playlist? {
        playlists.first { if case .chart(let c) = $0.kind { return c.id == source.id } else { return false } }
    }

    var manual: [Playlist] { playlists.filter(\.isManual) }
    var autos: [Playlist] { playlists.filter(\.isAuto) }
    var charts: [Playlist] { playlists.filter(\.isChart) }

    /// Song ids that should never be auto-removed (in pinned or downloaded playlists).
    var protectedSongIDs: Set<Int> {
        Set(playlists.filter { $0.pinned || $0.keepDownloaded || $0.isManual }.flatMap { $0.songs.map(\.id) })
    }

    // MARK: Editing

    @discardableResult
    func create(name: String, songs: [Song] = []) -> Playlist {
        let p = Playlist(name: name, kind: .manual, songs: songs, colorHex: Self.colors[playlists.count % Self.colors.count])
        playlists.insert(p, at: 0)
        save()
        return p
    }

    @discardableResult
    func createAuto(name: String, rule: AutoRule, keepDownloaded: Bool = false) -> Playlist {
        var p = Playlist(name: name, kind: .auto(rule), colorHex: Self.colors[(playlists.count + 2) % Self.colors.count])
        p.keepDownloaded = keepDownloaded
        playlists.insert(p, at: 0)
        save()
        Task { await refresh(p.id, force: true) }
        return p
    }

    @discardableResult
    func ensureChart(_ source: ChartSource) -> Playlist {
        if let p = chartPlaylist(source) { return p }
        let p = Playlist(name: source.name, kind: .chart(source), colorHex: source.colorHex)
        playlists.append(p)
        save()
        Task { await refresh(p.id, force: true) }
        return p
    }

    func removeChart(_ source: ChartSource) {
        playlists.removeAll { if case .chart(let c) = $0.kind { return c.id == source.id } else { return false } }
        save()
    }

    func update(_ id: UUID, _ change: (inout Playlist) -> Void) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[i])
        save()
    }

    func add(_ songs: [Song], to id: UUID) {
        update(id) { p in
            for s in songs where !p.songs.contains(where: { $0.id == s.id }) { p.songs.append(s) }
        }
        if let p = playlist(id), p.keepDownloaded { AppModel.shared.library.downloadAll(songs) }
        AppModel.shared.haptic(.light)
    }

    func remove(songIDs: Set<Int>, from id: UUID) { update(id) { $0.songs.removeAll { songIDs.contains($0.id) } } }
    func move(in id: UUID, from: IndexSet, to: Int) { update(id) { $0.songs.move(fromOffsets: from, toOffset: to) } }
    func delete(_ id: UUID) { playlists.removeAll { $0.id == id }; save() }
    func togglePin(_ id: UUID) { update(id) { $0.pinned.toggle() } }

    func setKeepDownloaded(_ id: UUID, _ on: Bool) {
        update(id) { $0.keepDownloaded = on }
        if on, let p = playlist(id) { AppModel.shared.library.downloadAll(p.songs) }
    }

    func markPlayed(_ id: UUID) { update(id) { $0.lastPlayedAt = .now } }

    /// Song ids removed from the library are kept in playlists (they show as not downloaded).
    func replaceAll(_ new: [Playlist]) {
        playlists = new
        Store.saveNow(playlists, "playlists.json")
    }

    private func save() {
        saveDebouncer.run { [weak self] in
            guard let self else { return }
            Store.save(self.playlists, "playlists.json")
        }
    }

    func saveNow() { Store.saveNow(playlists, "playlists.json") }

    // MARK: Default playlists

    func createDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "createdDefaultPlaylists") else { return }
        UserDefaults.standard.set(true, forKey: "createdDefaultPlaylists")
        createAuto(name: "Fresh from your artists", rule: AutoRule(source: .newReleases, maxSongs: 30))
        createAuto(name: "On Repeat", rule: AutoRule(source: .mostPlayed, maxSongs: 30))
        createAuto(name: "Forgotten Favorites", rule: AutoRule(source: .forgotten, maxSongs: 30))
    }

    /// Makes sure every chart shown on Home has a playlist behind it.
    func syncHomeCharts(_ charts: [ChartSource]) {
        for c in charts where chartPlaylist(c) == nil { ensureChart(c) }
    }

    // MARK: Refreshing auto playlists and charts

    func refreshAll(force: Bool = false) async {
        for p in playlists where !p.isManual { await refresh(p.id, force: force) }
    }

    func refresh(_ id: UUID, force: Bool = false) async {
        guard let p = playlist(id), !p.isManual, !refreshing.contains(id) else { return }
        let app = AppModel.shared
        if !force, let last = p.refreshedAt, Date.now.timeIntervalSince(last) < 6 * 3600 { return }
        let needsNetwork: Bool = {
            if case .auto(let r) = p.kind { return r.source != .mostPlayed && r.source != .forgotten }
            return true
        }()
        if needsNetwork && (!app.network.isOnline || app.prefs.data.offline) { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do {
            let songs: [Song]
            switch p.kind {
            case .manual: return
            case .chart(let source): songs = try await ChartCatalog.songs(for: source)
            case .auto(let rule): songs = try await build(rule)
            }
            errors[id] = nil
            update(id) {
                $0.songs = songs
                $0.refreshedAt = .now
            }
            if let fresh = playlist(id), fresh.keepDownloaded { app.library.downloadAll(fresh.songs) }
        } catch {
            errors[id] = error.localizedDescription
        }
    }

    private func build(_ rule: AutoRule) async throws -> [Song] {
        let app = AppModel.shared
        let stats = app.stats
        let library = app.library
        switch rule.source {
        case .mostPlayed:
            let recent = stats.records(.month)
            return stats.topSongs(recent, limit: rule.maxSongs * 2).compactMap { library.entry($0.songID)?.song }.prefix(rule.maxSongs).map { $0 }

        case .forgotten:
            let cutoff = Date.now.addingTimeInterval(-60 * 86_400)
            let all = stats.topSongs(stats.records(.all), limit: 400)
            return all.filter { $0.plays >= 3 && (stats.lastPlayed($0.songID) ?? .distantPast) < cutoff }
                .compactMap { library.entry($0.songID)?.song }
                .prefix(rule.maxSongs).map { $0 }

        case .newReleases:
            var artists = rule.artists
            if artists.isEmpty {
                let top = stats.topArtists(stats.records(in: DateInterval(start: .now.addingTimeInterval(-90 * 86_400), end: .distantFuture)), limit: 12).map(\.artist)
                artists = top
                for f in library.followed where !artists.contains(where: { $0.id == f.id }) { artists.append(f) }
            }
            let cutoff = Date.now.addingTimeInterval(-Double(rule.withinWeeks) * 7 * 86_400)
            var songs: [Song] = []
            for artist in artists.prefix(25) {
                guard let albums = try? await Catalog.albums(artist: artist, limit: 15) else { continue }
                for album in albums where (album.releaseDay ?? .distantPast) >= cutoff {
                    if !rule.includeLiveAndRemixes && isLiveOrRemix(album.title) { continue }
                    guard let info = try? await Catalog.album(album.id) else { continue }
                    songs.append(contentsOf: info.1.filter { rule.includeLiveAndRemixes || !isLiveOrRemix($0.title) })
                }
            }
            var seen = Set<Int>()
            return songs.sorted { ($0.album?.releaseDate ?? "") > ($1.album?.releaseDate ?? "") }
                .filter { seen.insert($0.id).inserted }
                .prefix(rule.maxSongs).map { $0 }

        case .similar:
            var seeds = rule.artists
            if seeds.isEmpty { seeds = stats.topArtists(stats.records(.month), limit: 10).map(\.artist) }
            if seeds.isEmpty { seeds = library.followed }
            let seedIDs = Set(seeds.map(\.id))
            var picks: [[Song]] = []
            var used = Set<Int>()
            for seed in seeds.prefix(10) {
                guard let related = try? await Catalog.related(artistID: seed.id, limit: 6) else { continue }
                for a in related where !seedIDs.contains(a.id) && used.insert(a.id).inserted {
                    if let top = try? await Catalog.topSongs(artistID: a.id, limit: 3) {
                        picks.append(top.filter { rule.includeLiveAndRemixes || !isLiveOrRemix($0.title) })
                    }
                    if picks.count >= rule.maxSongs { break }
                }
            }
            // Interleave artists so the same one never plays twice in a row.
            var out: [Song] = []
            var round = 0
            while out.count < rule.maxSongs {
                var added = false
                for group in picks where round < group.count {
                    out.append(group[round])
                    added = true
                    if out.count >= rule.maxSongs { break }
                }
                if !added { break }
                round += 1
            }
            return out

        case .chart:
            guard let c = rule.chart else { return [] }
            return try await ChartCatalog.songs(for: c, limit: rule.maxSongs)
        }
    }

    private func isLiveOrRemix(_ title: String) -> Bool {
        let t = " " + title.normalizedForMatching + " "
        return [" live ", " remix ", " remixes ", " acoustic ", " instrumental ", " sped up ", " slowed "].contains { t.contains($0) }
    }
}
