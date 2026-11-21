import Foundation
import Observation
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
        guard !launched else { return }
        launched = true
        player.updateRoute()
        player.restoreSession()
        playlists.createDefaultsIfNeeded()
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

    /// Songs plays can come from: the library copy if downloaded (with edits), else the catalog copy.
    func resolve(_ songs: [Song]) -> [Song] { songs.map { library.resolved($0) } }
}

/// Places you can navigate to.
enum Route: Hashable {
    case search
    case artist(Artist)
    case artistMore(Artist)
    case album(Album)
    case playlist(UUID)
    case liked
    case chart(ChartSource)
    case browseCharts
    case stats
    case settings
    case songStats(Int)
}
