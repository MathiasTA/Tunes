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

    /// A real record turns at 33⅓ rpm: 200° per second.
    private let degreesPerSecond: Double = 200
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

/// A cassette tape: the cover on the label, tape winding from one reel to the other through the window.
struct CassetteView: View {
    let song: Song
    let size: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look

    var body: some View {
        let p = app.player
        let w = size, h = size * 0.63
        let progress = p.duration > 0 ? min(1, max(0, p.elapsed / p.duration)) : 0
        let angle = p.position * 140
        ZStack {
            shell(w, h)
            label(w, h, progress: progress, angle: angle)
                .frame(width: w * 0.86, height: h * 0.66)
                .offset(y: -h * 0.1)
            bottomPlate(w, h)
            ForEach(0..<4, id: \.self) { i in
                screw(w * 0.032)
                    .offset(x: (i % 2 == 0 ? -1 : 1) * w * 0.455, y: (i < 2 ? -1 : 1) * h * 0.42)
            }
            screw(w * 0.028).offset(y: h * 0.42)
        }
        .frame(width: w, height: h)
        .scaleEffect(p.isPlaying ? 1 : 0.96)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: p.isPlaying)
    }

    private func shell(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: w * 0.045, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.13), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: w * 0.045, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.5), radius: 22, y: 12)
    }

    private func label(_ w: CGFloat, _ h: CGFloat, progress: Double, angle: Double) -> some View {
        let lw = w * 0.86, lh = h * 0.66
        return ZStack {
            // Label paper tinted with the cover
            song.artwork(lw)
                .frame(width: lw, height: lh).clipped()
                .blur(radius: 18).saturation(1.3)
                .overlay(LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                // Writing strip
                HStack(spacing: lw * 0.03) {
                    Text("A").font(.system(size: lw * 0.07, weight: .black, design: .rounded))
                        .foregroundStyle(look.accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(song.title).font(.system(size: lw * 0.055, weight: .bold, design: .rounded)).lineLimit(1)
                        Text(song.artistLine).font(.system(size: lw * 0.04, weight: .medium, design: .rounded)).opacity(0.65).lineLimit(1)
                    }
                    .foregroundStyle(Color(white: 0.12))
                    Spacer(minLength: 0)
                    song.artwork(lh * 0.24).clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(.horizontal, lw * 0.04)
                .frame(height: lh * 0.32)
                .background(Color(red: 0.96, green: 0.94, blue: 0.89))
                .overlay(alignment: .bottom) { Rectangle().fill(look.accent).frame(height: 2) }
                Spacer(minLength: 0)
                window(lw, lh, progress: progress, angle: angle)
                Spacer(minLength: 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: w * 0.025, style: .continuous))
    }

    /// The see-through window with both reels and the tape running along the bottom.
    private func window(_ lw: CGFloat, _ lh: CGFloat, progress: Double, angle: Double) -> some View {
        let ww = lw * 0.64, wh = lh * 0.4
        let hub = ww * 0.13
        let reelX = ww * 0.27
        let maxPack = ww * 0.42
        func pack(_ amount: Double) -> CGFloat { hub * 1.15 + (maxPack - hub * 1.15) * CGFloat(amount) }
        return ZStack {
            RoundedRectangle(cornerRadius: wh * 0.5, style: .continuous).fill(Color.black.opacity(0.78))
            ZStack {
                // Tape packs (the wound-up tape), brown and glossy
                tapePack(pack(1 - progress)).offset(x: -reelX)
                tapePack(pack(progress)).offset(x: reelX)
                // Tape running between the reels
                Rectangle().fill(Color(red: 0.3, green: 0.18, blue: 0.11)).frame(width: reelX * 2, height: 1.5)
                    .offset(y: wh * 0.36)
                hubView(hub, angle: angle).offset(x: -reelX)
                hubView(hub, angle: angle * 0.9 + 17).offset(x: reelX)
            }
            .clipShape(RoundedRectangle(cornerRadius: wh * 0.5, style: .continuous))
            RoundedRectangle(cornerRadius: wh * 0.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            // Glass glare
            RoundedRectangle(cornerRadius: wh * 0.5, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        }
        .frame(width: ww, height: wh)
    }

    private func tapePack(_ d: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color(red: 0.36, green: 0.22, blue: 0.14), Color(red: 0.2, green: 0.12, blue: 0.08)],
                                 center: .center, startRadius: 0, endRadius: d / 2))
            .frame(width: d, height: d)
            .animation(.easeInOut(duration: 0.5), value: d)
    }

    /// A white reel hub with six teeth, turning.
    private func hubView(_ d: CGFloat, angle: Double) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.92)).frame(width: d, height: d)
            Circle().fill(Color(white: 0.15)).frame(width: d * 0.62, height: d * 0.62)
            ForEach(0..<6, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.92))
                    .frame(width: d * 0.12, height: d * 0.22)
                    .offset(y: -d * 0.24)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
        .rotationEffect(.degrees(angle))
        .animation(.linear(duration: 0.04), value: angle)
    }

    /// The raised part at the bottom where the tape head touches, with its holes.
    private func bottomPlate(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            CassetteBottom()
                .fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
                .overlay(CassetteBottom().stroke(Color.white.opacity(0.1), lineWidth: 1))
            HStack(spacing: w * 0.09) {
                Circle().fill(Color.black.opacity(0.85)).frame(width: w * 0.035)
                RoundedRectangle(cornerRadius: 1.5).fill(Color.black.opacity(0.85)).frame(width: w * 0.05, height: w * 0.03)
                RoundedRectangle(cornerRadius: 1.5).fill(Color.black.opacity(0.85)).frame(width: w * 0.05, height: w * 0.03)
                Circle().fill(Color.black.opacity(0.85)).frame(width: w * 0.035)
            }
            .offset(y: h * 0.02)
        }
        .frame(width: w * 0.66, height: h * 0.17)
        .offset(y: h * 0.415)
    }

    private func screw(_ d: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.6), Color(white: 0.3)], center: .topLeading, startRadius: 0, endRadius: d))
            .frame(width: d, height: d)
            .overlay(Rectangle().fill(Color(white: 0.2)).frame(width: d * 0.7, height: d * 0.14).rotationEffect(.degrees(35)))
    }
}

/// Trapezoid at the bottom edge of a cassette.
private struct CassetteBottom: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset = r.width * 0.09
        p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
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
                            Squiggle(phase: phase, amplitude: playing ? h * 0.28 : 0)
                                .stroke(look.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: w * f, height: h)
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
    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        p.move(to: CGPoint(x: 0, y: mid))
        var x: CGFloat = 0
        while x <= rect.width {
            p.addLine(to: CGPoint(x: x, y: mid + sin(Double(x) / wavelength - phase) * amplitude))
            x += 2
        }
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
