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
    /// When scratching, one full turn moves 4 seconds.
    private let secondsPerTurn: Double = 4

    var body: some View {
        let p = app.player
        let spinning = dragStartAngle == nil
        let angle = spinning ? p.position * degreesPerSecond + angleOffset : (dragStartAngle ?? 0) + dragTotal
        ZStack {
            record
                .rotationEffect(.degrees(angle))
                .animation(spinning && p.isPlaying ? .linear(duration: 0.04) : nil, value: angle)
            tonearm
                .rotationEffect(.degrees(p.isPlaying && spinning ? 24 : 2), anchor: UnitPoint(x: 0.86, y: 0.08))
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: p.isPlaying && spinning)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .highPriorityGesture(scratch(angle: angle))
        .accessibilityElement()
        .accessibilityLabel("Record. Drag around to rewind or skip ahead.")
    }

    private var record: some View {
        ZStack {
            Circle().fill(Color(white: 0.06))
            // Grooves
            ForEach(0..<14, id: \.self) { i in
                Circle().stroke(Color.white.opacity(i.isMultiple(of: 3) ? 0.07 : 0.035), lineWidth: 1)
                    .padding(size * 0.06 + CGFloat(i) * size * 0.022)
            }
            // A soft shine that turns with the record, so you can see it spin
            Circle()
                .fill(AngularGradient(colors: [.clear, .white.opacity(0.13), .clear, .clear, .white.opacity(0.09), .clear], center: .center))
            song.artwork(size * 0.38)
                .clipShape(Circle())
                .overlay(Circle().fill(Color(white: 0.1)).frame(width: size * 0.035))
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }

    private var tonearm: some View {
        ZStack(alignment: .topTrailing) {
            Capsule().fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.035, height: size * 0.62)
                .rotationEffect(.degrees(18), anchor: .top)
                .offset(x: -size * 0.13, y: size * 0.05)
            Circle().fill(Color(white: 0.75)).frame(width: size * 0.11, height: size * 0.11)
                .overlay(Circle().fill(Color(white: 0.45)).frame(width: size * 0.05))
                .offset(x: -size * 0.08, y: 0)
        }
        .frame(width: size, height: size, alignment: .topTrailing)
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

/// A cassette whose reels turn while playing, with the tape moving from one reel to the other.
struct CassetteView: View {
    let song: Song
    let size: CGFloat
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.player
        let w = size, h = size * 0.64
        let progress = p.duration > 0 ? min(1, max(0, p.elapsed / p.duration)) : 0
        let angle = p.position * 140
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
            // Label with the cover's colors
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    song.artwork(w * 0.86)
                        .frame(width: w * 0.86, height: h * 0.5)
                        .clipped()
                        .blur(radius: 10)
                        .overlay(Color.black.opacity(0.25))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.system(size: w * 0.055, weight: .heavy)).lineLimit(1)
                        Text(song.artistLine).font(.system(size: w * 0.04, weight: .semibold)).opacity(0.85).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, w * 0.04)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, w * 0.03)
                }
                .frame(width: w * 0.86, height: h * 0.5)
                .clipShape(RoundedRectangle(cornerRadius: w * 0.025))
                Spacer()
            }
            .padding(.top, h * 0.08)
            // Window with the two reels
            RoundedRectangle(cornerRadius: h * 0.08)
                .fill(Color.black.opacity(0.75))
                .frame(width: w * 0.56, height: h * 0.3)
                .offset(y: h * 0.12)
            HStack(spacing: w * 0.2) {
                reel(tape: 1 - progress, angle: angle)
                reel(tape: progress, angle: angle)
            }
            .offset(y: h * 0.12)
            // Screws
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color(white: 0.4)).frame(width: w * 0.025)
                    .offset(x: (i % 2 == 0 ? -1 : 1) * w * 0.44, y: (i < 2 ? -1 : 1) * h * 0.4)
            }
        }
        .frame(width: w, height: h)
        .scaleEffect(p.isPlaying ? 1 : 0.95)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: p.isPlaying)
    }

    private func reel(tape: Double, angle: Double) -> some View {
        let base = size * 0.1
        return ZStack {
            Circle().fill(Color(red: 0.25, green: 0.17, blue: 0.12)).frame(width: base + size * 0.1 * tape, height: base + size * 0.1 * tape)
            Circle().fill(Color(white: 0.9)).frame(width: base * 0.75)
            ForEach(0..<6, id: \.self) { i in
                Rectangle().fill(Color(white: 0.35)).frame(width: base * 0.08, height: base * 0.3)
                    .offset(y: -base * 0.2)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
        .rotationEffect(.degrees(angle))
        .animation(.linear(duration: 0.04), value: angle)
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
