import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - Themes

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case dark, black, light, auto
    case dynamic, horizon
    case midnight, sunset, ocean, forest, rose, synthwave, matcha, coffee, arctic, graphite, vapor, abyss
    case aurora, nebula, lava, lagoon, pastel, fireflies, tide, warp
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rose: "Rosé"
        case .dynamic: "Dynamic"
        default: rawValue.capitalized
        }
    }

    /// The plain themes; everything else paints its own background.
    var isClassic: Bool { [.dark, .black, .light, .auto].contains(self) }
    /// Themes whose look changes by themselves (with the song, or with the time of day).
    var isLive: Bool { self == .dynamic || self == .horizon }

    static let groups: [(String, [ThemeMode])] = [
        ("Classic", [.dark, .black, .light, .auto]),
        ("Alive", [.dynamic, .horizon]),
        ("Gradients", [.midnight, .sunset, .ocean, .forest, .rose, .synthwave, .vapor, .abyss, .matcha, .coffee, .arctic, .graphite]),
        ("Animated", [.aurora, .nebula, .fireflies, .tide, .warp, .lava, .lagoon, .pastel]),
    ]

    /// Static look of the gradient and animated themes.
    var palette: ThemePalette? {
        func p(_ colors: [String], bar: String, scheme: ColorScheme = .dark, glow: [String] = [], accent: String,
               lights: [String] = [], opacity: Double = 0.3, seconds: Double = 18, stars: Bool = false, grid: Bool = false,
               effect: ThemeEffect = .none, sun: Bool = false, starColor: String = "#FFFFFF") -> ThemePalette {
            ThemePalette(colors: colors.map { Color(hex: $0) }, bar: Color(hex: bar), scheme: scheme, glow: glow.map { Color(hex: $0) },
                    lights: lights.map { Color(hex: $0) }, lightOpacity: opacity, lightSeconds: seconds, stars: stars, grid: grid,
                    accent: Color(hex: accent), accentHex: accent, effect: effect, sun: sun, starColor: Color(hex: starColor))
        }
        switch self {
        case .midnight: return p(["#0B1026", "#1B1446", "#2E1458"], bar: "#0D1130", glow: ["#6366F1", "#C084FC"], accent: "#A78BFA")
        case .sunset: return p(["#1C0B2B", "#4A1638", "#8C3B2E"], bar: "#1E0C2C", glow: ["#F97316", "#EC4899"], accent: "#FB923C")
        case .ocean: return p(["#03192B", "#053F5C", "#0B7285"], bar: "#041E33", glow: ["#22D3EE", "#3B82F6"], accent: "#22D3EE")
        case .forest: return p(["#06140D", "#0F2A1B", "#1F4A2C"], bar: "#08180F", glow: ["#4ADE80", "#A3E635"], accent: "#86EFAC")
        case .rose: return p(["#FFF1F2", "#FCE7F3", "#EDE9FE"], bar: "#FFF5F8", scheme: .light, glow: ["#F9A8D4", "#C4B5FD"], accent: "#DB2777")
        case .synthwave:
            return p(["#0D0221", "#2A0845", "#6A0F5A"], bar: "#120330", glow: ["#FF2A6D", "#05D9E8"], accent: "#FF2A6D", grid: true)
        case .matcha: return p(["#F4F9EC", "#E3F0CF", "#C9E2A8"], bar: "#F2F8E9", scheme: .light, glow: ["#A3D977", "#FDE68A"], accent: "#4D7C0F")
        case .coffee: return p(["#140D09", "#2E2019", "#4A3326"], bar: "#17100B", glow: ["#D4A373", "#B5651D"], accent: "#E0B583")
        case .arctic: return p(["#F0F9FF", "#E0F2FE", "#DBEAFE"], bar: "#F2FAFF", scheme: .light, glow: ["#7DD3FC", "#C4B5FD"], accent: "#0284C7")
        case .vapor:
            return p(["#FBD3E9", "#C9B6F2", "#9FE7F5"], bar: "#F8E1F0", scheme: .light, glow: ["#FF71CE", "#01CDFE"], accent: "#B026FF", sun: true)
        case .abyss:
            return p(["#010B13", "#022235", "#04364A"], bar: "#021019", glow: ["#00F5D4", "#3A86FF"], accent: "#00F5D4", stars: true, starColor: "#7FFFE8")
        case .fireflies:
            return p(["#030B07", "#071A10"], bar: "#05110A", glow: ["#14532D"], accent: "#D9F99D", effect: .fireflies)
        case .tide:
            return p(["#0B1026", "#0E2A47", "#0F4C5C"], bar: "#0B1A33", accent: "#5EEAD4", effect: .tide)
        case .warp:
            return p(["#05010F", "#0D0420"], bar: "#07021A", glow: ["#7C3AED"], accent: "#C4B5FD", effect: .warp)
        case .graphite: return p(["#0A0A0A", "#1A1A1A", "#2B2B2B"], bar: "#0E0E0E", glow: ["#6B7280", "#D1D5DB"], accent: "#E5E7EB")
        case .aurora: return p(["#050B14"], bar: "#070F1A", accent: "#34D399", lights: ["#10B981", "#8B5CF6", "#0EA5E9"], opacity: 0.32, seconds: 18)
        case .nebula: return p(["#07051A"], bar: "#0A0820", accent: "#E879F9", lights: ["#C026D3", "#4F46E5", "#06B6D4"], opacity: 0.28, seconds: 24, stars: true)
        case .lava: return p(["#130606"], bar: "#1A0909", accent: "#FB923C", lights: ["#F97316", "#DC2626", "#DB2777"], opacity: 0.30, seconds: 14)
        case .lagoon: return p(["#03161A"], bar: "#041B20", accent: "#2DD4BF", lights: ["#14B8A6", "#22D3EE", "#4ADE80"], opacity: 0.26, seconds: 20)
        case .pastel: return p(["#FFF9F5"], bar: "#FFF8F6", scheme: .light, accent: "#EC4899", lights: ["#F9A8D4", "#FDBA74", "#C4B5FD"], opacity: 0.45, seconds: 22)
        default: return nil
        }
    }

    /// The accent picked automatically when you choose this theme (you can still change it).
    var suggestedAccent: String? { palette?.accentHex }

    /// The light/dark mode the theme needs (nil = follow the iPhone).
    var scheme: ColorScheme? {
        switch self {
        case .light: .light
        case .auto: nil
        default: palette?.scheme ?? .dark
        }
    }
}

/// Everything that decides how a non-classic theme looks.
struct ThemePalette: Equatable {
    var colors: [Color]
    var bar: Color
    var scheme: ColorScheme
    var glow: [Color] = []
    var lights: [Color] = []
    var lightOpacity: Double = 0.3
    var lightSeconds: Double = 18
    var stars = false
    var grid = false
    /// Accent the theme sets (Dynamic and Horizon always use theirs).
    var accent: Color?
    var accentHex: String?
    /// Special moving scenes (fireflies, waves, stars flying by).
    var effect: ThemeEffect = .none
    /// A big retro sun with stripes (Vapor).
    var sun = false
    var starColor: Color = .white
}

enum ThemeEffect: Equatable { case none, fireflies, tide, warp }

// MARK: - Horizon: a theme that follows the sky

enum HorizonPhase: String, CaseIterable {
    case night, dawn, sunrise, day, goldenHour, sunset, dusk

    var label: String {
        switch self {
        case .night: "Night"
        case .dawn: "Dawn"
        case .sunrise: "Sunrise"
        case .day: "Day"
        case .goldenHour: "Golden hour"
        case .sunset: "Sunset"
        case .dusk: "Dusk"
        }
    }

    static func at(_ date: Date) -> HorizonPhase {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        switch h {
        case 5..<6.5: return .dawn
        case 6.5..<9: return .sunrise
        case 9..<17: return .day
        case 17..<19: return .goldenHour
        case 19..<20.5: return .sunset
        case 20.5..<22: return .dusk
        default: return .night
        }
    }

    var palette: ThemePalette {
        func p(_ c: [String], bar: String, _ scheme: ColorScheme, glow: [String], accent: String, stars: Bool = false) -> ThemePalette {
            ThemePalette(colors: c.map { Color(hex: $0) }, bar: Color(hex: bar), scheme: scheme, glow: glow.map { Color(hex: $0) },
                    stars: stars, accent: Color(hex: accent), accentHex: accent)
        }
        switch self {
        case .night: return p(["#03050F", "#0A1030", "#141A45"], bar: "#050817", .dark, glow: ["#312E81", "#1E3A8A"], accent: "#A5B4FC", stars: true)
        case .dawn: return p(["#1E1B4B", "#6B2F6B", "#E07A5F"], bar: "#1C1A44", .dark, glow: ["#F28C6B", "#A855F7"], accent: "#FDA4AF")
        case .sunrise: return p(["#FFE4C7", "#FECACA", "#FEF3C7"], bar: "#FFF1E3", .light, glow: ["#FDBA74", "#FDE68A"], accent: "#EA580C")
        case .day: return p(["#BFE6FF", "#E0F2FE", "#F8FAFC"], bar: "#F1F8FF", .light, glow: ["#7DD3FC", "#FDE68A"], accent: "#0284C7")
        case .goldenHour: return p(["#FFF1C1", "#FDD08A", "#F7A35C"], bar: "#FFF3D6", .light, glow: ["#FBBF24", "#F97316"], accent: "#C2410C")
        case .sunset: return p(["#2E1065", "#9D174D", "#F97316"], bar: "#2A0E5C", .dark, glow: ["#FB923C", "#EC4899"], accent: "#FDBA74")
        case .dusk: return p(["#0F0C29", "#302B63", "#5B2A86"], bar: "#110E2E", .dark, glow: ["#A855F7", "#6366F1"], accent: "#E879F9", stars: true)
        }
    }
}

// MARK: - Dynamic: a theme made from the cover that's playing

/// Colors taken from a cover: a background color and a bright accent.
struct CoverColors: Equatable {
    var top: Color
    var bottom: Color
    var accent: Color
    var accentHex: String

    var palette: ThemePalette {
        ThemePalette(colors: [top, bottom.opacity(1)], bar: bottom, scheme: .dark, glow: [accent],
                accent: accent, accentHex: accentHex)
    }

    static let fallback = CoverColors(top: Color(hex: "#1F2937"), bottom: Color(hex: "#0B0F19"),
                                      accent: Color(hex: "#34D399"), accentHex: "#34D399")

    /// Average color of each quarter of the cover; the most colorful one becomes the accent.
    static func extract(from image: UIImage) async -> CoverColors? {
        guard let cg = image.cgImage else { return nil }
        return await Task.detached(priority: .utility) { () -> CoverColors? in
            let ci = CIImage(cgImage: cg)
            let ctx = CIContext(options: [.workingColorSpace: NSNull()])
            let e = ci.extent
            let quads = [CGRect(x: e.minX, y: e.midY, width: e.width / 2, height: e.height / 2),
                         CGRect(x: e.midX, y: e.midY, width: e.width / 2, height: e.height / 2),
                         CGRect(x: e.minX, y: e.minY, width: e.width / 2, height: e.height / 2),
                         CGRect(x: e.midX, y: e.minY, width: e.width / 2, height: e.height / 2)]
            func average(_ r: CGRect) -> UIColor? {
                let f = CIFilter.areaAverage()
                f.inputImage = ci
                f.extent = r
                guard let out = f.outputImage else { return nil }
                var px = [UInt8](repeating: 0, count: 4)
                ctx.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                return UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            }
            let colors = quads.compactMap(average)
            guard colors.count == 4 else { return nil }
            func hsb(_ c: UIColor) -> (CGFloat, CGFloat, CGFloat) {
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                return (h, s, b)
            }
            let vivid = colors.max { hsb($0).1 * hsb($0).2 < hsb($1).1 * hsb($1).2 } ?? colors[0]
            let (ah, asat, ab) = hsb(vivid)
            let accent = UIColor(hue: ah, saturation: max(0.45, min(0.85, asat * 1.2)), brightness: max(0.85, ab), alpha: 1)
            func darkened(_ c: UIColor, _ target: CGFloat) -> UIColor {
                let (h, s, b) = hsb(c)
                return UIColor(hue: h, saturation: min(0.9, s * 1.1), brightness: min(b, target), alpha: 1)
            }
            let topAvg = colors[0].blended(with: colors[1])
            let bottomAvg = colors[2].blended(with: colors[3])
            return CoverColors(top: Color(darkened(topAvg, 0.42)), bottom: Color(darkened(bottomAvg, 0.16)),
                               accent: Color(accent), accentHex: accent.hexString)
        }.value
    }
}

extension UIColor {
    func blended(with other: UIColor) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: (r1 + r2) / 2, green: (g1 + g2) / 2, blue: (b1 + b2) / 2, alpha: 1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

extension Color {
    var hexString: String { UIColor(self).hexString }
}

// MARK: - Fonts

enum AppFont: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, serif, mono, condensed, expanded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: "Default"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .mono: "Mono"
        case .condensed: "Condensed"
        case .expanded: "Wide"
        }
    }
    var design: Font.Design {
        switch self {
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        default: .default
        }
    }
    var width: Font.Width {
        switch self {
        case .condensed: .condensed
        case .expanded: .expanded
        default: .standard
        }
    }
}

extension View {
    /// Applies the chosen app font everywhere below.
    func appFont(_ f: AppFont) -> some View {
        fontDesign(f.design).fontWidth(f.width)
    }
}

// MARK: - Backgrounds

/// The full-screen background for the current theme: a plain color, a gradient with glows, or drifting light.
struct ThemeBackground: View {
    @Environment(\.look) private var look

    var body: some View {
        Group {
            if let p = look.palette {
                if p.effect != .none {
                    AnimatedScene(palette: p).id(look.theme)
                } else if !p.lights.isEmpty {
                    DriftingLights(palette: p).id(look.theme)
                } else {
                    GlowGradient(palette: p)
                }
            } else {
                Surface.background(look)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: look.palette)
    }
}

/// A gradient with soft, still glows for depth (plus stars or a retro grid on some themes).
private struct GlowGradient: View {
    let palette: ThemePalette
    var body: some View {
        let light = palette.scheme == .light
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: palette.colors.count > 1 ? palette.colors : palette.colors + palette.colors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let a = palette.glow.first {
                    RadialGradient(colors: [a.opacity(light ? 0.35 : 0.30), .clear], center: .topTrailing,
                                   startRadius: 0, endRadius: max(w, h) * 0.7)
                }
                if palette.glow.count > 1 {
                    RadialGradient(colors: [palette.glow[1].opacity(light ? 0.30 : 0.22), .clear],
                                   center: UnitPoint(x: 0.1, y: 0.75), startRadius: 0, endRadius: max(w, h) * 0.6)
                }
                if palette.sun { RetroSun().frame(width: w * 0.7, height: w * 0.7).position(x: w * 0.5, y: h * 0.62) }
                if palette.grid { RetroGrid(color: palette.glow.last ?? .cyan).frame(height: h * 0.38).frame(maxHeight: .infinity, alignment: .bottom) }
                if palette.stars { Stars(count: 40, twinkle: false, color: palette.starColor) }
                LinearGradient(colors: [.clear, (light ? Color.white : Color.black).opacity(0.25)],
                               startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
            }
        }
    }
}

/// Synthwave's glowing floor grid.
private struct RetroGrid: View {
    let color: Color
    var body: some View {
        Canvas { gc, size in
            var p = Path()
            let horizon = size.height * 0.05
            for i in 0...10 {
                let t = Double(i) / 10
                let y = horizon + (size.height - horizon) * t * t
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            }
            for i in -8...8 {
                let x0 = size.width / 2 + CGFloat(i) * size.width * 0.06
                let x1 = size.width / 2 + CGFloat(i) * size.width * 0.32
                p.move(to: CGPoint(x: x0, y: horizon)); p.addLine(to: CGPoint(x: x1, y: size.height))
            }
            gc.stroke(p, with: .color(color.opacity(0.35)), lineWidth: 1)
        }
        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
    }
}

/// Tiny stars in fixed spots; with `twinkle`, half of them fade in while the other half fade out.
struct Stars: View {
    let count: Int
    let twinkle: Bool
    var color: Color = .white
    @State private var on = false

    var body: some View {
        GeometryReader { g in
            var rng = SeededRNG(seed: 42)
            let points = (0..<count).map { i -> (CGFloat, CGFloat, CGFloat, Bool) in
                (CGFloat.random(in: 0...g.size.width, using: &rng), CGFloat.random(in: 0...g.size.height * 0.7, using: &rng),
                 CGFloat.random(in: 1...2.4, using: &rng), i.isMultiple(of: 2))
            }
            ZStack {
                ForEach(points.indices, id: \.self) { i in
                    let p = points[i]
                    Circle().fill(color)
                        .frame(width: p.2, height: p.2)
                        .opacity(twinkle ? ((p.3 == on) ? 0.85 : 0.2) : 0.55)
                        .position(x: p.0, y: p.1)
                }
            }
        }
        .onAppear {
            guard twinkle, AppModel.shared.prefs.data.animations else { return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

/// Three large, heavily blurred lights that drift slowly back and forth. Only offsets animate, so it's cheap to draw.
private struct DriftingLights: View {
    let palette: ThemePalette
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let l = palette.lights
            ZStack {
                palette.colors.first ?? .black
                if l.count == 3 {
                    blob(l[0], size: w * 1.1).offset(x: drift ? -w * 0.25 : w * 0.15, y: drift ? -h * 0.30 : -h * 0.18)
                    blob(l[1], size: w * 1.0).offset(x: drift ? w * 0.30 : -w * 0.10, y: drift ? -h * 0.05 : -h * 0.25)
                    blob(l[2], size: w * 0.9).offset(x: drift ? -w * 0.05 : w * 0.25, y: drift ? h * 0.30 : h * 0.15)
                }
                if palette.stars { Stars(count: 46, twinkle: true) }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion, AppModel.shared.prefs.data.animations else { return }
            withAnimation(.easeInOut(duration: palette.lightSeconds).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func blob(_ c: Color, size: CGFloat) -> some View {
        Circle().fill(c.opacity(palette.lightOpacity)).frame(width: size, height: size).blur(radius: 90)
    }
}

extension View {
    /// Puts the current theme's background behind a screen.
    func themeBackground() -> some View {
        background { ThemeBackground().ignoresSafeArea() }
    }
}


/// Vapor's sun: a soft gradient disc cut by horizontal stripes.
private struct RetroSun: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(hex: "#FFE66D"), Color(hex: "#FF71CE")], startPoint: .top, endPoint: .bottom))
            .mask {
                VStack(spacing: 0) {
                    Rectangle().frame(maxHeight: .infinity)
                    ForEach(0..<6, id: \.self) { i in
                        Rectangle().fill(.clear).frame(height: CGFloat(2 + i * 2))
                        Rectangle().frame(height: 10)
                    }
                }
            }
            .opacity(0.55)
            .blur(radius: 1)
    }
}

/// Fireflies, Tide and Warp: small scenes drawn 30 times a second (still when Animations is off).
struct AnimatedScene: View {
    let palette: ThemePalette
    var still = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = !still && !reduceMotion && AppModel.shared.prefs.data.animations
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { ctx in
            let t = moving ? ctx.date.timeIntervalSinceReferenceDate : 1000
            Canvas { gc, size in
                gc.fill(Path(CGRect(origin: .zero, size: size)),
                        with: .linearGradient(Gradient(colors: palette.colors.count > 1 ? palette.colors : palette.colors + palette.colors),
                                              startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
                switch palette.effect {
                case .fireflies: Self.fireflies(&gc, size, t, glow: palette.accent ?? .yellow)
                case .tide: Self.tide(&gc, size, t, color: palette.accent ?? .teal)
                case .warp: Self.warp(&gc, size, t, glow: palette.glow.first ?? .purple)
                case .none: break
                }
            }
        }
    }

    /// Glowing dots wandering slowly and pulsing, each on its own path.
    static func fireflies(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double, glow: Color) {
        var rng = SeededRNG(seed: 7)
        for _ in 0..<28 {
            let bx = Double.random(in: 0...1, using: &rng), by = Double.random(in: 0.15...1, using: &rng)
            let sp = Double.random(in: 0.05...0.12, using: &rng), ph = Double.random(in: 0...6.28, using: &rng)
            let x = (bx + 0.06 * sin(t * sp * 2 + ph) + 0.03 * sin(t * sp * 5 + ph * 2)) * size.width
            let y = (by + 0.05 * cos(t * sp * 1.6 + ph)) * size.height
            let pulse = 0.35 + 0.65 * max(0, sin(t * 0.9 + ph * 3))
            let r = 2.2 + 1.2 * pulse
            gc.fill(Path(ellipseIn: CGRect(x: x - r * 5, y: y - r * 5, width: r * 10, height: r * 10)),
                    with: .radialGradient(Gradient(colors: [glow.opacity(0.35 * pulse), .clear]),
                                          center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 5))
            gc.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(glow.opacity(0.6 + 0.4 * pulse)))
        }
    }

    /// Layers of slow waves rolling along the bottom of the screen.
    static func tide(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double, color: Color) {
        let layers = 4
        for i in 0..<layers {
            let k = Double(i)
            let base = size.height * (0.55 + 0.1 * k)
            let amp = 18.0 + 8 * k
            let speed = 0.25 + 0.12 * k
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height))
            var x = 0.0
            while x <= size.width + 8 {
                let y = base + sin(x / (90 + 25 * k) + t * speed + k) * amp + sin(x / 41 - t * speed * 1.7) * amp * 0.25
                p.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.closeSubpath()
            gc.fill(p, with: .color(color.opacity(0.08 + 0.05 * k)))
        }
    }

    /// Stars streaming slowly out from the middle, like gliding through space.
    static func warp(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double, glow: Color) {
        let c = CGPoint(x: size.width / 2, y: size.height * 0.4)
        gc.fill(Path(ellipseIn: CGRect(x: c.x - size.width * 0.6, y: c.y - size.width * 0.6, width: size.width * 1.2, height: size.width * 1.2)),
                with: .radialGradient(Gradient(colors: [glow.opacity(0.25), .clear]), center: c, startRadius: 0, endRadius: size.width * 0.6))
        var rng = SeededRNG(seed: 11)
        let reach = hypot(size.width, size.height) * 0.6
        for _ in 0..<90 {
            let angle = Double.random(in: 0...(2 * .pi), using: &rng)
            let offset = Double.random(in: 0...1, using: &rng)
            let speed = Double.random(in: 0.04...0.09, using: &rng)
            let d = (offset + t * speed).truncatingRemainder(dividingBy: 1) // 0 → 1, then starts over
            let dist = d * d * reach
            let x = c.x + cos(angle) * dist, y = c.y + sin(angle) * dist
            let len = 2 + d * 14
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x - cos(angle) * len, y: y - sin(angle) * len))
            gc.stroke(line, with: .color(.white.opacity(0.15 + 0.7 * d)), lineWidth: 0.8 + d * 1.4)
        }
    }
}
