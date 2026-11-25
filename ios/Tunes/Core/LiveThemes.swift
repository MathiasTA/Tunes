import SwiftUI
import UIKit

/// The looks of the alive themes, which change by themselves: with the weather, the season, the music,
/// the moon, your battery and your listening streak.
@MainActor
enum LiveThemes {
    static func p(_ colors: [String], bar: String, _ scheme: ColorScheme = .dark, glow: [String] = [], accent: String,
                  effect: ThemeEffect = .none, stars: Bool = false, fx: [String] = []) -> ThemePalette {
        ThemePalette(colors: colors.map { Color(hex: $0) }, bar: Color(hex: bar), scheme: scheme, glow: glow.map { Color(hex: $0) },
                     stars: stars, accent: Color(hex: accent), accentHex: accent, effect: effect, effectColors: fx.map { Color(hex: $0) })
    }

    /// The palette for an alive theme right now (nil for the rest).
    static func palette(for theme: ThemeMode, at date: Date, cover: CoverColors?) -> ThemePalette? {
        switch theme {
        case .horizon: return HorizonPhase.at(date).palette
        case .dynamic: return (cover ?? .fallback).palette
        case .weather: return weather(WeatherWatcher.shared.now, date: date)
        case .seasons: return seasons(date)
        case .pulse:
            let mood = AppModel.shared.pulseMood
            let accent = MoodColors.color(mood).mixed(with: .white, by: 0.25)
            return ThemePalette(colors: [MoodColors.color(max(0, mood - 0.2), darken: 0.8), MoodColors.color(mood, darken: 0.9)],
                                bar: MoodColors.color(mood, darken: 0.88), scheme: .dark, accent: accent, accentHex: accent.hexString,
                                effect: .pulse)
        case .moon: return moon(date)
        case .battery: return battery()
        case .streak: return streak(AppModel.shared.streak)
        default: return nil
        }
    }

    /// What the theme is showing right now, for the theme picker.
    static func subtitle(_ theme: ThemeMode, at date: Date = .now) -> String {
        switch theme {
        case .horizon: return "Horizon · \(HorizonPhase.at(date).label)"
        case .weather: return WeatherWatcher.shared.now.map { "Weather · \($0.kind.label)" } ?? "Weather"
        case .seasons: return "Seasons · \(Holiday.at(date)?.label ?? Season.at(date).label)"
        case .moon: return "Moon · \(MoonPhase.name(MoonPhase.at(date)))"
        case .battery:
            let level = UIDevice.current.batteryLevel
            let eco = ProcessInfo.processInfo.isLowPowerModeEnabled ? " · Low Power" : ""
            return level >= 0 ? "Battery · \(Int(level * 100))%\(eco)" : "Battery"
        case .streak:
            let d = AppModel.shared.streak.current
            return "Streak · \(d) day\(d == 1 ? "" : "s")"
        default: return theme.label
        }
    }

    // MARK: Weather

    static func weather(_ w: WeatherNow?, date: Date) -> ThemePalette {
        guard let w else { return HorizonPhase.at(date).palette }
        switch (w.kind, w.isDay) {
        case (.clear, true):
            return p(["#6CB8EA", "#A9DCF7", "#E6F5FD"], bar: "#D6EEFA", .light, glow: ["#FFE08A", "#FFFFFF"], accent: "#0369A1", effect: .clearDay)
        case (.clear, false):
            return p(["#020617", "#0B1736", "#16234D"], bar: "#050B1E", glow: ["#334E99"], accent: "#93C5FD", effect: .clearNight)
        case (.clouds, true):
            return p(["#8FA3B8", "#B6C4D2", "#DCE3EA"], bar: "#D2DBE3", .light, glow: ["#FFFFFF"], accent: "#334155", effect: .clouds)
        case (.clouds, false):
            return p(["#0E1420", "#1A2333", "#273246"], bar: "#101722", glow: ["#475569"], accent: "#CBD5E1", effect: .clouds)
        case (.rain, true):
            return p(["#2B3A4A", "#3C4F63", "#52677D"], bar: "#2A3746", glow: ["#7DA3C4"], accent: "#93C5FD", effect: .rain)
        case (.rain, false):
            return p(["#0B121B", "#152030", "#1F2E42"], bar: "#0D1520", glow: ["#3B5878"], accent: "#93C5FD", effect: .rain)
        case (.snow, true):
            return p(["#C9D6E3", "#E2EAF1", "#F7FAFC"], bar: "#E4EBF2", .light, glow: ["#BFDBFE"], accent: "#1D4ED8", effect: .snow)
        case (.snow, false):
            return p(["#0F172A", "#1E293B", "#334155"], bar: "#111A2E", glow: ["#93C5FD"], accent: "#E0F2FE", effect: .snow)
        case (.thunder, _):
            return p(["#0A0A14", "#161629", "#24243D"], bar: "#0C0C18", glow: ["#6D5BD0"], accent: "#C4B5FD", effect: .thunder)
        case (.fog, true):
            return p(["#A3ABB4", "#C3C9CF", "#E1E4E7"], bar: "#CDD2D7", .light, accent: "#475569", effect: .fog)
        case (.fog, false):
            return p(["#15191E", "#22282F", "#30373F"], bar: "#181C21", accent: "#CBD5E1", effect: .fog)
        }
    }

    // MARK: Seasons

    static func seasons(_ date: Date) -> ThemePalette {
        if let h = Holiday.at(date) { return holiday(h) }
        switch Season.at(date) {
        case .spring:
            return p(["#FDF2F8", "#FCE7F3", "#ECFCCB"], bar: "#FDF0F6", .light, glow: ["#F9A8D4", "#BEF264"], accent: "#DB2777",
                     effect: .blossoms, fx: ["#F9A8D4", "#FBCFE8", "#FFFFFF"])
        case .summer:
            return p(["#FFF7D6", "#FFE7A8", "#FFD08A"], bar: "#FFF3CF", .light, glow: ["#FDE047", "#FB923C"], accent: "#C2410C",
                     effect: .pollen, fx: ["#FDE68A", "#FFFFFF"])
        case .autumn:
            return p(["#1F0F07", "#3B1D0C", "#5A2E12"], bar: "#22110A", glow: ["#EA580C", "#B45309"], accent: "#FB923C",
                     effect: .leaves, fx: ["#EA580C", "#F59E0B", "#B91C1C", "#A16207"])
        case .winter:
            return p(["#0B1426", "#15233F", "#243656"], bar: "#0D172B", glow: ["#93C5FD"], accent: "#BAE6FD", effect: .snow)
        }
    }

    static func holiday(_ h: Holiday) -> ThemePalette {
        switch h {
        case .newYear:
            return p(["#05040F", "#0E0B26", "#1B1440"], bar: "#07061A", glow: ["#F59E0B", "#A855F7"], accent: "#FBBF24",
                     effect: .fireworks, fx: ["#FBBF24", "#F472B6", "#60A5FA", "#34D399", "#FFFFFF"])
        case .valentine:
            return p(["#2A0614", "#4A0B24", "#6B1235"], bar: "#2C0716", glow: ["#FB7185", "#F472B6"], accent: "#FB7185",
                     effect: .hearts, fx: ["#FB7185", "#F9A8D4", "#FDA4AF"])
        case .fastelavn:
            return p(["#1E1036", "#2D1B54", "#3B2470"], bar: "#20123A", glow: ["#F472B6", "#22D3EE"], accent: "#FACC15",
                     effect: .confetti, fx: ["#F472B6", "#FACC15", "#22D3EE", "#A3E635", "#FB923C"])
        case .easter:
            return p(["#FFFBEB", "#FEF3C7", "#ECFCCB"], bar: "#FFF8E1", .light, glow: ["#FDE047", "#BEF264"], accent: "#A16207",
                     effect: .blossoms, fx: ["#FDE047", "#FACC15", "#FFFFFF"])
        case .sanktHans:
            return p(["#0B1030", "#1E1B4B", "#3B2A5A"], bar: "#0D1234", glow: ["#F97316", "#FDE68A"], accent: "#FDBA74",
                     effect: .bonfire, fx: ["#F97316", "#FBBF24", "#FDE68A"])
        case .halloween:
            return p(["#0C0614", "#1F0B2E", "#3B1208"], bar: "#0E0717", glow: ["#F97316", "#7C3AED"], accent: "#FB923C", effect: .bats)
        case .mortensaften:
            return p(["#180C05", "#2C170A", "#40210E"], bar: "#1A0D06", glow: ["#F59E0B", "#B45309"], accent: "#FBBF24",
                     effect: .leaves, fx: ["#D97706", "#B45309", "#92400E", "#FBBF24"])
        case .christmas(let candles):
            return p(["#061A12", "#0B2A1C", "#3A0A0E"], bar: "#071C14", glow: ["#DC2626", "#16A34A"], accent: "#F87171",
                     effect: .christmas(candles: candles), fx: ["#F87171", "#FBBF24", "#4ADE80", "#60A5FA"])
        case .lucia:
            return p(["#050A1F", "#0B1436", "#14204D"], bar: "#060C23", glow: ["#FBBF24"], accent: "#FDE68A", effect: .lucia)
        case .birthday:
            let mine = AppModel.shared.prefs.data.accentHex
            return p(["#1A0B2E", "#2B1050", "#3D1670"], bar: "#1C0C32", glow: [mine, "#F472B6"], accent: mine,
                     effect: .balloons, fx: [mine, "#F472B6", "#FACC15", "#60A5FA", "#34D399"])
        }
    }

    // MARK: Moon, battery, streak

    static func moon(_ date: Date) -> ThemePalette {
        p(["#02030A", "#070B1F", "#0E1533"], bar: "#03050F", glow: ["#1E293B"], accent: "#E2E8F0", effect: .moon(phase: MoonPhase.at(date)))
    }

    static func battery() -> ThemePalette {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        let level = device.batteryLevel < 0 ? 1 : Double(device.batteryLevel)
        let charging = device.batteryState == .charging || device.batteryState == .full
        if charging {
            return p(["#03140E", "#062A1D", "#0A3D2A"], bar: "#04170F", glow: ["#22C55E"], accent: "#4ADE80", effect: .charging)
        }
        var look: ThemePalette
        if level < 0.2 {
            look = p(["#050505", "#0E0606", "#1C0808"], bar: "#070505", glow: ["#DC2626", "#7F1D1D"], accent: "#F87171", effect: .lowBattery)
        } else if level < 0.6 {
            look = p(["#1A1405", "#3A2A08", "#5C420C"], bar: "#1C1506", glow: ["#FACC15", "#F59E0B"], accent: "#FDE047")
        } else {
            look = p(["#0D1B3D", "#2A2470", "#5B2A86"], bar: "#0F1D42", glow: ["#F472B6", "#22D3EE"], accent: "#F0ABFC")
        }
        // Low Power Mode: the same colors for your level, but dimmer and perfectly still.
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            look.colors = look.colors.map { $0.mixed(with: .black, by: 0.4) }
            look.glow = look.glow.map { $0.opacity(0.5) }
            look.effect = .none
        }
        return look
    }

    static func streak(_ s: StreakInfo) -> ThemePalette {
        let fire = ["#F97316", "#FBBF24", "#EA580C"]
        switch s.level {
        case 0: return p(["#111111", "#181818", "#202020"], bar: "#121212", glow: ["#525252"], accent: "#A3A3A3")
        case 1: return p(["#14100C", "#221A12", "#2E2216"], bar: "#15110D", glow: ["#B45309"], accent: "#F59E0B", effect: .streak(level: 1), fx: fire)
        case 2: return p(["#170D07", "#2A140A", "#3C1A0C"], bar: "#180E08", glow: ["#EA580C"], accent: "#FB923C", effect: .streak(level: 2), fx: fire)
        case 3: return p(["#1A0906", "#331008", "#4A160A"], bar: "#1B0A07", glow: ["#F97316", "#DC2626"], accent: "#F97316", effect: .streak(level: 3), fx: fire)
        case 4: return p(["#1C0505", "#3A0A06", "#5A1208"], bar: "#1D0606", glow: ["#F97316", "#FACC15"], accent: "#FDBA74", effect: .streak(level: 4), fx: fire)
        default: return p(["#240302", "#5A0C03", "#9A2A05"], bar: "#260403", glow: ["#FACC15", "#F97316"], accent: "#FDE047", effect: .streak(level: 5), fx: fire)
        }
    }
}

/// Your daily listening streak, and how fiery the Streak theme is (it cools a step for each day you miss).
struct StreakInfo: Equatable {
    var current = 0
    var level = 0
}

enum Season {
    case spring, summer, autumn, winter
    var label: String {
        switch self {
        case .spring: "Spring"
        case .summer: "Summer"
        case .autumn: "Autumn"
        case .winter: "Winter"
        }
    }
    static func at(_ date: Date) -> Season {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }
}

/// Special days the Seasons theme celebrates (Danish calendar), plus your birthday.
enum Holiday: Equatable {
    case newYear, valentine, fastelavn, easter, sanktHans, halloween, mortensaften, christmas(candles: Int), lucia, birthday

    var label: String {
        switch self {
        case .newYear: "New Year"
        case .valentine: "Valentine's Day"
        case .fastelavn: "Fastelavn"
        case .easter: "Easter"
        case .sanktHans: "Sankt Hans"
        case .halloween: "Halloween"
        case .mortensaften: "Mortensaften"
        case .christmas: "Christmas"
        case .lucia: "Lucia"
        case .birthday: "Your birthday"
        }
    }

    @MainActor
    static func at(_ date: Date) -> Holiday? {
        let cal = Calendar.current
        let m = cal.component(.month, from: date), d = cal.component(.day, from: date)
        let prefs = AppModel.shared.prefs.data
        if prefs.birthdayMonth > 0, prefs.birthdayMonth == m, prefs.birthdayDay == d { return .birthday }
        switch (m, d) {
        case (12, 31), (1, 1): return .newYear
        case (2, 14): return .valentine
        case (6, 23): return .sanktHans
        case (10, 31): return .halloween
        case (11, 10): return .mortensaften
        case (12, 13): return .lucia
        case (12, 1...26): return .christmas(candles: adventCandles(date))
        default: break
        }
        let year = cal.component(.year, from: date)
        if let easter = easterSunday(year) {
            let day = cal.startOfDay(for: date)
            let diff = cal.dateComponents([.day], from: easter, to: day).day ?? 999
            if diff == -49 { return .fastelavn }
            if diff >= -7 && diff <= 1 { return .easter }
        }
        return nil
    }

    /// How many Advent candles are lit: one more each Sunday from the 4th Sunday before Christmas.
    static func adventCandles(_ date: Date) -> Int {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        guard let christmasEve = cal.date(from: DateComponents(year: year, month: 12, day: 24)) else { return 1 }
        // 4th Advent: the last Sunday on or before Dec 24.
        let weekday = cal.component(.weekday, from: christmasEve) // 1 = Sunday
        guard let fourth = cal.date(byAdding: .day, value: -(weekday - 1), to: christmasEve) else { return 1 }
        let day = cal.startOfDay(for: date)
        var lit = 0
        for k in 0..<4 {
            if let sunday = cal.date(byAdding: .day, value: -7 * (3 - k), to: fourth), sunday <= day { lit += 1 }
        }
        return max(lit, day >= christmasEve ? 4 : 1)
    }

    /// Easter Sunday (the Gregorian "anonymous" algorithm).
    static func easterSunday(_ y: Int) -> Date? {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return Calendar.current.date(from: DateComponents(year: y, month: month, day: day))
    }
}

enum MoonPhase {
    /// 0 = new moon, 0.5 = full, back to new at 1 (worked out from a known new moon; no internet needed).
    static func at(_ date: Date) -> Double {
        let knownNew = Date(timeIntervalSince1970: 947_182_440) // 6 Jan 2000, 18:14 UTC
        let days = date.timeIntervalSince(knownNew) / 86_400
        let cycle = 29.530588853
        let x = days / cycle
        return x - floor(x)
    }

    static func name(_ p: Double) -> String {
        switch p {
        case ..<0.03, 0.97...: "New moon"
        case ..<0.22: "Waxing crescent"
        case ..<0.28: "First quarter"
        case ..<0.47: "Waxing gibbous"
        case ..<0.53: "Full moon"
        case ..<0.72: "Waning gibbous"
        case ..<0.78: "Last quarter"
        default: "Waning crescent"
        }
    }
}


extension Color {
    /// This color blended toward another (0 = unchanged, 1 = the other color).
    func mixed(with other: Color, by k: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(k)
        return Color(red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t), blue: Double(b1 + (b2 - b1) * t))
    }
}
