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

    enum Tab: Hashable { case home, library, stats }

    var tab: Tab = .home
    var homePath: [Route] = []
    var libraryPath: [Route] = []
    var statsPath: [Route] = []
    var showPlayer = false
    var showWrapped = false
    var sheet: AppSheet?
    var toast: String?

    /// Opens a page from anywhere (player, menus, sheets).
    /// Colors of the cover that's playing, for the Dynamic theme.
    var coverColors: CoverColors?

    func coverChanged() {
        checkBadges() // a song just changed: a good moment to check (stats moved on)
        guard prefs.data.theme == .dynamic, let song = player.currentSong else { return }
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
        }
    }

    func navigate(_ route: Route) {
        sheet = nil
        showPlayer = false
        switch tab {
        case .home: homePath.append(route)
        case .library: libraryPath.append(route)
        case .stats: statsPath.append(route)
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
        checkBadges(force: true)
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
        if first { prefs.data.counters["badgesReady"] = 1; return }
        if let best = earned.max(by: { $0.tier < $1.tier }) {
            let more = earned.count > 1 ? " and \(earned.count - 1) more" : ""
            show("\(best.tier == .gold ? "🥇" : best.tier == .silver ? "🥈" : "🥉") \(best.tier.label) badge: \(best.def.name)\(more)")
            haptic(.success)
        }
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
}
