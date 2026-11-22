import Foundation
import Observation
import SwiftUI
import UIKit

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case dark, black, light, auto
    case midnight, sunset, ocean, forest, rose
    case aurora, nebula, lava, lagoon, pastel
    var id: String { rawValue }
    var label: String { self == .rose ? "Rosé" : rawValue.capitalized }

    /// The plain themes; everything else draws a gradient (or, for Aurora, moving light) behind the app.
    var isClassic: Bool { [.dark, .black, .light, .auto].contains(self) }

    /// Animated themes: soft colored light drifting slowly behind the app.
    var isAnimated: Bool { [.aurora, .nebula, .lava, .lagoon, .pastel].contains(self) }

    /// The drifting lights of an animated theme, and how long one slow drift takes (seconds).
    var lights: (colors: [String], opacity: Double, seconds: Double, stars: Bool) {
        switch self {
        case .aurora: (["#10B981", "#8B5CF6", "#0EA5E9"], 0.32, 18, false)
        case .nebula: (["#C026D3", "#4F46E5", "#06B6D4"], 0.28, 24, true)
        case .lava: (["#F97316", "#DC2626", "#DB2777"], 0.30, 14, false)
        case .lagoon: (["#14B8A6", "#22D3EE", "#4ADE80"], 0.26, 20, false)
        case .pastel: (["#F9A8D4", "#FDBA74", "#C4B5FD"], 0.45, 22, false)
        default: ([], 0, 0, false)
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .light, .rose, .pastel: .light
        case .auto: nil
        default: .dark
        }
    }

    /// Gradient colors from top to bottom (gradient themes only).
    var gradient: [String] {
        switch self {
        case .midnight: ["#0B1026", "#1B1446", "#2E1458"]
        case .sunset: ["#1C0B2B", "#4A1638", "#8C3B2E"]
        case .ocean: ["#03192B", "#053F5C", "#0B7285"]
        case .forest: ["#06140D", "#0F2A1B", "#1F4A2C"]
        case .aurora: ["#050B14", "#07121F", "#050B14"]
        case .nebula: ["#07051A", "#0B0826", "#07051A"]
        case .lava: ["#130606", "#1C0909", "#130606"]
        case .lagoon: ["#03161A", "#052126", "#03161A"]
        case .pastel: ["#FFF9F5", "#FDF4FF", "#FFF9F5"]
        case .rose: ["#FFF1F2", "#FCE7F3", "#EDE9FE"]
        default: []
        }
    }

    /// A solid color for the tab bar, so its buttons stay readable over the gradient.
    var barHex: String? {
        switch self {
        case .midnight: "#0D1130"
        case .sunset: "#1E0C2C"
        case .ocean: "#041E33"
        case .forest: "#08180F"
        case .aurora: "#070F1A"
        case .nebula: "#0A0820"
        case .lava: "#1A0909"
        case .lagoon: "#041B20"
        case .pastel: "#FFF8F6"
        case .rose: "#FFF5F8"
        default: nil
        }
    }

    /// The accent picked automatically when you choose this theme (you can still change it).
    var suggestedAccent: String? {
        switch self {
        case .midnight: "#A78BFA"
        case .sunset: "#FB923C"
        case .ocean: "#22D3EE"
        case .forest: "#86EFAC"
        case .aurora: "#34D399"
        case .nebula: "#E879F9"
        case .lava: "#FB923C"
        case .lagoon: "#2DD4BF"
        case .pastel: "#EC4899"
        case .rose: "#DB2777"
        default: nil
        }
    }
}

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
    var id: String { rawValue }
    /// The summary card has a fixed look; everything else can change layout.
    var hasLayouts: Bool { self != .summary }
    var defaultLayout: HomeLayout {
        switch self {
        case .onRepeat: .numbered
        case .trending: .list
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

    // Home
    var home: [HomeSection] = HomeSectionKind.allCases.map { HomeSection(kind: $0, visible: true) }
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
        home = v(.home, d.home); homeCharts = v(.homeCharts, d.homeCharts)
        offline = v(.offline, d.offline); downloadWifiOnly = v(.downloadWifiOnly, d.downloadWifiOnly)
        askBeforeExtras = v(.askBeforeExtras, d.askBeforeExtras); previewsOnCellular = v(.previewsOnCellular, d.previewsOnCellular)
        quality = v(.quality, d.quality); storageLimitGB = v(.storageLimitGB, d.storageLimitGB)
        autoRemoveUnplayed = v(.autoRemoveUnplayed, d.autoRemoveUnplayed); allowRemoteExtraction = v(.allowRemoteExtraction, d.allowRemoteExtraction)
        lyricsEnabled = v(.lyricsEnabled, d.lyricsEnabled); eq = v(.eq, d.eq); eqEnabled = v(.eqEnabled, d.eqEnabled)
        normalization = v(.normalization, d.normalization); gapless = v(.gapless, d.gapless)
        crossfade = v(.crossfade, d.crossfade); noCrossfadeInAlbums = v(.noCrossfadeInAlbums, d.noCrossfadeInAlbums)
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
            home.append(HomeSection(kind: kind, visible: true))
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
}

/// Colors and shapes derived from appearance settings, available to every view.
struct Look: Equatable {
    var accent: Color = Color(hex: "#34D399")
    var theme: ThemeMode = .dark
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
    var look: Look {
        Look(accent: accent,
             theme: data.theme,
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
        if !look.theme.isClassic, let base = look.theme.gradient.first { return Color(hex: base) }
        return look.black ? .black : dynamic(light: .systemBackground, dark: gray(0.075))
    }
    static func card(_ look: Look) -> Color {
        if !look.theme.isClassic { return look.theme.scheme == .light ? Color.white.opacity(0.6) : Color.white.opacity(0.08) }
        return look.black ? Color(white: 0.08) : dynamic(light: .secondarySystemBackground, dark: gray(0.13))
    }
    static func raised(_ look: Look) -> Color {
        if !look.theme.isClassic { return look.theme.scheme == .light ? Color.white.opacity(0.8) : Color.white.opacity(0.14) }
        return look.black ? Color(white: 0.13) : dynamic(light: .tertiarySystemBackground, dark: gray(0.18))
    }
    /// The tab bar: always solid.
    static func bar(_ look: Look) -> Color {
        if let hex = look.theme.barHex { return Color(hex: hex) }
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
        default: return look.theme.scheme == .light ? Color.white.opacity(0.55) : Color.white.opacity(0.085)
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
                if look.theme.isClassic { Surface.grouped(look).ignoresSafeArea() } else { ThemeBackground().ignoresSafeArea() }
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


/// The full-screen background for the current theme: a plain color, a gradient, or Aurora's slowly drifting light.
struct ThemeBackground: View {
    @Environment(\.look) private var look

    var body: some View {
        let theme = look.theme
        if theme.isClassic {
            Surface.background(look)
        } else if theme.isAnimated {
            DriftingLights(theme: theme)
                .id(theme)
        } else {
            GlowGradient(theme: theme)
        }
    }
}

/// A gradient with two soft, still glows for depth, plus a gentle darkening at the bottom so text stays readable.
private struct GlowGradient: View {
    let theme: ThemeMode
    var body: some View {
        let c = theme.gradient.map { Color(hex: $0) }
        let light = theme.scheme == .light
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [glow.0.opacity(light ? 0.35 : 0.30), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: max(w, h) * 0.7)
                RadialGradient(colors: [glow.1.opacity(light ? 0.30 : 0.22), .clear],
                               center: UnitPoint(x: 0.1, y: 0.75), startRadius: 0, endRadius: max(w, h) * 0.6)
                LinearGradient(colors: [.clear, (light ? Color.white : Color.black).opacity(0.25)],
                               startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
            }
        }
    }

    /// Two glow colors per theme, picked to sit nicely on its gradient.
    private var glow: (Color, Color) {
        switch theme {
        case .midnight: (Color(hex: "#6366F1"), Color(hex: "#C084FC"))
        case .sunset: (Color(hex: "#F97316"), Color(hex: "#EC4899"))
        case .ocean: (Color(hex: "#22D3EE"), Color(hex: "#3B82F6"))
        case .forest: (Color(hex: "#4ADE80"), Color(hex: "#A3E635"))
        case .rose: (Color(hex: "#F9A8D4"), Color(hex: "#C4B5FD"))
        default: (.clear, .clear)
        }
    }
}

/// Three large, heavily blurred lights that drift slowly back and forth (plus optional twinkling stars).
/// Only offsets and opacity animate, so it's cheap to draw.
private struct DriftingLights: View {
    let theme: ThemeMode
    @State private var drift = false
    @State private var twinkle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let l = theme.lights
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Color(hex: theme.gradient.first ?? "#000000")
                if l.colors.count == 3 {
                    blob(l.colors[0], l.opacity, size: w * 1.1)
                        .offset(x: drift ? -w * 0.25 : w * 0.15, y: drift ? -h * 0.30 : -h * 0.18)
                    blob(l.colors[1], l.opacity, size: w * 1.0)
                        .offset(x: drift ? w * 0.30 : -w * 0.10, y: drift ? -h * 0.05 : -h * 0.25)
                    blob(l.colors[2], l.opacity, size: w * 0.9)
                        .offset(x: drift ? -w * 0.05 : w * 0.25, y: drift ? h * 0.30 : h * 0.15)
                }
                if l.stars { stars(w: w, h: h) }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion, AppModel.shared.prefs.data.animations else { return }
            withAnimation(.easeInOut(duration: l.seconds).repeatForever(autoreverses: true)) { drift = true }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { twinkle = true }
        }
    }

    private func blob(_ hex: String, _ opacity: Double, size: CGFloat) -> some View {
        Circle().fill(Color(hex: hex).opacity(opacity)).frame(width: size, height: size).blur(radius: 90)
    }

    /// Tiny stars in fixed spots; half of them fade in while the other half fade out.
    private func stars(w: CGFloat, h: CGFloat) -> some View {
        var rng = SeededRNG(seed: 42)
        let points = (0..<46).map { i -> (CGFloat, CGFloat, CGFloat, Bool) in
            (CGFloat.random(in: 0...w, using: &rng), CGFloat.random(in: 0...h, using: &rng),
             CGFloat.random(in: 1...2.4, using: &rng), i.isMultiple(of: 2))
        }
        return ZStack {
            ForEach(points.indices, id: \.self) { i in
                let p = points[i]
                Circle().fill(.white)
                    .frame(width: p.2, height: p.2)
                    .opacity((p.3 == twinkle) ? 0.85 : 0.2)
                    .position(x: p.0, y: p.1)
            }
        }
    }
}

extension View {
    /// Puts the current theme's background behind a screen.
    func themeBackground() -> some View {
        background { ThemeBackground().ignoresSafeArea() }
    }
}
