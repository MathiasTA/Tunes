import Foundation
import Observation
import SwiftUI
import UIKit

enum Haptic { case light, medium, success, warning, selection }

/// Owns every store. Created once when the app starts.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let prefs = Prefs()
    let network = NetworkMonitor()
    let stats = StatsStore()
    let library = Library()
    let playlists = PlaylistStore()
    let player = Player()
    let backup = BackupManager()
    let history = HistoryImporter()
    let wrappedAudio = WrappedAudio()

    enum Tab: Hashable { case home, library, stats, games }

    var tab: Tab = .home
    var homePath: [Route] = []
    var libraryPath: [Route] = []
    var statsPath: [Route] = []
    var gamesPath: [Route] = []
    /// Bumped when the Games tab is tapped while already at its top page (scroll up).
    var gamesReselect = 0
    var showPlayer = false
    var showWrapped = false
    var sheet: AppSheet?
    var toast: String?

    /// Opens a page from anywhere (player, menus, sheets).
    /// Colors of the cover that's playing, for the Dynamic theme.
    var coverColors: CoverColors?

    func coverChanged() {
        checkBadges() // a song just changed: a good moment to check (stats moved on)
        if prefs.data.theme == .pulse, let id = player.currentID {
            let mood = MoodIndex.shared.rank(id, fallback: AnalysisCache.load(id)?.mood ?? 0.5)
            if abs(mood - pulseMood) > 0.01 { withAnimation(.easeInOut(duration: 1.5)) { pulseMood = mood } }
        }
        guard prefs.data.theme == .dynamic || prefs.data.theme == .pulse, let song = player.currentSong else { return }
        Task {
            guard let img = await ImageCache.shared.image(local: song.localArtworkURL, remote: song.artworkURL, maxPixel: 120),
                  let colors = await CoverColors.extract(from: img), player.currentSong?.id == song.id else { return }
            withAnimation(.easeInOut(duration: 1.2)) { coverColors = colors }
        }
    }

    /// Bumped when Home's tab is tapped while already on Home's first page (scroll up, close search).
    var homeReselect = 0

    /// Tapping the tab you're already on: go back to its first page, or if you're there, to the top.
    func reselect(_ t: Tab) {
        switch t {
        case .home: if homePath.isEmpty { homeReselect += 1 } else { homePath.removeAll() }
        case .library: libraryPath.removeAll()
        case .stats: statsPath.removeAll()
        case .games: if gamesPath.isEmpty { gamesReselect += 1 } else { gamesPath.removeAll() }
        }
    }

    func navigate(_ route: Route) {
        sheet = nil
        showPlayer = false
        switch tab {
        case .home: homePath.append(route)
        case .library: libraryPath.append(route)
        case .stats: statsPath.append(route)
        case .games: gamesPath.append(route)
        }
    }

    private var launched = false

    private init() {}

    func onLaunch() {
        defer { Task { @MainActor in try? await Task.sleep(for: .seconds(3)); AppModel.shared.checkBadges(force: true) } }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        guard !launched else { return }
        launched = true
        player.updateRoute()
        player.restoreSession()
        playlists.createDefaultsIfNeeded()
        playlists.createDailyMixesIfNeeded()
        playlists.syncHomeCharts(prefs.data.homeCharts)
        library.analyzeMissing()
        stats.mergeVersions(library)
        pickSongOfTheDay()
        UIDevice.current.isBatteryMonitoringEnabled = true
        WeatherWatcher.shared.start()
        if prefs.data.autoRemoveUnplayed {
            library.cleanUpUnplayed(stats: stats, protectedIDs: playlists.protectedSongIDs)
        }
        Task { await playlists.refreshAll() }
        backup.autoBackupIfDue()
        if let name = prefs.data.appIcon == "Classic" ? nil : prefs.data.appIcon,
           UIApplication.shared.alternateIconName != name {
            UIApplication.shared.setAlternateIconName(name) { _ in }
        }
    }

    func onForeground() {
        stats.mergeVersions(library)
        checkBadges(force: true)
        pickSongOfTheDay()
        Task { await WeatherWatcher.shared.refreshIfNeeded() }
        library.pump()
        Task { await playlists.refreshAll() }
        backup.autoBackupIfDue()
    }

    func onBackground() {
        stats.saveNow()
        library.saveNow()
        playlists.saveNow()
        prefs.saveNow()
        player.saveSession()
        backup.autoBackupIfDue()
    }

    func haptic(_ kind: Haptic) {
        guard prefs.data.haptics else { return }
        switch kind {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    func show(_ message: String) { toast = message }

    // MARK: Badges

    /// Counts something a badge looks at (e.g. songs shared), then checks for new badges.
    func bump(_ key: String, by n: Int = 1) {
        prefs.data.counters[key, default: 0] += n
        checkBadges()
    }

    /// Marks something as done at least once (e.g. a theme tried).
    func mark(_ key: String) {
        guard prefs.data.counters[key] == nil else { return }
        prefs.data.counters[key] = 1
        checkBadges()
    }

    @ObservationIgnored private var lastBadgeCheck = Date.distantPast

    /// Announces badges that just reached a new tier. The first check after updating is silent,
    /// so badges you'd already earned don't all pop up at once.
    func checkBadges(force: Bool = false) {
        guard force || Date.now.timeIntervalSince(lastBadgeCheck) > 2 else { return }
        lastBadgeCheck = .now
        let statuses = Badges.evaluate()
        let first = prefs.data.counters["badgesReady"] == nil
        var earned: [BadgeStatus] = []
        for s in statuses {
            let known = prefs.data.badgeTiers[s.id] ?? 0
            if s.tier.rawValue > known {
                prefs.data.badgeTiers[s.id] = s.tier.rawValue
                earned.append(s)
            }
        }
        let newThemes = medalThemesJustUnlocked()
        let s = stats.streakInfo()
        if s != streak { streak = s }
        if first { prefs.data.counters["badgesReady"] = 1; return }
        if let best = earned.max(by: { $0.tier < $1.tier }) {
            let more = earned.count > 1 ? " and \(earned.count - 1) more" : ""
            show("\(best.tier == .gold ? "🥇" : best.tier == .silver ? "🥈" : "🥉") \(best.tier.label) badge: \(best.def.name)\(more)")
            haptic(.success)
        } else if let theme = newThemes.last {
            show("✨ New theme unlocked: \(theme.label)")
            haptic(.success)
        }
    }

    /// The welcome screen shows for new users, and once more for everyone after the update that added birthdays
    /// (your name and everything else stay as they are).
    var needsWelcome: Bool { !prefs.data.onboarded || prefs.data.counters["welcome2"] == nil }

    static func dayKey(_ d: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var songOfTheDay: LibraryEntry? { prefs.data.songOfDay[Self.dayKey()].flatMap { library.entry($0) } }

    /// Picks today's song once: liked songs and old favorites you haven't heard lately come first,
    /// and nothing picked in the last 30 days.
    func pickSongOfTheDay() {
        let key = Self.dayKey()
        if let id = prefs.data.songOfDay[key], library.entry(id) != nil { return }
        guard !library.entries.isEmpty else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recentPicks = Set(prefs.data.songOfDay.compactMap { k, v in k >= Self.dayKey(cutoff) ? v : nil })
        let twoWeeks = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        var plays: [Int: Int] = [:], last: [Int: Date] = [:]
        for r in stats.records where r.seconds >= StatsStore.playThreshold {
            plays[r.songID, default: 0] += 1
            last[r.songID] = r.start
        }
        let pool = library.entries.filter { !recentPicks.contains($0.id) }
        let favorites = pool.filter { e in (e.liked || (plays[e.id] ?? 0) >= 3) && (last[e.id] ?? .distantPast) < twoWeeks }
        let source = favorites.isEmpty ? pool : favorites
        var rng = SeededRNG(seed: UInt64(key.replacingOccurrences(of: "-", with: "")) ?? 1)
        guard let pick = source.randomElement(using: &rng) ?? library.entries.randomElement() else { return }
        // Keep the last 60 days of picks.
        let old = Self.dayKey(Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .now)
        prefs.data.songOfDay = prefs.data.songOfDay.filter { $0.key >= old }
        prefs.data.songOfDay[key] = pick.id
    }

    /// Wrapped for a specific period (a recap), opened from Home or Stats.
    struct WrappedRequest: Equatable {
        var interval: DateInterval
        var name: String
        var previousName: String
    }
    var wrappedRequest: WrappedRequest?

    func openRecap(weekly: Bool, interval: DateInterval? = nil) {
        guard let i = interval ?? (weekly ? StatsStore.lastWeek() : StatsStore.lastMonth()) else { return }
        let name = weekly
            ? "the week of \(i.start.formatted(.dateTime.day().month(.abbreviated)))"
            : i.start.formatted(.dateTime.month(.wide).year())
        wrappedRequest = WrappedRequest(interval: i, name: name, previousName: weekly ? "the week before" : "the month before")
        player.pause()
        showWrapped = true
    }

    /// The mood (0 calm … 1 energetic) of the song playing, for Pulse's accent and bars.
    var pulseMood = 0.5

    /// Your listening streak, for the Streak theme (updated with the badge checks).
    var streak = StreakInfo()

    /// How many badges you have at a tier or better.
    func badgeCount(atLeast tier: BadgeTier) -> Int {
        prefs.data.badgeTiers.values.filter { $0 >= tier.rawValue }.count
    }

    func isUnlocked(_ theme: ThemeMode) -> Bool {
        guard let r = theme.medalRequirement else { return true }
        return badgeCount(atLeast: r.tier) >= r.count
    }

    /// Medal themes that became available since the last check (each is announced once).
    private func medalThemesJustUnlocked() -> [ThemeMode] {
        var out: [ThemeMode] = []
        for theme in ThemeMode.allCases where theme.medalRequirement != nil && isUnlocked(theme) {
            let key = "unlocked:\(theme.rawValue)"
            if prefs.data.counters[key] == nil {
                prefs.data.counters[key] = 1
                out.append(theme)
            }
        }
        return out
    }

    /// Badges in the order to show off: highest tier first.
    var earnedBadges: [BadgeStatus] {
        Badges.evaluate().filter { $0.tier != .none }.sorted { $0.tier != $1.tier ? $0.tier > $1.tier : $0.def.name < $1.def.name }
    }

    /// Songs plays can come from: the library copy if downloaded (with edits), else the catalog copy.
    func resolve(_ songs: [Song]) -> [Song] { songs.map { library.resolved($0) } }
}

/// Places you can navigate to.
enum Route: Hashable {
    case search
    case artist(Artist)
    case artistMore(Artist)
    case discography(Artist)
    case badges
    case album(Album)
    case playlist(UUID)
    case liked
    case chart(ChartSource)
    case browseCharts
    case stats
    case settings
    case songStats(Int)
    case yourCharts
    case songJourney(Int)
    case recaps
    case games
}
