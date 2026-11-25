import Foundation
import Observation
import SwiftUI
import UIKit


enum CornerStyle: String, Codable, CaseIterable, Identifiable {
    case sharp, soft, round
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ArtShape: String, Codable, CaseIterable, Identifiable {
    case square, soft, circle
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum TextSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { switch self { case .small: "S"; case .medium: "M"; case .large: "L" } }
    var dynamicType: DynamicTypeSize { switch self { case .small: .medium; case .medium: .large; case .large: .xLarge } }
}

enum PlayerBackground: String, Codable, CaseIterable, Identifiable {
    case coverColor, blur, plain
    var id: String { rawValue }
    var label: String { switch self { case .coverColor: "Cover color"; case .blur: "Blur"; case .plain: "Plain" } }
}

enum Normalization: String, Codable, CaseIterable, Identifiable {
    case off, quiet, normal, loud
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Target loudness in dBFS (RMS).
    var target: Double? { switch self { case .off: nil; case .quiet: -20; case .normal: -16; case .loud: -13 } }
}

enum DownloadQuality: String, Codable, CaseIterable, Identifiable {
    case best, saver
    var id: String { rawValue }
}

enum BackupFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly
    var id: String { rawValue }
    var interval: TimeInterval { self == .daily ? 86_400 : 604_800 }
}

/// Speaker / headphones / everything else (AirPlay, car, cast). Each gets its own sound settings.
enum OutputKind: String, Codable, CaseIterable, Identifiable {
    case phone, headphones, speakers
    var id: String { rawValue }
    var label: String { switch self { case .phone: "iPhone"; case .headphones: "Headphones"; case .speakers: "Speakers" } }
}

enum EQPreset: String, Codable, CaseIterable, Identifiable {
    case flat, bass, vocal, bright, night, custom
    var id: String { rawValue }
    var label: String { switch self { case .flat: "Flat"; case .bass: "Bass boost"; case .vocal: "Vocals"; case .bright: "Bright"; case .night: "Night"; case .custom: "Custom" } }
    var gains: [Float] {
        switch self {
        case .flat, .custom: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bass: [6, 5, 4, 2, 0, -1, 0, 0, 1, 1]
        case .vocal: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]
        case .bright: [-1, -1, 0, 0, 1, 2, 3, 4, 5, 5]
        case .night: [-3, -2, 0, 1, 2, 2, 1, 0, -2, -4]
        }
    }
}

struct EQProfile: Codable, Hashable {
    var preset: EQPreset = .flat
    var custom: [Float] = Array(repeating: 0, count: 10)
    var gains: [Float] { preset == .custom ? custom : preset.gains }
    static let bands: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
}

enum HomeSectionKind: String, Codable, CaseIterable, Identifiable {
    case summary, madeForYou, newFromArtists, charts, recentlyPlayed, recentlyAdded, topArtists, following, onRepeat, trending, newReleases
    case yourPlaylists, favoriteAlbums, badges, dice, songOfDay, songOfWeek, recap, onThisDay
    var id: String { rawValue }
    /// New sections are on by default, except a few you choose to turn on.
    var visibleByDefault: Bool { ![.badges, .dice, .songOfWeek, .onThisDay].contains(self) }
    /// These have their own fixed look; everything else can change layout (Dice chooses its songs instead).
    var hasLayouts: Bool { ![.summary, .badges, .dice, .songOfDay, .songOfWeek, .recap, .onThisDay].contains(self) }
    var defaultLayout: HomeLayout {
        switch self {
        case .onRepeat: .numbered
        case .trending: .list
        case .yourPlaylists: .compactGrid
        case .following: .smallCovers
        default: .bigCovers
        }
    }
    var title: String {
        switch self {
        case .summary: "Listening summary"
        case .madeForYou: "Made for you"
        case .newFromArtists: "New from your artists"
        case .charts: "Charts"
        case .recentlyPlayed: "Recently played"
        case .recentlyAdded: "Recently downloaded"
        case .topArtists: "Your top artists"
        case .following: "Following"
        case .onRepeat: "On repeat"
        case .trending: "Trending now"
        case .newReleases: "New releases"
        case .yourPlaylists: "Your playlists"
        case .favoriteAlbums: "Your favorite albums right now"
        case .badges: "Your badges"
        case .dice: "Roll the dice"
        case .songOfDay: "Song of the day"
        case .songOfWeek: "Song of the week"
        case .recap: "Your recap"
        case .onThisDay: "On this day"
        }
    }
    var icon: String {
        switch self {
        case .summary: "chart.bar.fill"
        case .madeForYou: "sparkles"
        case .newFromArtists: "bell.badge"
        case .charts: "list.number"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .recentlyAdded: "arrow.down.circle"
        case .topArtists: "star.fill"
        case .following: "heart.fill"
        case .onRepeat: "repeat"
        case .trending: "flame.fill"
        case .newReleases: "opticaldisc"
        case .yourPlaylists: "music.note.list"
        case .favoriteAlbums: "square.stack.fill"
        case .badges: "medal.fill"
        case .dice: "dice.fill"
        case .songOfDay: "sun.max.fill"
        case .songOfWeek: "calendar.badge.clock"
        case .recap: "sparkles.rectangle.stack.fill"
        case .onThisDay: "clock.arrow.circlepath"
        }
    }
}

struct HomeSection: Codable, Hashable, Identifiable {
    var kind: HomeSectionKind
    var visible: Bool
    /// How the section is drawn, and how many items it shows (nil = the section's default).
    var layout: HomeLayout? = nil
    var count: Int? = nil
    var id: String { kind.rawValue }

    var effectiveLayout: HomeLayout { layout ?? kind.defaultLayout }
    var effectiveCount: Int { count ?? effectiveLayout.defaultCount }
}

/// The ways a Home section can be drawn.
enum HomeLayout: String, Codable, CaseIterable, Identifiable {
    case bigCovers, smallCovers, featured, compactGrid, coverGrid, list, numbered
    var id: String { rawValue }

    var label: String {
        switch self {
        case .bigCovers: "Big covers"
        case .smallCovers: "Small covers"
        case .featured: "Featured"
        case .compactGrid: "Compact grid"
        case .coverGrid: "Cover grid"
        case .list: "List"
        case .numbered: "Numbered list"
        }
    }
    var detail: String {
        switch self {
        case .bigCovers: "Large artwork you swipe through sideways"
        case .smallCovers: "Smaller artwork, more at once"
        case .featured: "One big card, then a row of small ones"
        case .compactGrid: "Two columns of small artwork with titles beside"
        case .coverGrid: "Three columns of covers going down"
        case .list: "Rows going down, with details"
        case .numbered: "Rows with rank numbers"
        }
    }
    var icon: String {
        switch self {
        case .bigCovers: "rectangle.split.3x1"
        case .smallCovers: "square.grid.4x3.fill"
        case .featured: "rectangle.topthird.inset.filled"
        case .compactGrid: "square.grid.2x2"
        case .coverGrid: "square.grid.3x3"
        case .list: "list.bullet"
        case .numbered: "list.number"
        }
    }
    var defaultCount: Int {
        switch self {
        case .bigCovers, .smallCovers: 15
        case .featured: 7
        case .compactGrid: 8
        case .coverGrid: 9
        case .list, .numbered: 5
        }
    }
    static let countChoices = [3, 4, 5, 6, 8, 9, 10, 12, 15, 20]
}

enum PrivateMode: Codable, Hashable {
    case off
    case until(Date)
    case always

    var isActive: Bool {
        switch self {
        case .off: false
        case .always: true
        case .until(let d): d > .now
        }
    }
}

struct ConcertCity: Codable, Hashable, Identifiable {
    var name: String
    var lat: Double
    var lon: Double
    var id: String { name }

    static let all: [ConcertCity] = [
        .init(name: "Copenhagen", lat: 55.6761, lon: 12.5683), .init(name: "Aarhus", lat: 56.1629, lon: 10.2039),
        .init(name: "Odense", lat: 55.4038, lon: 10.4024), .init(name: "Aalborg", lat: 57.0488, lon: 9.9217),
        .init(name: "Malmö", lat: 55.6050, lon: 13.0038), .init(name: "Stockholm", lat: 59.3293, lon: 18.0686),
        .init(name: "Oslo", lat: 59.9139, lon: 10.7522), .init(name: "Hamburg", lat: 53.5511, lon: 9.9937),
        .init(name: "Berlin", lat: 52.5200, lon: 13.4050), .init(name: "London", lat: 51.5072, lon: -0.1276),
        .init(name: "Amsterdam", lat: 52.3676, lon: 4.9041)
    ]
}

/// Everything the user can set. Stored as one JSON file.
struct PrefsData: Codable, Equatable {
    // Profile
    var name = ""
    var onboarded = false
    var avatarHex = "#34D399"
    var hasAvatarPhoto = false
    var privateMode: PrivateMode = .off
    var privateSkipsStats = false

    // Appearance
    var theme: ThemeMode = .dark
    var accentHex = "#34D399"
    var appIcon = "Classic"
    var corners: CornerStyle = .soft
    var artShape: ArtShape = .soft
    var textSize: TextSize = .medium
    var playerBackground: PlayerBackground = .coverColor
    var tabLabels = true
    var haptics = true
    var animations = true
    var font: AppFont = .standard
    var playerStyle: PlayerStyle = .classic
    var progressStyle: ProgressStyle = .line
    var miniPlayerStyle: MiniPlayerStyle = .card
    /// Things the badges count that can't be worked out from your stats (e.g. songs shared).
    var counters: [String: Int] = [:]
    /// Badge tiers already celebrated, so each unlock is announced once.
    var badgeTiers: [String: Int] = [:]
    /// Weather theme: use your location, or this city.
    var weatherUseLocation = true
    var weatherCity = ""
    /// Your birthday (month 0 = not set), celebrated by the Seasons theme.
    var birthdayMonth = 0
    var birthdayDay = 0
    /// Song of the day picks, by day ("2026-11-25" → song ID), so a song isn't picked twice in 30 days.
    var songOfDay: [String: Int] = [:]
    /// Daily game results and streaks.
    var games: [String: GameRecord] = [:]
    /// Moves made in today's daily puzzles ("tunedle|2026-11-25" → moves), so leaving doesn't reset them.
    var gameProgress: [String: [String]] = [:]
    /// Dice block on Home: where its songs come from.
    var diceSource: DiceSource = .anything
    var diceArtist: Artist?
    var dicePlaylistID: UUID?

    // Home
    var home: [HomeSection] = HomeSectionKind.allCases.map { HomeSection(kind: $0, visible: $0.visibleByDefault) }
    var homeCharts: [ChartSource] = ChartCatalog.defaults

    // Data & downloads
    var offline = false
    var downloadWifiOnly = true
    var askBeforeExtras = true
    var previewsOnCellular = true
    var quality: DownloadQuality = .best
    var storageLimitGB = 0
    var autoRemoveUnplayed = false
    var allowRemoteExtraction = false

    // Playback
    var lyricsEnabled = true
    var eq: [String: EQProfile] = [:]
    var eqEnabled = true
    var normalization: Normalization = .normal
    var gapless = true
    var crossfade = 0
    var noCrossfadeInAlbums = true
    /// Beat-matched blends between songs on shuffle and in mixes (albums stay gapless).
    var smartTransitions = false

    // Backup
    var backupBookmark: Data?
    var backupFolderName: String?
    var autoBackup = true
    var backupFrequency: BackupFrequency = .daily
    var backupKeep = 5
    /// Include your own pictures (custom covers, playlist photos, profile picture) in backups.
    var backupImages = true
    /// Include the audio of songs you imported from files (these can't be downloaded again).
    var backupOwnFiles = true
    var lastBackup: Date?

    // Connections
    var ticketmasterKey = ""
    var concertCity = ConcertCity.all[0]
    var concertRadiusKm = 500

    init() {}

    init(from decoder: Decoder) throws {
        let d = PrefsData()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? def }
        name = v(.name, d.name); onboarded = v(.onboarded, d.onboarded); avatarHex = v(.avatarHex, d.avatarHex)
        hasAvatarPhoto = v(.hasAvatarPhoto, d.hasAvatarPhoto); privateMode = v(.privateMode, d.privateMode)
        privateSkipsStats = v(.privateSkipsStats, d.privateSkipsStats)
        theme = v(.theme, d.theme); accentHex = v(.accentHex, d.accentHex); appIcon = v(.appIcon, d.appIcon)
        corners = v(.corners, d.corners); artShape = v(.artShape, d.artShape); textSize = v(.textSize, d.textSize)
        playerBackground = v(.playerBackground, d.playerBackground); tabLabels = v(.tabLabels, d.tabLabels)
        haptics = v(.haptics, d.haptics); animations = v(.animations, d.animations)
        font = v(.font, d.font); playerStyle = v(.playerStyle, d.playerStyle); progressStyle = v(.progressStyle, d.progressStyle)
        miniPlayerStyle = v(.miniPlayerStyle, d.miniPlayerStyle); counters = v(.counters, d.counters); badgeTiers = v(.badgeTiers, d.badgeTiers)
        weatherUseLocation = v(.weatherUseLocation, d.weatherUseLocation); weatherCity = v(.weatherCity, d.weatherCity)
        birthdayMonth = v(.birthdayMonth, d.birthdayMonth); birthdayDay = v(.birthdayDay, d.birthdayDay)
        diceSource = v(.diceSource, d.diceSource)
        songOfDay = v(.songOfDay, d.songOfDay); games = v(.games, d.games); gameProgress = v(.gameProgress, d.gameProgress)
        diceArtist = try? c.decodeIfPresent(Artist.self, forKey: .diceArtist)
        dicePlaylistID = try? c.decodeIfPresent(UUID.self, forKey: .dicePlaylistID)
        home = v(.home, d.home); homeCharts = v(.homeCharts, d.homeCharts)
        offline = v(.offline, d.offline); downloadWifiOnly = v(.downloadWifiOnly, d.downloadWifiOnly)
        askBeforeExtras = v(.askBeforeExtras, d.askBeforeExtras); previewsOnCellular = v(.previewsOnCellular, d.previewsOnCellular)
        quality = v(.quality, d.quality); storageLimitGB = v(.storageLimitGB, d.storageLimitGB)
        autoRemoveUnplayed = v(.autoRemoveUnplayed, d.autoRemoveUnplayed); allowRemoteExtraction = v(.allowRemoteExtraction, d.allowRemoteExtraction)
        lyricsEnabled = v(.lyricsEnabled, d.lyricsEnabled); eq = v(.eq, d.eq); eqEnabled = v(.eqEnabled, d.eqEnabled)
        normalization = v(.normalization, d.normalization); gapless = v(.gapless, d.gapless)
        crossfade = v(.crossfade, d.crossfade); noCrossfadeInAlbums = v(.noCrossfadeInAlbums, d.noCrossfadeInAlbums)
        smartTransitions = v(.smartTransitions, d.smartTransitions)
        backupBookmark = try? c.decodeIfPresent(Data.self, forKey: .backupBookmark)
        backupFolderName = try? c.decodeIfPresent(String.self, forKey: .backupFolderName)
        autoBackup = v(.autoBackup, d.autoBackup); backupFrequency = v(.backupFrequency, d.backupFrequency)
        backupKeep = v(.backupKeep, d.backupKeep)
        backupImages = v(.backupImages, d.backupImages); backupOwnFiles = v(.backupOwnFiles, d.backupOwnFiles)
        lastBackup = try? c.decodeIfPresent(Date.self, forKey: .lastBackup)
        ticketmasterKey = v(.ticketmasterKey, d.ticketmasterKey); concertCity = v(.concertCity, d.concertCity)
        concertRadiusKm = v(.concertRadiusKm, d.concertRadiusKm)
        // Sections added in later versions show up at the end.
        for kind in HomeSectionKind.allCases where !home.contains(where: { $0.kind == kind }) {
            home.append(HomeSection(kind: kind, visible: kind.visibleByDefault))
        }
    }

    func eqProfile(_ kind: OutputKind) -> EQProfile { eq[kind.rawValue] ?? EQProfile() }
}

@MainActor @Observable
final class Prefs {
    var data: PrefsData {
        didSet {
            guard data != oldValue else { return }
            debouncer.run { [weak self] in
                guard let self else { return }
                Store.save(self.data, "prefs.json")
            }
        }
    }

    private let debouncer = Debouncer(.milliseconds(400))

    init() {
        data = Store.load(PrefsData.self, "prefs.json") ?? PrefsData()
    }

    func saveNow() { Store.saveNow(data, "prefs.json") }

    var accent: Color { Color(hex: data.accentHex) }
    var displayName: String { data.name.trimmingCharacters(in: .whitespaces) }
    var initial: String { displayName.first.map { String($0).uppercased() } ?? "T" }
    var isPrivate: Bool { data.privateMode.isActive }

    var colorScheme: ColorScheme? { data.theme.scheme }

    /// Light/dark for a given look (Horizon switches during the day).
    func colorScheme(for look: Look) -> ColorScheme? { look.palette?.scheme ?? data.theme.scheme }
}

/// Colors and shapes derived from appearance settings, available to every view.
struct Look: Equatable {
    var accent: Color = Color(hex: "#34D399")
    var theme: ThemeMode = .dark
    /// The resolved colors of non-classic themes (Dynamic and Horizon change over time).
    var palette: ThemePalette? = nil
    var black: Bool { theme == .black }
    var corner: CGFloat = 1
    var artShape: ArtShape = .soft
    var playerBackground: PlayerBackground = .coverColor

    func radius(_ base: CGFloat) -> CGFloat {
        switch corner {
        case ..<0.6: return max(2, base * 0.35)
        case 1.4...: return base * 1.6
        default: return base
        }
    }

    func artRadius(size: CGFloat) -> CGFloat {
        switch artShape {
        case .square: return 2
        case .soft: return size > 100 ? 12 : 6
        case .circle: return size / 2
        }
    }
}

private struct LookKey: EnvironmentKey {
    static let defaultValue = Look()
}

extension EnvironmentValues {
    var look: Look {
        get { self[LookKey.self] }
        set { self[LookKey.self] = newValue }
    }
}

extension Prefs {
    var look: Look { look(at: .now, cover: nil) }

    /// The look at a given moment: Horizon depends on the time, Dynamic on the cover that's playing.
    func look(at date: Date, cover: CoverColors?) -> Look {
        let palette: ThemePalette? = data.theme.isLive
            ? LiveThemes.palette(for: data.theme, at: date, cover: cover)
            : data.theme.palette
        let accentColor = data.theme.isLive ? (palette?.accent ?? accent) : accent
        return Look(accent: accentColor,
             theme: data.theme,
             palette: palette,
             corner: data.corners == .sharp ? 0.4 : (data.corners == .round ? 1.6 : 1),
             artShape: data.artShape,
             playerBackground: data.playerBackground)
    }
}

/// Background colors for the themes. Dark is a soft charcoal; Black is pure black (best on OLED screens);
/// Light and Auto follow the system in light mode.
struct Surface {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    private static func gray(_ v: CGFloat) -> UIColor { UIColor(red: v, green: v, blue: v + 0.012, alpha: 1) }

    /// A solid background color. Gradient themes draw `ThemeBackground` instead; this is their base color.
    static func background(_ look: Look) -> Color {
        if let base = look.palette?.colors.first { return base }
        return look.black ? .black : dynamic(light: .systemBackground, dark: gray(0.075))
    }
    static func card(_ look: Look) -> Color {
        if let p = look.palette { return p.scheme == .light ? Color.white.opacity(0.6) : Color.white.opacity(0.08) }
        return look.black ? Color(white: 0.08) : dynamic(light: .secondarySystemBackground, dark: gray(0.13))
    }
    static func raised(_ look: Look) -> Color {
        if let p = look.palette { return p.scheme == .light ? Color.white.opacity(0.8) : Color.white.opacity(0.14) }
        return look.black ? Color(white: 0.13) : dynamic(light: .tertiarySystemBackground, dark: gray(0.18))
    }
    /// The tab bar: always solid.
    static func bar(_ look: Look) -> Color {
        if let bar = look.palette?.bar { return bar }
        return card(look)
    }
    /// Background behind grouped settings lists.
    static func grouped(_ look: Look) -> Color {
        look.black ? .black : dynamic(light: .systemGroupedBackground, dark: gray(0.075))
    }
    /// Row color inside grouped settings lists: slightly see-through, so the theme shows behind.
    static func groupedRow(_ look: Look) -> Color {
        switch look.theme {
        case .black: return Color.white.opacity(0.09)
        case .dark: return Color.white.opacity(0.075)
        case .light: return Color.white.opacity(0.85)
        case .auto: return dynamic(light: UIColor.white.withAlphaComponent(0.85), dark: UIColor.white.withAlphaComponent(0.075))
        default: return look.palette?.scheme == .light ? Color.white.opacity(0.55) : Color.white.opacity(0.085)
        }
    }
}

/// Applies the theme's colors to a Form or List of settings.
struct ThemedForm: ViewModifier {
    @Environment(\.look) private var look
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                if look.palette == nil { Surface.grouped(look).ignoresSafeArea() } else { ThemeBackground().ignoresSafeArea() }
            }
            .labelStyle(SettingsLabelStyle())
            .tint(look.accent)
    }
}

/// Settings rows: accent-colored icon in a fixed-width column, text in the normal text color.
struct SettingsLabelStyle: LabelStyle {
    @Environment(\.look) private var look
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon.foregroundStyle(look.accent).frame(width: 26)
            configuration.title.foregroundStyle(Color.primary)
        }
    }
}

extension View {
    func themedForm() -> some View { modifier(ThemedForm()) }
    /// Applied to each Section of a settings list.
    func themedRow() -> some View { modifier(ThemedRow()) }
}

struct ThemedRow: ViewModifier {
    @Environment(\.look) private var look
    func body(content: Content) -> some View { content.listRowBackground(Surface.groupedRow(look)) }
}

/// A switch drawn by Tunes, so it follows the accent color and the Haptics setting
/// (the system switch always vibrates, whatever the app's setting is).
struct TunesToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        TunesSwitch(configuration: configuration)
    }
}

/// Just the switch, with no label (for rows that lay out their own text).
struct SwitchKnob: View {
    @Binding var isOn: Bool
    @Environment(\.look) private var look

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
            AppModel.shared.haptic(.selection)
        } label: {
            Capsule()
                .fill(isOn ? look.accent : Color(.systemFill))
                .frame(width: 51, height: 31)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct TunesSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { configuration.isOn.toggle() }
            AppModel.shared.haptic(.selection)
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                Capsule()
                    .fill(configuration.isOn ? look.accent : Color(.systemFill))
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}




enum PlayerStyle: String, Codable, CaseIterable, Identifiable {
    case classic, vinyl, cassette, minimal, lyrics
    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: "Classic"
        case .vinyl: "Vinyl"
        case .cassette: "Cassette"
        case .minimal: "Minimal"
        case .lyrics: "Lyrics first"
        }
    }
    var icon: String {
        switch self {
        case .classic: "square.fill"
        case .vinyl: "record.circle"
        case .cassette: "recordingtape"
        case .minimal: "textformat.size.larger"
        case .lyrics: "quote.bubble.fill"
        }
    }
}

enum ProgressStyle: String, Codable, CaseIterable, Identifiable {
    case line, thick, waveform, squiggle, dots
    var id: String { rawValue }
    var label: String {
        switch self {
        case .line: "Line"
        case .thick: "Thick"
        case .waveform: "Waveform"
        case .squiggle: "Squiggle"
        case .dots: "Dots"
        }
    }
}

enum MiniPlayerStyle: String, Codable, CaseIterable, Identifiable {
    case card, bar, bubble, minimal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .card: "Card"
        case .bar: "Bar"
        case .bubble: "Bubble"
        case .minimal: "Minimal"
        }
    }
    /// Room screens leave at the bottom for it.
    var height: CGFloat {
        switch self {
        case .card: 72
        case .bar: 62
        case .bubble: 78
        case .minimal: 52
        }
    }
}


/// Where the Dice block on Home picks its random song from.
enum DiceSource: String, Codable, CaseIterable, Identifiable {
    case anything, favorites, recentFavorites, pastFavorites, artist, neverPlayed, playlist
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anything: "Anything"
        case .favorites: "Favorites"
        case .recentFavorites: "Recent favorites"
        case .pastFavorites: "Past favorites"
        case .artist: "One artist"
        case .neverPlayed: "Never played"
        case .playlist: "A playlist"
        }
    }
    var detail: String {
        switch self {
        case .anything: "Any song in your library"
        case .favorites: "Your liked songs"
        case .recentFavorites: "What you've played most lately"
        case .pastFavorites: "Songs you loved but haven't played in a while"
        case .artist: "Only songs by the artist you pick"
        case .neverPlayed: "Downloaded but never played"
        case .playlist: "Only songs from the playlist you pick"
        }
    }
    var icon: String {
        switch self {
        case .anything: "music.note"
        case .favorites: "heart.fill"
        case .recentFavorites: "flame.fill"
        case .pastFavorites: "clock.arrow.circlepath"
        case .artist: "person.fill"
        case .neverPlayed: "sparkles"
        case .playlist: "music.note.list"
        }
    }
}


/// Results for one game: daily streaks and totals.
struct GameRecord: Codable, Hashable {
    var lastDaily = ""
    var dailyWon = false
    var streak = 0
    var bestStreak = 0
    var played = 0
    var won = 0
    /// How today's daily ended, for "See your answer".
    var lastHeadline: String?
    var lastDetail: String?
}
