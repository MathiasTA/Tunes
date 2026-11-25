import SwiftUI
import UIKit

// MARK: - Effects

/// The little moving scene a theme draws on top of its background.
enum ThemeEffect: Equatable {
    case none
    // Animated themes
    case fireflies, tide, warp, ribbons, dust, lavaLamp, caustics, bubbles
    // Medal themes
    case embers, glint, sparkles
    // Weather
    case clearDay, clearNight, clouds, rain, snow, thunder, fog
    // Seasons and holidays
    case blossoms, pollen, leaves, fireworks, hearts, confetti, bonfire, bats, christmas(candles: Int), lucia, balloons
    // Other alive themes
    case moon(phase: Double)
    case pulse
    case charging
    case streak(level: Int)
}

/// Draws a theme's effect, about 30 times a second. Holds still when Animations or Reduce Motion is off,
/// and in the small previews in Appearance.
struct EffectLayer: View {
    let palette: ThemePalette
    var still = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = !still && !reduceMotion && AppModel.shared.prefs.data.animations
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { ctx in
            let t = moving ? ctx.date.timeIntervalSinceReferenceDate : 1000
            let level = palette.effect == .pulse ? PulseMeter.shared.level(at: ctx.date, moving: moving) : 0
            Canvas { gc, size in
                EffectPainter.draw(palette, in: &gc, size: size, t: t, level: level)
            }
        }
        .allowsHitTesting(false)
    }
}

/// How loud the song is right now, smoothed so Pulse breathes with phrases rather than flickering on every beat.
@MainActor
final class PulseMeter {
    static let shared = PulseMeter()
    private var songID: Int?
    private var blocks: [Float] = []
    private var smooth: Double = 0
    private var last = Date.distantPast

    func level(at date: Date, moving: Bool) -> Double {
        let p = AppModel.shared.player
        guard moving else { return 0.35 }
        if p.currentID != songID {
            songID = p.currentID
            blocks = songID.flatMap { AnalysisCache.load($0)?.blocks } ?? []
        }
        var target = 0.0
        if p.isPlaying, !blocks.isEmpty {
            let i = Int(p.position / AudioAnalysis.blockSeconds)
            let lo = max(0, i - 4), hi = min(blocks.count - 1, i + 4)
            if lo <= hi { target = Double(blocks[lo...hi].reduce(0, +)) / Double(hi - lo + 1) }
        }
        let dt = min(0.2, max(0, date.timeIntervalSince(last)))
        last = date
        smooth += (target - smooth) * min(1, dt * 1.5)
        return smooth
    }
}

enum EffectPainter {
    static func frac(_ x: Double) -> Double { x - floor(x) }

    static func colors(_ p: ThemePalette) -> [Color] {
        if !p.effectColors.isEmpty { return p.effectColors }
        if !p.lights.isEmpty { return p.lights }
        if !p.glow.isEmpty { return p.glow }
        return [p.accent ?? .white]
    }

    static func draw(_ p: ThemePalette, in gc: inout GraphicsContext, size s: CGSize, t: Double, level: Double) {
        let cs = colors(p)
        let accent = p.accent ?? .white
        switch p.effect {
        case .none: break
        case .fireflies: fireflies(&gc, s, t, glow: accent)
        case .tide: tide(&gc, s, t, color: accent)
        case .warp: warp(&gc, s, t, glow: p.glow.first ?? .purple)
        case .ribbons: ribbons(&gc, s, t, cs)
        case .dust: dust(&gc, s, t, cs)
        case .lavaLamp: lavaLamp(&gc, s, t, cs)
        case .caustics: caustics(&gc, s, t, accent)
        case .bubbles: bubbles(&gc, s, t, cs)
        case .embers: embers(&gc, s, t, cs, count: 46)
        case .glint: glint(&gc, s, t)
        case .sparkles: sparkles(&gc, s, t, cs)
        case .clearDay: clearDay(&gc, s, t)
        case .clearNight: starsField(&gc, s, t, count: 70, shooting: true)
        case .clouds: clouds(&gc, s, t, dark: p.scheme == .dark)
        case .rain: rain(&gc, s, t)
        case .snow: snow(&gc, s, t, count: 70)
        case .thunder: rain(&gc, s, t); lightning(&gc, s, t)
        case .fog: fog(&gc, s, t, dark: p.scheme == .dark)
        case .blossoms: blossoms(&gc, s, t, cs)
        case .pollen: pollen(&gc, s, t, cs)
        case .leaves: leaves(&gc, s, t, cs)
        case .fireworks: fireworks(&gc, s, t, cs)
        case .hearts: hearts(&gc, s, t, cs)
        case .confetti: confetti(&gc, s, t, cs, count: 60)
        case .bonfire: bottomGlow(&gc, s, t, cs.first ?? .orange, strength: 1); embers(&gc, s, t, cs, count: 40)
        case .bats: bigMoon(&gc, s); bats(&gc, s, t)
        case .christmas(let n): snow(&gc, s, t, count: 45); fairyLights(&gc, s, t, cs); candles(&gc, s, t, count: 4, lit: n)
        case .lucia: candles(&gc, s, t, count: 7, lit: 7); starsField(&gc, s, t, count: 30, shooting: false)
        case .balloons: balloons(&gc, s, t, cs); confetti(&gc, s, t, cs, count: 24)
        case .moon(let phase): starsField(&gc, s, t, count: 60, shooting: false); moon(&gc, s, phase: phase)
        case .pulse: pulse(&gc, s, t, level: level, a: accent, b: p.glow.first ?? accent)
        case .charging: charging(&gc, s, t, accent)
        case .streak(let level):
            if level > 0 {
                bottomGlow(&gc, s, t, cs.first ?? .orange, strength: Double(level) / 5)
                embers(&gc, s, t, cs, count: 6 * level)
            }
        }
    }

    // MARK: Animated themes

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

    static func tide(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double, color: Color) {
        for i in 0..<4 {
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
            let d = frac(offset + t * speed)
            let dist = d * d * reach
            let x = c.x + cos(angle) * dist, y = c.y + sin(angle) * dist
            let len = 2 + d * 14
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x - cos(angle) * len, y: y - sin(angle) * len))
            gc.stroke(line, with: .color(.white.opacity(0.15 + 0.7 * d)), lineWidth: 0.8 + d * 1.4)
        }
    }

    /// Aurora: glowing curtains hanging from the top, swaying.
    static func ribbons(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        for k in 0..<3 {
            let c = cs[k % cs.count]
            let kk = Double(k)
            var x = -6.0
            while x < s.width + 6 {
                let top = s.height * (0.06 + 0.07 * kk) + sin(x / (150 + 30 * kk) + t * 0.16 + kk * 2) * 30 + sin(x / 53 - t * 0.27) * 8
                let len = 90 + 80 * (0.5 + 0.5 * sin(x / 95 + t * 0.22 + kk))
                let a = 0.07 + 0.09 * (0.5 + 0.5 * sin(x / 37 + t * 0.5 + kk * 3))
                var p = Path()
                p.move(to: CGPoint(x: x, y: top))
                p.addLine(to: CGPoint(x: x, y: top + len))
                gc.stroke(p, with: .linearGradient(Gradient(colors: [c.opacity(0), c.opacity(a), c.opacity(0)]),
                                                   startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: top + len)),
                          lineWidth: 3.4)
                x += 3
            }
        }
    }

    /// Nebula: a slow swirl of glittering dust around a soft core.
    static func dust(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        let c = CGPoint(x: s.width * 0.5, y: s.height * 0.36)
        gc.fill(Path(ellipseIn: CGRect(x: c.x - s.width * 0.4, y: c.y - s.width * 0.25, width: s.width * 0.8, height: s.width * 0.5)),
                with: .radialGradient(Gradient(colors: [(cs.first ?? .purple).opacity(0.22), .clear]), center: c, startRadius: 0, endRadius: s.width * 0.4))
        var rng = SeededRNG(seed: 21)
        for i in 0..<150 {
            let arm = Double(i % 2) * .pi
            let r = Double.random(in: 0.06...1, using: &rng)
            let jitter = Double.random(in: -0.4...0.4, using: &rng)
            let size = Double.random(in: 0.8...2.2, using: &rng)
            let ang = arm + r * 4.2 + jitter + t * 0.035 * (1.3 - r)
            let dist = r * s.width * 0.75
            let x = c.x + cos(ang) * dist, y = c.y + sin(ang) * dist * 0.55
            let twinkle = 0.5 + 0.5 * sin(t * 1.3 + Double(i))
            let col = i % 5 == 0 ? Color.white : cs[i % cs.count]
            gc.fill(Path(ellipseIn: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)),
                    with: .color(col.opacity((0.2 + 0.5 * twinkle) * (1 - r * 0.55))))
        }
    }

    /// Lava: blobs rising and merging like a lava lamp.
    static func lavaLamp(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        let color = cs.first ?? .orange
        gc.drawLayer { ctx in
            ctx.opacity = 0.42
            ctx.addFilter(.alphaThreshold(min: 0.5, color: color))
            ctx.addFilter(.blur(radius: 22))
            ctx.drawLayer { inner in
                var rng = SeededRNG(seed: 5)
                inner.fill(Path(ellipseIn: CGRect(x: -s.width * 0.1, y: s.height * 0.93, width: s.width * 1.2, height: 160)), with: .color(.white))
                inner.fill(Path(ellipseIn: CGRect(x: -s.width * 0.1, y: -110, width: s.width * 1.2, height: 140)), with: .color(.white))
                for _ in 0..<7 {
                    let bx = Double.random(in: 0.1...0.9, using: &rng)
                    let sp = Double.random(in: 0.012...0.022, using: &rng)
                    let off = Double.random(in: 0...1, using: &rng)
                    let r = Double.random(in: 28...62, using: &rng)
                    let ph = Double.random(in: 0...6.28, using: &rng)
                    // Up and back down, slowly, like warm wax
                    let cycle = frac(off + t * sp)
                    let up = 0.5 - 0.5 * cos(cycle * 2 * .pi)
                    let y = s.height * (1.02 - up * 1.04)
                    let x = (bx + 0.07 * sin(t * 0.15 + ph)) * s.width
                    let stretch = 1 + 0.18 * sin(t * 0.4 + ph)
                    inner.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * stretch, width: r * 2, height: r * 2 * stretch)), with: .color(.white))
                }
            }
        }
    }

    /// Lagoon: rippling light patterns, like sunlight on a pool floor.
    static func caustics(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ color: Color) {
        for family in 0..<2 {
            for i in 0..<13 {
                let k = Double(i)
                var p = Path()
                let length = family == 0 ? s.width : s.height
                let spacing = (family == 0 ? s.height : s.width) / 12
                var u = -10.0
                var first = true
                while u <= length + 10 {
                    let off = sin(u / 70 + t * 0.45 + k * 1.7) * 14 + sin(u / 29 - t * 0.8 + k * 2.3) * 5
                    let pt = family == 0 ? CGPoint(x: u, y: k * spacing + off) : CGPoint(x: k * spacing + off, y: u)
                    if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                    u += 10
                }
                let a = 0.05 + 0.05 * (0.5 + 0.5 * sin(t * 0.7 + k + Double(family) * 2))
                gc.stroke(p, with: .color(color.opacity(a)), lineWidth: 1.6)
            }
        }
    }

    /// Pastel: soft bubbles floating up.
    static func bubbles(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        var rng = SeededRNG(seed: 9)
        for i in 0..<18 {
            let bx = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.015...0.035, using: &rng)
            let off = Double.random(in: 0...1, using: &rng)
            let r = Double.random(in: 8...26, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let y = s.height * (1.1 - frac(off + t * sp) * 1.3)
            let x = (bx + 0.04 * sin(t * 0.5 + ph)) * s.width
            let c = cs[i % cs.count]
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            gc.fill(Path(ellipseIn: rect), with: .color(c.opacity(0.12)))
            gc.stroke(Path(ellipseIn: rect), with: .color(c.opacity(0.4)), lineWidth: 1.2)
            gc.fill(Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.55, width: r * 0.3, height: r * 0.22)), with: .color(.white.opacity(0.55)))
        }
    }

    // MARK: Medal themes

    static func embers(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color], count: Int) {
        var rng = SeededRNG(seed: 13)
        for i in 0..<count {
            let bx = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.04...0.09, using: &rng)
            let off = Double.random(in: 0...1, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let q = frac(off + t * sp)
            let y = s.height * (1.04 - q * 1.0)
            let x = (bx + 0.03 * sin(t * 0.8 + ph) + q * 0.04) * s.width
            let flicker = 0.6 + 0.4 * sin(t * 7 + ph * 5)
            let fade = (1 - q) * flicker
            let r = 1.2 + 1.4 * (1 - q)
            let c = cs[i % cs.count]
            gc.fill(Path(ellipseIn: CGRect(x: x - r * 4, y: y - r * 4, width: r * 8, height: r * 8)),
                    with: .radialGradient(Gradient(colors: [c.opacity(0.3 * fade), .clear]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 4))
            gc.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(c.opacity(0.9 * fade)))
        }
    }

    /// Silver: brushed metal, with a glint of light sweeping across now and then.
    static func glint(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        var rng = SeededRNG(seed: 17)
        for _ in 0..<70 {
            let y = Double.random(in: 0...1, using: &rng) * s.height
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: s.width, y: y))
            gc.stroke(p, with: .color(.white.opacity(Double.random(in: 0.015...0.05, using: &rng))), lineWidth: Double.random(in: 0.5...1.5, using: &rng))
        }
        let q = frac(t / 7)
        let cx = -s.width * 0.6 + q * s.width * 2.6
        let band = s.width * 0.18
        var p = Path()
        p.move(to: CGPoint(x: cx - band, y: 0)); p.addLine(to: CGPoint(x: cx + band, y: 0))
        p.addLine(to: CGPoint(x: cx + band - s.height * 0.45, y: s.height)); p.addLine(to: CGPoint(x: cx - band - s.height * 0.45, y: s.height))
        p.closeSubpath()
        gc.fill(p, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.16), .clear]),
                                         startPoint: CGPoint(x: cx - band, y: 0), endPoint: CGPoint(x: cx + band, y: 0)))
    }

    /// Gold: twinkling four-pointed sparkles and a slow shimmer.
    static func sparkles(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        let q = frac(t / 11)
        let cx = -s.width * 0.5 + q * s.width * 2
        gc.fill(Path(CGRect(origin: .zero, size: s)),
                with: .linearGradient(Gradient(colors: [.clear, (cs.first ?? .yellow).opacity(0.1), .clear]),
                                      startPoint: CGPoint(x: cx - s.width * 0.3, y: 0), endPoint: CGPoint(x: cx + s.width * 0.3, y: s.height * 0.5)))
        var rng = SeededRNG(seed: 19)
        for i in 0..<28 {
            let x = Double.random(in: 0...1, using: &rng) * s.width
            let y = Double.random(in: 0...1, using: &rng) * s.height
            let sp = Double.random(in: 0.5...1.2, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let big = Double.random(in: 4...10, using: &rng)
            let k = pow(max(0, sin(t * sp + ph)), 3)
            guard k > 0.02 else { continue }
            gc.fill(star4(CGPoint(x: x, y: y), big * k), with: .color(cs[i % cs.count].opacity(0.85 * k)))
        }
    }

    static func star4(_ c: CGPoint, _ r: Double) -> Path {
        var p = Path()
        let w = r * 0.22
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - w, y: c.y - w))
        return p
    }

    // MARK: Weather

    static func clearDay(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        let c = CGPoint(x: s.width * 0.85, y: s.height * 0.06)
        let breathe = 0.5 + 0.5 * sin(t * 0.3)
        gc.fill(Path(ellipseIn: CGRect(x: c.x - s.width, y: c.y - s.width, width: s.width * 2, height: s.width * 2)),
                with: .radialGradient(Gradient(colors: [Color(hex: "#FFF7D1").opacity(0.55 + 0.1 * breathe), .clear]),
                                      center: c, startRadius: 0, endRadius: s.width * 0.9))
        for i in 0..<9 {
            let a = Double(i) / 9 * 2 * .pi + t * 0.02
            var p = Path()
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + cos(a - 0.05) * s.height, y: c.y + sin(a - 0.05) * s.height))
            p.addLine(to: CGPoint(x: c.x + cos(a + 0.05) * s.height, y: c.y + sin(a + 0.05) * s.height))
            p.closeSubpath()
            gc.fill(p, with: .radialGradient(Gradient(colors: [.white.opacity(0.14), .clear]), center: c, startRadius: 0, endRadius: s.height * 0.7))
        }
    }

    static func starsField(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, count: Int, shooting: Bool) {
        var rng = SeededRNG(seed: 23)
        for _ in 0..<count {
            let x = Double.random(in: 0...1, using: &rng) * s.width
            let y = Double.random(in: 0...0.75, using: &rng) * s.height
            let r = Double.random(in: 0.8...2, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let tw = 0.35 + 0.5 * (0.5 + 0.5 * sin(t * 0.8 + ph))
            gc.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(.white.opacity(tw)))
        }
        guard shooting else { return }
        // A shooting star roughly every 14 seconds
        let cycle = floor(t / 14), q = (t / 14 - cycle) * 14
        guard q < 1.1 else { return }
        var r2 = SeededRNG(seed: UInt64(max(0, cycle)) &+ 99)
        let sx = Double.random(in: 0.2...0.9, using: &r2) * s.width, sy = Double.random(in: 0.05...0.3, using: &r2) * s.height
        let k = q / 1.1
        let x = sx - k * s.width * 0.35, y = sy + k * s.width * 0.18
        var p = Path()
        p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + 60, y: y - 31))
        gc.stroke(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.9 * (1 - k)), .clear]),
                                           startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + 60, y: y - 31)), lineWidth: 1.5)
    }

    static func clouds(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, dark: Bool) {
        var rng = SeededRNG(seed: 29)
        for _ in 0..<6 {
            let off = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.004...0.009, using: &rng)
            let y = Double.random(in: 0.03...0.5, using: &rng) * s.height
            let scale = Double.random(in: 0.7...1.4, using: &rng)
            let x = frac(off + t * sp) * (s.width + 360) - 180
            let a = (dark ? 0.06 : 0.22) * Double.random(in: 0.7...1.2, using: &rng)
            for (dx, dy, r) in [(0.0, 0.0, 60.0), (50, -18, 48), (-48, 6, 44), (95, 8, 40), (-90, 14, 34)] {
                let c = CGPoint(x: x + dx * scale, y: y + dy * scale)
                let rr = r * scale
                gc.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                        with: .radialGradient(Gradient(colors: [.white.opacity(a), .clear]), center: c, startRadius: 0, endRadius: rr))
            }
        }
    }

    static func rain(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        var rng = SeededRNG(seed: 31)
        for _ in 0..<110 {
            let bx = Double.random(in: -0.1...1, using: &rng) * s.width
            let off = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.6...1.0, using: &rng)
            let len = Double.random(in: 12...24, using: &rng)
            let y = frac(off + t * sp) * (s.height + 60) - 30
            let x = bx + y * 0.12
            var p = Path()
            p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + len * 0.12, y: y + len))
            gc.stroke(p, with: .color(.white.opacity(Double.random(in: 0.12...0.28, using: &rng))), lineWidth: 1)
        }
    }

    static func lightning(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        let q = t.truncatingRemainder(dividingBy: 13)
        var a = 0.0
        if q < 0.1 { a = 0.16 } else if q > 0.2 && q < 0.32 { a = 0.1 } else if q < 0.9 { a = 0.05 * (1 - q / 0.9) }
        guard a > 0 else { return }
        gc.fill(Path(CGRect(origin: .zero, size: s)), with: .color(.white.opacity(a)))
    }

    static func snow(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, count: Int) {
        var rng = SeededRNG(seed: 37)
        for _ in 0..<count {
            let bx = Double.random(in: 0...1, using: &rng) * s.width
            let off = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.03...0.07, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let r = Double.random(in: 1.5...3.6, using: &rng)
            let y = frac(off + t * sp) * (s.height + 20) - 10
            let x = bx + sin(t * 0.6 + ph) * 14
            gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.75)))
        }
    }

    static func fog(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, dark: Bool) {
        for i in 0..<5 {
            let k = Double(i)
            let y = s.height * (0.15 + 0.18 * k)
            let x = s.width * 0.5 + sin(t * 0.05 + k * 1.7) * s.width * 0.3
            let w = s.width * 1.4, h = 120.0
            gc.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(dark ? 0.07 : 0.22), .clear]),
                                          center: CGPoint(x: x, y: y), startRadius: 0, endRadius: w / 2))
        }
    }

    // MARK: Seasons and holidays

    static func petal(_ c: CGPoint, _ size: Double, _ angle: Double) -> Path {
        Path(ellipseIn: CGRect(x: -size / 2, y: -size * 0.28, width: size, height: size * 0.56))
            .applying(CGAffineTransform(rotationAngle: angle))
            .applying(CGAffineTransform(translationX: c.x, y: c.y))
    }

    static func blossoms(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        var rng = SeededRNG(seed: 41)
        for i in 0..<34 {
            let bx = Double.random(in: 0...1.2, using: &rng) * s.width
            let off = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.025...0.05, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let size = Double.random(in: 6...11, using: &rng)
            let y = frac(off + t * sp) * (s.height + 30) - 15
            let x = bx - y * 0.25 + sin(t * 0.7 + ph) * 18
            gc.fill(petal(CGPoint(x: x, y: y), size, t * 0.9 + ph), with: .color(cs[i % cs.count].opacity(0.75)))
        }
    }

    static func pollen(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        for i in 0..<4 {
            let k = Double(i)
            let x0 = s.width * (0.1 + 0.22 * k) + sin(t * 0.05 + k) * 20
            var p = Path()
            p.move(to: CGPoint(x: x0, y: 0)); p.addLine(to: CGPoint(x: x0 + 60, y: 0))
            p.addLine(to: CGPoint(x: x0 + 60 + s.height * 0.35, y: s.height)); p.addLine(to: CGPoint(x: x0 + s.height * 0.35 - 30, y: s.height))
            p.closeSubpath()
            gc.fill(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.18 + 0.06 * sin(t * 0.3 + k)), .clear]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height * 0.8)))
        }
        var rng = SeededRNG(seed: 43)
        for i in 0..<40 {
            let bx = Double.random(in: 0...1, using: &rng), by = Double.random(in: 0...1, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let x = (bx + 0.04 * sin(t * 0.12 + ph)) * s.width
            let y = (by + 0.03 * cos(t * 0.1 + ph) - frac(t * 0.004 + bx) * 0.1) * s.height
            let r = 1 + 1.4 * (0.5 + 0.5 * sin(t + ph))
            gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(cs[i % cs.count].opacity(0.7)))
        }
    }

    static func leaf(_ c: CGPoint, _ size: Double, _ angle: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -size / 2, y: 0))
        p.addQuadCurve(to: CGPoint(x: size / 2, y: 0), control: CGPoint(x: 0, y: -size * 0.45))
        p.addQuadCurve(to: CGPoint(x: -size / 2, y: 0), control: CGPoint(x: 0, y: size * 0.45))
        return p.applying(CGAffineTransform(rotationAngle: angle)).applying(CGAffineTransform(translationX: c.x, y: c.y))
    }

    static func leaves(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        var rng = SeededRNG(seed: 47)
        for i in 0..<22 {
            let bx = Double.random(in: 0...1, using: &rng) * s.width
            let off = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.03...0.055, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let size = Double.random(in: 12...20, using: &rng)
            let y = frac(off + t * sp) * (s.height + 40) - 20
            let x = bx + sin(t * 0.9 + ph) * 30
            let tumble = sin(t * 1.2 + ph) * 1.2 + ph
            gc.fill(leaf(CGPoint(x: x, y: y), size, tumble), with: .color(cs[i % cs.count].opacity(0.8)))
        }
    }

    static func fireworks(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        for slot in 0..<4 {
            let period = 4.2 + Double(slot) * 0.7
            let tt = t + Double(slot) * 1.9
            let cycle = floor(tt / period)
            let p = tt / period - cycle
            var rng = SeededRNG(seed: UInt64(max(0, cycle)) &* 31 &+ UInt64(slot))
            let bx = Double.random(in: 0.15...0.85, using: &rng) * s.width
            let by = Double.random(in: 0.1...0.42, using: &rng) * s.height
            let color = cs[Int.random(in: 0..<cs.count, using: &rng)]
            let launch = 0.22
            if p < launch {
                let q = p / launch
                let y = s.height + (by - s.height) * (1 - (1 - q) * (1 - q))
                gc.fill(Path(ellipseIn: CGRect(x: bx - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(color.opacity(0.85)))
                var trail = Path()
                trail.move(to: CGPoint(x: bx, y: y)); trail.addLine(to: CGPoint(x: bx, y: y + 18))
                gc.stroke(trail, with: .linearGradient(Gradient(colors: [color.opacity(0.5), .clear]),
                                                       startPoint: CGPoint(x: bx, y: y), endPoint: CGPoint(x: bx, y: y + 18)), lineWidth: 1.2)
            } else {
                let q = (p - launch) / (1 - launch)
                let radius = min(s.width, s.height) * 0.2 * (1 - pow(1 - q, 3))
                let fade = pow(1 - q, 1.6)
                let c = CGPoint(x: bx, y: by)
                gc.fill(Path(ellipseIn: CGRect(x: bx - radius, y: by - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(Gradient(colors: [color.opacity(0.18 * fade), .clear]), center: c, startRadius: 0, endRadius: radius))
                for i in 0..<32 {
                    let a = Double(i) / 32 * 2 * .pi + Double(slot)
                    let x = bx + cos(a) * radius, y = by + sin(a) * radius + q * q * 36
                    let r = 1.9 * (1 - q * 0.5)
                    gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(0.9 * fade)))
                }
            }
        }
    }

    static func heart(_ c: CGPoint, _ r: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y + r * 0.9))
        p.addCurve(to: CGPoint(x: c.x - r, y: c.y - r * 0.2), control1: CGPoint(x: c.x - r * 0.6, y: c.y + r * 0.5), control2: CGPoint(x: c.x - r, y: c.y + r * 0.2))
        p.addArc(center: CGPoint(x: c.x - r * 0.5, y: c.y - r * 0.25), radius: r * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: c.x + r * 0.5, y: c.y - r * 0.25), radius: r * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: c.x, y: c.y + r * 0.9), control1: CGPoint(x: c.x + r, y: c.y + r * 0.2), control2: CGPoint(x: c.x + r * 0.6, y: c.y + r * 0.5))
        return p
    }

    static func hearts(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        var rng = SeededRNG(seed: 53)
        for i in 0..<18 {
            let bx = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.02...0.04, using: &rng)
            let off = Double.random(in: 0...1, using: &rng)
            let r = Double.random(in: 6...14, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let q = frac(off + t * sp)
            let y = s.height * (1.08 - q * 1.2)
            let x = (bx + 0.035 * sin(t * 0.7 + ph)) * s.width
            let beat = 1 + 0.08 * sin(t * 3 + ph)
            gc.fill(heart(CGPoint(x: x, y: y), r * beat), with: .color(cs[i % cs.count].opacity(0.55 * min(1, (1 - q) * 3))))
        }
    }

    static func confetti(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color], count: Int) {
        var rng = SeededRNG(seed: 59)
        for i in 0..<count {
            let bx = Double.random(in: 0...1, using: &rng) * s.width
            let off = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.04...0.08, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let y = frac(off + t * sp) * (s.height + 20) - 10
            let x = bx + sin(t * 1.1 + ph) * 16
            let flip = abs(cos(t * 2.4 + ph))
            let rect = CGRect(x: -3.5, y: -2 * flip, width: 7, height: 4 * flip + 0.5)
            let path = Path(rect).applying(CGAffineTransform(rotationAngle: t + ph)).applying(CGAffineTransform(translationX: x, y: y))
            gc.fill(path, with: .color(cs[i % cs.count].opacity(0.85)))
        }
    }

    static func bottomGlow(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ color: Color, strength: Double) {
        let flick = 0.85 + 0.15 * sin(t * 2.3) * sin(t * 3.7)
        let c = CGPoint(x: s.width / 2, y: s.height * 1.05)
        let r = s.width * (0.7 + 0.25 * strength)
        gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(Gradient(colors: [color.opacity((0.18 + 0.22 * strength) * flick), .clear]), center: c, startRadius: 0, endRadius: r))
    }

    static func bigMoon(_ gc: inout GraphicsContext, _ s: CGSize) {
        let r = s.width * 0.2
        let c = CGPoint(x: s.width * 0.72, y: s.height * 0.16)
        gc.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.5, y: c.y - r * 2.5, width: r * 5, height: r * 5)),
                with: .radialGradient(Gradient(colors: [Color(hex: "#FDBA74").opacity(0.25), .clear]), center: c, startRadius: r, endRadius: r * 2.5))
        gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: "#FED7AA").opacity(0.85)))
    }

    static func bats(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        var rng = SeededRNG(seed: 61)
        for _ in 0..<6 {
            let off = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.025...0.05, using: &rng)
            let by = Double.random(in: 0.08...0.5, using: &rng)
            let size = Double.random(in: 10...18, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let x = frac(off + t * sp) * (s.width + 80) - 40
            let y = by * s.height + sin(t * 1.5 + ph) * 14
            let flap = sin(t * 12 + ph)
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addQuadCurve(to: CGPoint(x: x - size, y: y - size * 0.5 * flap), control: CGPoint(x: x - size * 0.5, y: y - size * 0.6))
            p.addQuadCurve(to: CGPoint(x: x, y: y + size * 0.25), control: CGPoint(x: x - size * 0.5, y: y))
            p.addQuadCurve(to: CGPoint(x: x + size, y: y - size * 0.5 * flap), control: CGPoint(x: x + size * 0.5, y: y))
            p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x + size * 0.5, y: y - size * 0.6))
            gc.fill(p, with: .color(.black.opacity(0.85)))
        }
    }

    /// A string of twinkling bulbs hanging across the top.
    static func fairyLights(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        var wire = Path()
        let sag = 40.0
        let top = s.height * 0.06
        func y(_ x: Double) -> Double { let u = x / s.width; return top + sag * 4 * u * (1 - u) }
        wire.move(to: CGPoint(x: 0, y: y(0)))
        var x = 0.0
        while x <= s.width { wire.addLine(to: CGPoint(x: x, y: y(x))); x += 8 }
        gc.stroke(wire, with: .color(.white.opacity(0.18)), lineWidth: 1)
        let n = 14
        for i in 0..<n {
            let bx = (Double(i) + 0.5) / Double(n) * s.width
            let by = y(bx) + 5
            let c = cs[i % cs.count]
            let on = 0.55 + 0.45 * sin(t * 1.6 + Double(i) * 1.3)
            gc.fill(Path(ellipseIn: CGRect(x: bx - 12, y: by - 12, width: 24, height: 24)),
                    with: .radialGradient(Gradient(colors: [c.opacity(0.45 * on), .clear]), center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: 12))
            gc.fill(Path(ellipseIn: CGRect(x: bx - 2.5, y: by - 3.5, width: 5, height: 7)), with: .color(c.opacity(0.5 + 0.5 * on)))
        }
    }

    /// A row of candles at the bottom; `lit` of them burn (Advent lights one more each Sunday).
    static func candles(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, count: Int, lit: Int) {
        let w = min(s.width * 0.8, Double(count) * 44)
        let start = (s.width - w) / 2
        let baseY = s.height * 0.95
        for i in 0..<count {
            let x = start + (Double(i) + 0.5) / Double(count) * w
            let h = count > 4 ? 40.0 : 56.0
            let body = CGRect(x: x - 7, y: baseY - h, width: 14, height: h)
            gc.fill(Path(roundedRect: body, cornerRadius: 3), with: .color(Color(hex: "#F5F0E6").opacity(0.75)))
            guard i < lit else { continue }
            let flick = 1 + 0.12 * sin(t * 9 + Double(i) * 2) * sin(t * 5.3 + Double(i))
            let fy = baseY - h - 9
            gc.fill(Path(ellipseIn: CGRect(x: x - 34, y: fy - 34, width: 68, height: 68)),
                    with: .radialGradient(Gradient(colors: [Color(hex: "#FBBF24").opacity(0.3), .clear]), center: CGPoint(x: x, y: fy), startRadius: 0, endRadius: 34))
            var flame = Path()
            flame.move(to: CGPoint(x: x, y: fy - 10 * flick))
            flame.addQuadCurve(to: CGPoint(x: x, y: fy + 6), control: CGPoint(x: x + 7, y: fy + 2))
            flame.addQuadCurve(to: CGPoint(x: x, y: fy - 10 * flick), control: CGPoint(x: x - 7, y: fy + 2))
            gc.fill(flame, with: .color(Color(hex: "#FDE68A").opacity(0.95)))
        }
    }

    static func balloons(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ cs: [Color]) {
        var rng = SeededRNG(seed: 67)
        for i in 0..<9 {
            let bx = Double.random(in: 0.05...0.95, using: &rng)
            let sp = Double.random(in: 0.015...0.03, using: &rng)
            let off = Double.random(in: 0...1, using: &rng)
            let r = Double.random(in: 16...26, using: &rng)
            let ph = Double.random(in: 0...6.28, using: &rng)
            let y = s.height * (1.15 - frac(off + t * sp) * 1.4)
            let x = (bx + 0.03 * sin(t * 0.6 + ph)) * s.width
            let c = cs[i % cs.count]
            var string = Path()
            string.move(to: CGPoint(x: x, y: y + r * 1.15))
            string.addQuadCurve(to: CGPoint(x: x + sin(t + ph) * 6, y: y + r * 3.2), control: CGPoint(x: x - 8, y: y + r * 2))
            gc.stroke(string, with: .color(.white.opacity(0.3)), lineWidth: 0.8)
            gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 1.15, width: r * 2, height: r * 2.3)), with: .color(c.opacity(0.7)))
            gc.fill(Path(ellipseIn: CGRect(x: x - r * 0.55, y: y - r * 0.8, width: r * 0.35, height: r * 0.5)), with: .color(.white.opacity(0.35)))
        }
    }

    // MARK: Other alive themes

    /// Tonight's moon: `phase` 0 = new, 0.5 = full, back to new at 1.
    static func moon(_ gc: inout GraphicsContext, _ s: CGSize, phase: Double) {
        let r = s.width * 0.15
        let c = CGPoint(x: s.width * 0.72, y: s.height * 0.15)
        let lit = 0.5 - 0.5 * cos(phase * 2 * .pi)
        gc.fill(Path(ellipseIn: CGRect(x: c.x - r * 3, y: c.y - r * 3, width: r * 6, height: r * 6)),
                with: .radialGradient(Gradient(colors: [Color.white.opacity(0.05 + 0.12 * lit), .clear]), center: c, startRadius: r, endRadius: r * 3))
        gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.06)))
        let k = cos(phase * 2 * .pi)
        let waxing = phase < 0.5
        var p = Path()
        let steps = 40
        for i in 0...steps {
            let th = -Double.pi / 2 + Double(i) / Double(steps) * .pi
            let x = (waxing ? 1 : -1) * r * cos(th)
            let pt = CGPoint(x: c.x + x, y: c.y + r * sin(th))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        for i in 0...steps {
            let th = Double.pi / 2 - Double(i) / Double(steps) * .pi
            let x = (waxing ? 1 : -1) * k * r * cos(th)
            p.addLine(to: CGPoint(x: c.x + x, y: c.y + r * sin(th)))
        }
        p.closeSubpath()
        gc.fill(p, with: .linearGradient(Gradient(colors: [Color(hex: "#F8FAFC"), Color(hex: "#CBD5E1")]),
                                         startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: CGPoint(x: c.x + r, y: c.y + r)))
        // A few soft craters
        var clipped = gc
        clipped.clip(to: p)
        for (dx, dy, cr) in [(-0.3, -0.25, 0.18), (0.25, 0.2, 0.22), (0.05, -0.45, 0.1), (-0.15, 0.4, 0.12)] {
            clipped.fill(Path(ellipseIn: CGRect(x: c.x + dx * r - cr * r, y: c.y + dy * r - cr * r, width: cr * r * 2, height: cr * r * 2)),
                         with: .color(Color(hex: "#94A3B8").opacity(0.28)))
        }
    }

    /// Pulse: two soft glows that swell gently with the music.
    static func pulse(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, level: Double, a: Color, b: Color) {
        let breathe = 0.5 + 0.5 * sin(t * 0.4)
        let c1 = CGPoint(x: s.width * (0.3 + 0.1 * sin(t * 0.07)), y: s.height * (0.28 + 0.05 * cos(t * 0.09)))
        let r1 = s.width * (0.75 + 0.25 * level)
        gc.fill(Path(ellipseIn: CGRect(x: c1.x - r1, y: c1.y - r1, width: r1 * 2, height: r1 * 2)),
                with: .radialGradient(Gradient(colors: [a.opacity(0.08 + 0.2 * level + 0.03 * breathe), .clear]), center: c1, startRadius: 0, endRadius: r1))
        let c2 = CGPoint(x: s.width * (0.75 + 0.08 * cos(t * 0.06)), y: s.height * (0.78 + 0.04 * sin(t * 0.08)))
        let r2 = s.width * (0.65 + 0.2 * level)
        gc.fill(Path(ellipseIn: CGRect(x: c2.x - r2, y: c2.y - r2, width: r2 * 2, height: r2 * 2)),
                with: .radialGradient(Gradient(colors: [b.opacity(0.06 + 0.15 * level), .clear]), center: c2, startRadius: 0, endRadius: r2))
    }

    /// Battery while charging: a calm green glow rising from the bottom, with a few motes.
    static func charging(_ gc: inout GraphicsContext, _ s: CGSize, _ t: Double, _ c: Color) {
        let q = 0.5 + 0.5 * sin(t * 0.8)
        bottomGlow(&gc, s, t, c, strength: 0.4 + 0.4 * q)
        var rng = SeededRNG(seed: 71)
        for _ in 0..<20 {
            let bx = Double.random(in: 0...1, using: &rng)
            let off = Double.random(in: 0...1, using: &rng)
            let sp = Double.random(in: 0.03...0.06, using: &rng)
            let p = frac(off + t * sp)
            let y = s.height * (1.02 - p * 0.7)
            let x = bx * s.width
            gc.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(c.opacity(0.7 * (1 - p))))
        }
    }
}
