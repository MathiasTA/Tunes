import SwiftUI

// MARK: - Vinyl

/// The cover as a spinning record. Drag it around: backwards rewinds, forwards skips ahead.
struct VinylView: View {
    let song: Song
    let size: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    /// Extra rotation kept after a scratch, so the record doesn't jump when you let go.
    @State private var angleOffset: Double = 0
    @State private var dragStartAngle: Double?
    @State private var dragStartPosition: Double = 0
    @State private var lastTouchAngle: Double = 0
    @State private var dragTotal: Double = 0
    @State private var lastSeek = Date.distantPast
    @State private var lastTick: Int = 0

    /// While playing on its own the record turns calmly (a real 33⅓ rpm looks frantic on a phone).
    /// Spinning it by hand is separate: the record follows your finger, and a turn moves 12 seconds.
    private let degreesPerSecond: Double = 70
    /// When scratching, one full turn moves 12 seconds.
    private let secondsPerTurn: Double = 12

    var body: some View {
        let p = app.player
        let spinning = dragStartAngle == nil
        let angle = spinning ? p.position * degreesPerSecond + angleOffset : (dragStartAngle ?? 0) + dragTotal
        record
            .rotationEffect(.degrees(angle))
            .animation(spinning && p.isPlaying ? .linear(duration: 0.04) : nil, value: angle)
            .frame(width: size, height: size)
        .contentShape(Circle())
        .highPriorityGesture(scratch(angle: angle))
        .accessibilityElement()
        .accessibilityLabel("Record. Drag around to rewind or skip ahead.")
    }

    private var record: some View {
        ZStack {
            Circle().fill(Color(white: 0.06))
            // Grooves, between the edge and the (big) cover label
            ForEach(0..<8, id: \.self) { i in
                Circle().stroke(Color.white.opacity(i.isMultiple(of: 3) ? 0.07 : 0.035), lineWidth: 1)
                    .padding(size * 0.035 + CGFloat(i) * size * 0.017)
            }
            // A soft shine that turns with the record, so you can see it spin
            Circle()
                .fill(AngularGradient(colors: [.clear, .white.opacity(0.13), .clear, .clear, .white.opacity(0.09), .clear], center: .center))
            // The cover as the label, raised off the plate a little
            song.artwork(size * 0.64)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .overlay(Circle().fill(Color(white: 0.08)).frame(width: size * 0.04)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5)))
                .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }

    private func scratch(angle: Double) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                let center = CGPoint(x: size / 2, y: size / 2)
                let a = atan2(v.location.y - center.y, v.location.x - center.x) * 180 / .pi
                if dragStartAngle == nil {
                    dragStartAngle = angle
                    dragStartPosition = app.player.position
                    lastTouchAngle = a
                    dragTotal = 0
                    lastTick = 0
                    AppModel.shared.bump("vinylScratches")
                    return
                }
                var delta = a - lastTouchAngle
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }
                lastTouchAngle = a
                dragTotal += delta
                // A little tick every 30°, like the record catching under your finger.
                let tick = Int(dragTotal / 30)
                if tick != lastTick { lastTick = tick; app.haptic(.selection) }
                // Jump the music along while you scratch (a few times a second).
                if Date.now.timeIntervalSince(lastSeek) > 0.25 {
                    lastSeek = .now
                    app.player.seek(to: target)
                }
            }
            .onEnded { _ in
                let t = target
                app.player.seek(to: t)
                // Keep the record where your finger left it.
                angleOffset = ((dragStartAngle ?? 0) + dragTotal) - t * degreesPerSecond
                dragStartAngle = nil
                dragTotal = 0
            }
    }

    private var target: Double {
        let p = app.player
        return min(max(p.start, dragStartPosition + dragTotal / 360 * secondsPerTurn), max(p.start, p.end - 0.5))
    }
}

// MARK: - Cassette

/// A clean, minimal cassette: one soft shell, a simple label, and two reels winding the tape across.
struct CassetteView: View {
    let song: Song
    let size: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        let p = app.player
        let w = size, h = size * 0.62
        let progress = p.duration > 0 ? min(1, max(0, p.elapsed / p.duration)) : 0
        let angle = p.position * 120
        let shellShape = RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
        ZStack {
            // Shell: one color, a hairline highlight on top
            shellShape
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
                .overlay(shellShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

            VStack(spacing: h * 0.07) {
                labelStrip(w)
                window(w * 0.62, h * 0.3, progress: progress, angle: angle)
            }
            .offset(y: -h * 0.04)

            // The tape-head edge: just an outline
            CassetteBottom()
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                .frame(width: w * 0.6, height: h * 0.13)
                .offset(y: h * 0.435)

            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color.white.opacity(0.14)).frame(width: w * 0.018)
                    .offset(x: (i % 2 == 0 ? -1 : 1) * w * 0.44, y: (i < 2 ? -1 : 1) * h * 0.4)
            }
        }
        .frame(width: w, height: h)
        .scaleEffect(p.isPlaying ? 1 : 0.97)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: p.isPlaying)
    }

    /// A paper label: small cover, title and artist, a thin accent line.
    private func labelStrip(_ w: CGFloat) -> some View {
        HStack(spacing: w * 0.035) {
            song.artwork(w * 0.11).clipShape(RoundedRectangle(cornerRadius: w * 0.015, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).font(.system(size: w * 0.048, weight: .semibold)).lineLimit(1)
                Text(song.artistLine).font(.system(size: w * 0.036)).foregroundStyle(Color.black.opacity(0.5)).lineLimit(1)
            }
            .foregroundStyle(Color.black.opacity(0.85))
            Spacer(minLength: 0)
            Text("A").font(.system(size: w * 0.05, weight: .bold, design: .rounded)).foregroundStyle(look.accent)
        }
        .padding(.horizontal, w * 0.035)
        .frame(width: w * 0.82, height: w * 0.16)
        .background(Color(red: 0.95, green: 0.94, blue: 0.91), in: RoundedRectangle(cornerRadius: w * 0.025, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle().fill(look.accent).frame(height: 2).padding(.horizontal, w * 0.035).padding(.bottom, w * 0.018)
        }
    }

    /// The window: tape packs that grow and shrink, two turning hubs.
    private func window(_ ww: CGFloat, _ wh: CGFloat, progress: Double, angle: Double) -> some View {
        let shape = Capsule(style: .continuous)
        let reelX = ww * 0.27
        let hub = wh * 0.42
        func pack(_ amount: Double) -> CGFloat { hub + (wh * 1.25 - hub) * CGFloat(amount) }
        return ZStack {
            shape.fill(Color.black.opacity(0.55))
            ZStack {
                tapePack(pack(1 - progress)).offset(x: -reelX)
                tapePack(pack(progress)).offset(x: reelX)
                hubView(hub, angle: angle).offset(x: -reelX)
                hubView(hub, angle: angle + 30).offset(x: reelX)
            }
            .clipShape(shape)
            shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .frame(width: ww, height: wh)
    }

    private func tapePack(_ d: CGFloat) -> some View {
        Circle().fill(Color(red: 0.24, green: 0.16, blue: 0.11))
            .frame(width: d, height: d)
            .animation(.easeInOut(duration: 0.5), value: d)
    }

    /// A thin ring with three teeth.
    private func hubView(_ d: CGFloat, angle: Double) -> some View {
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: d * 0.14)
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Color.white.opacity(0.85))
                    .frame(width: d * 0.12, height: d * 0.26)
                    .offset(y: -d * 0.26)
                    .rotationEffect(.degrees(Double(i) * 120))
            }
        }
        .frame(width: d, height: d)
        .rotationEffect(.degrees(angle))
        .animation(.linear(duration: 0.04), value: angle)
    }
}

/// Trapezoid at the bottom edge of a cassette.
private struct CassetteBottom: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset = r.width * 0.08
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

// MARK: - Progress bar looks

/// Draws the progress bar in the chosen style (the scrubbing itself is handled by the player).
struct ProgressBarArt: View {
    let style: ProgressStyle
    let fraction: Double
    var waveform: [Float] = []
    var playing = true
    var active = false
    /// A still picture of the style (for the picker in Appearance).
    var preview = false
    @Environment(\.look) private var look

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let f = CGFloat(min(1, max(0, fraction)))
            switch style {
            case .line, .thick:
                let t: CGFloat = style == .thick ? (active ? 12 : 8) : (active ? 8 : 4)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.2)).frame(height: t)
                    Capsule().fill(style == .thick ? look.accent : Color.primary).frame(width: max(t, w * f), height: t)
                }
                .frame(height: h)
            case .waveform:
                // As many bars as fit nicely (about one per 4–5 points), sampled from the song's real shape.
                let source = waveform.isEmpty ? Self.placeholder : waveform
                let count = max(8, min(source.count, Int(w / 4.5)))
                let spacing: CGFloat = w < 120 ? 1.5 : 2
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        let v = source[min(source.count - 1, i * source.count / count)]
                        let played = CGFloat(i) / CGFloat(max(count - 1, 1)) <= f
                        Capsule().fill(played ? look.accent : Color.primary.opacity(0.22))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, CGFloat(v) * h))
                    }
                }
                .frame(height: h)
            case .squiggle:
                if preview {
                    // A still sine wave: the played part in the accent color, the rest faint.
                    ZStack(alignment: .leading) {
                        Squiggle(phase: 0, amplitude: h * 0.3, wavelength: 5)
                            .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        Squiggle(phase: 0, amplitude: h * 0.3, wavelength: 5)
                            .stroke(look.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .mask(alignment: .leading) { Rectangle().frame(width: w * f) }
                    }
                    .frame(height: h)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
                        let phase = ctx.date.timeIntervalSinceReferenceDate * 6
                        ZStack(alignment: .leading) {
                            // Only a very faint guide for the part still to play.
                            Capsule().fill(Color.primary.opacity(0.1)).frame(height: 2)
                                .padding(.leading, w * f)
                            // Ends at the dot's center (the round cap stays hidden under the dot).
                            Squiggle(phase: phase, amplitude: playing ? h * 0.28 : 0, taper: 14)
                                .stroke(look.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: max(0, w * f - 2), height: h)
                                .animation(.easeInOut(duration: 0.3), value: playing)
                        }
                        .frame(height: h)
                    }
                }
            case .dots:
                let count = max(8, Int(w / 9))
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        let played = Double(i) / Double(count - 1) <= fraction
                        Circle().fill(played ? look.accent : Color.primary.opacity(0.22))
                            .frame(width: played ? 6 : 4, height: played ? 6 : 4)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: h)
            }
        }
    }

    static let placeholder: [Float] = (0..<48).map { i -> Float in
        let x = Double(i)
        let a: Double = abs(sin(x * 0.7))
        let b: Double = abs(sin(x * 0.23))
        return Float(0.35 + 0.3 * a + 0.2 * b)
    }
}

/// A wavy line, like a moving sound wave.
struct Squiggle: Shape {
    var phase: Double
    var amplitude: CGFloat
    /// Points per radian: smaller means tighter waves.
    var wavelength: Double = 7
    /// Over this many points at the end the wave flattens out, so it runs straight into the progress dot.
    var taper: CGFloat = 0
    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        func y(_ x: CGFloat) -> CGFloat {
            let fade = taper > 0 ? min(1, max(0, (rect.width - x) / taper)) : 1
            // Smooth ease so the flattening has no kink.
            let ease = fade * fade * (3 - 2 * fade)
            return mid + CGFloat(sin(Double(x) / wavelength - phase)) * amplitude * ease
        }
        p.move(to: CGPoint(x: 0, y: y(0)))
        var x: CGFloat = 2
        while x < rect.width {
            p.addLine(to: CGPoint(x: x, y: y(x)))
            x += 2
        }
        if rect.width > 0 { p.addLine(to: CGPoint(x: rect.width, y: y(rect.width))) }
        return p
    }
}

// MARK: - Mini player looks

/// The mini player in its "Bubble" style: just the cover in a circle with a progress ring, floating in the corner.
struct MiniBubble: View {
    let song: Song
    let progress: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                Button { app.player.togglePlayPause() } label: {
                    Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(app.player.isPlaying ? "Pause" : "Play")
                song.artwork(56)
                    .clipShape(Circle())
                    .rotationEffect(.degrees(app.player.isPlaying ? app.player.position * 20 : 0))
                    .padding(4)
                    .overlay {
                        Circle().trim(from: 0, to: progress)
                            .stroke(look.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .background(Circle().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .onTapGesture { app.showPlayer = true }
                    .accessibilityLabel("Open player: \(song.title)")
            }
            .foregroundStyle(.primary)
            .padding(.trailing, 14)
        }
    }
}
