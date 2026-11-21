import Foundation
import Observation
import SwiftUI
import UIKit

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case dark, light, auto, black
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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
    var id: String { kind.rawValue }
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

    var colorScheme: ColorScheme? {
        switch data.theme {
        case .dark, .black: .dark
        case .light: .light
        case .auto: nil
        }
    }
}

/// Colors and shapes derived from appearance settings, available to every view.
struct Look: Equatable {
    var accent: Color = Color(hex: "#34D399")
    var black = false
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
             black: data.theme == .black,
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

    static func background(_ look: Look) -> Color {
        look.black ? .black : dynamic(light: .systemBackground, dark: gray(0.075))
    }
    static func card(_ look: Look) -> Color {
        look.black ? Color(white: 0.08) : dynamic(light: .secondarySystemBackground, dark: gray(0.13))
    }
    static func raised(_ look: Look) -> Color {
        look.black ? Color(white: 0.13) : dynamic(light: .tertiarySystemBackground, dark: gray(0.18))
    }
    /// Background behind grouped settings lists.
    static func grouped(_ look: Look) -> Color {
        look.black ? .black : dynamic(light: .systemGroupedBackground, dark: gray(0.075))
    }
    /// Row color inside grouped settings lists.
    static func groupedRow(_ look: Look) -> Color {
        look.black ? Color(white: 0.09) : dynamic(light: .secondarySystemGroupedBackground, dark: gray(0.14))
    }
}

/// Applies the theme's colors to a Form or List of settings.
struct ThemedForm: ViewModifier {
    @Environment(\.look) private var look
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Surface.grouped(look).ignoresSafeArea())
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
