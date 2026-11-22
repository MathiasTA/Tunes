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

    /// Three daily mixes, made once (also for people who already had the other default playlists).
    func createDailyMixesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "createdDailyMixes") else { return }
        UserDefaults.standard.set(true, forKey: "createdDailyMixes")
        for n in 1...3 {
            var rule = AutoRule(source: .dailyMix, maxSongs: 40)
            rule.mix = n
            let p = createAuto(name: "Daily Mix \(n)", rule: rule)
            if let i = playlists.firstIndex(where: { $0.id == p.id }) {
                let moved = playlists.remove(at: i)
                playlists.insert(moved, at: min(n - 1, playlists.count))
            }
        }
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
        if !force, let last = p.refreshedAt {
            if case .auto(let r) = p.kind, r.source == .dailyMix {
                if Calendar.current.isDateInToday(last) { return } // daily mixes change once a day
            } else if Date.now.timeIntervalSince(last) < 6 * 3600 {
                return
            }
        }
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
            let mixName = dailyMixName(for: p, songs: songs)
            update(id) {
                $0.songs = songs
                $0.refreshedAt = .now
                if let mixName { $0.name = mixName }
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
        case .dailyMix:
            return try await buildDailyMix(rule)

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

    /// Built around your Nth most played artist (last two months): about 40% songs you already love by them and
    /// their circle, 60% top songs from them and similar artists. Shuffled with today's date, so it changes daily.
    private func buildDailyMix(_ rule: AutoRule) async throws -> [Song] {
        let app = AppModel.shared
        let stats = app.stats, library = app.library
        let recent = stats.records(in: DateInterval(start: .now.addingTimeInterval(-60 * 86_400), end: .distantFuture))
        var seeds = stats.topArtists(recent, limit: 6).map(\.artist).filter { $0.id > 0 }
        for f in library.followed where !seeds.contains(where: { $0.id == f.id }) { seeds.append(f) }
        let n = max(1, rule.mix ?? 1)
        guard seeds.count >= n else { return [] }
        let seed = seeds[n - 1]

        let related = (try? await Catalog.related(artistID: seed.id, limit: 8)) ?? []
        let circle = [seed] + related
        let circleIDs = Set(circle.map(\.id))
        let day = Int(Date.now.timeIntervalSince1970 / 86_400)
        var rng = SeededRNG(seed: UInt64(day * 31 + n))

        // Songs you already have and play, by this circle of artists.
        let playCounts = Dictionary(stats.topSongs(stats.records(.all), limit: 1000).map { ($0.songID, $0.plays) }, uniquingKeysWith: +)
        var favorites = library.entries.map(\.song).filter { s in s.allArtists.contains { circleIDs.contains($0.id) } }
        favorites.sort { (playCounts[$0.id] ?? 0) > (playCounts[$1.id] ?? 0) }
        favorites = Array(favorites.prefix(rule.maxSongs)).shuffled(using: &rng)

        // New finds: popular songs of the seed and similar artists.
        var finds: [Song] = []
        for a in circle.prefix(7) {
            if let top = try? await Catalog.topSongs(artistID: a.id, limit: 5) {
                finds += top.filter { !isLiveOrRemix($0.title) }
            }
        }
        finds.shuffle(using: &rng)

        let wantFavorites = min(favorites.count, Int(Double(rule.maxSongs) * 0.4))
        var picked: [Song] = Array(favorites.prefix(wantFavorites))
        var seen = Set(picked.map(\.id))
        for s in finds where picked.count < rule.maxSongs && seen.insert(s.id).inserted { picked.append(s) }
        for s in favorites.dropFirst(wantFavorites) where picked.count < rule.maxSongs && seen.insert(s.id).inserted { picked.append(s) }
        picked.shuffle(using: &rng)

        // Spread artists out so the same one doesn't play twice in a row when it can be avoided.
        var out: [Song] = []
        var rest = picked
        while !rest.isEmpty {
            let last = out.last?.artist.id
            let i = rest.firstIndex { $0.artist.id != last } ?? 0
            out.append(rest.remove(at: i))
        }
        return out
    }

    /// "Daily Mix 1 · Artist" so you can tell the mixes apart. Left alone if you renamed it.
    private func dailyMixName(for p: Playlist, songs: [Song]) -> String? {
        guard case .auto(let r) = p.kind, r.source == .dailyMix, p.name.hasPrefix("Daily Mix") else { return nil }
        let base = "Daily Mix \(r.mix ?? 1)"
        var counts: [String: Int] = [:]
        for s in songs { counts[s.artist.name, default: 0] += 1 }
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return base }
        return "\(base) · \(top)"
    }

    private func isLiveOrRemix(_ title: String) -> Bool {
        let t = " " + title.normalizedForMatching + " "
        return [" live ", " remix ", " remixes ", " acoustic ", " instrumental ", " sped up ", " slowed "].contains { t.contains($0) }
    }
}
