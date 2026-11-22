import SwiftUI

struct ShareCardStyle: Equatable {
    enum Pattern: String, CaseIterable { case plain = "None", circles = "Circles", waves = "Waves", grid = "Grid", stripes = "Stripes", stars = "Stars" }
    enum Typeface: String, CaseIterable { case rounded = "Rounded", serif = "Serif", mono = "Mono", classic = "Classic", condensed = "Bold" }
    enum Layout: String, CaseIterable { case list = "List", bigNumber = "Big number", cover = "Cover" }
    enum Size: String, CaseIterable {
        case story = "Story", post = "Post", square = "Square"
        var aspect: CGFloat { switch self { case .story: 9.0 / 16.0; case .post: 4.0 / 5.0; case .square: 1 } }
    }

    var background = Color(hex: "#7C3AED")
    var shapes = Color(hex: "#EC4899")
    var text = Color.white
    var pattern: Pattern = .circles
    var typeface: Typeface = .rounded
    var layout: Layout = .list
    var size: Size = .story
    var showName = true
    var showMinutes = true
    var showArtists = true
    var showSongs = true
    var showGenre = true
    var showPersonality = true
    var showStreak = false

    static let themes: [(String, Color, Color, Color)] = [
        ("Grape", Color(hex: "#7C3AED"), Color(hex: "#EC4899"), .white),
        ("Mint", Color(hex: "#064E3B"), Color(hex: "#34D399"), .white),
        ("Sunset", Color(hex: "#F97316"), Color(hex: "#FACC15"), Color(hex: "#3B0A0A")),
        ("Ocean", Color(hex: "#0C4A6E"), Color(hex: "#38BDF8"), .white),
        ("Paper", Color(hex: "#F5F5F4"), Color(hex: "#FB7185"), Color(hex: "#1C1917")),
        ("Night", Color(hex: "#0A0A0A"), Color(hex: "#6366F1"), .white),
        ("Lime", Color(hex: "#D9F99D"), Color(hex: "#16A34A"), Color(hex: "#052E16")),
        ("Cherry", Color(hex: "#881337"), Color(hex: "#FB923C"), .white)
    ]

    func font(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .black) -> SwiftUI.Font {
        switch typeface {
        case .rounded: .system(size: size, weight: weight, design: .rounded)
        case .serif: .system(size: size, weight: weight, design: .serif)
        case .mono: .system(size: size, weight: weight, design: .monospaced)
        case .classic: .system(size: size, weight: weight)
        case .condensed: .system(size: size, weight: weight).width(.condensed)
        }
    }

    static func random() -> ShareCardStyle {
        var s = ShareCardStyle()
        let t = themes.randomElement()!
        s.background = t.1; s.shapes = t.2; s.text = t.3
        s.pattern = Pattern.allCases.randomElement()!
        s.typeface = Typeface.allCases.randomElement()!
        s.layout = Layout.allCases.randomElement()!
        return s
    }
}

/// The image that gets shared. Fixed logical width so it renders the same everywhere.
struct ShareCard: View {
    let data: WrappedData
    let style: ShareCardStyle
    let name: String
    let artistImage: UIImage?
    let songImage: UIImage?
    static let width: CGFloat = 360

    var body: some View {
        let h = Self.width / style.size.aspect
        ZStack(alignment: .topLeading) {
            style.background
            PatternView(pattern: style.pattern, color: style.shapes)
            content
                .padding(style.size == .square ? 22 : 28)
                .foregroundStyle(style.text)
        }
        .frame(width: Self.width, height: h)
        .clipped()
    }

    private var title: String { style.showName && !name.isEmpty ? "\(name)'s Wrapped" : "My Wrapped" }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: style.size == .square ? 10 : 16) {
            HStack {
                Text(title.uppercased()).font(style.font(13, .heavy)).tracking(1.2)
                Spacer()
                Text(periodLabel).font(style.font(12, .bold)).opacity(0.75)
            }
            switch style.layout {
            case .list: listLayout
            case .bigNumber: bigLayout
            case .cover: coverLayout
            }
            Spacer(minLength: 0)
            HStack {
                if style.showPersonality {
                    Label(data.personality.title, systemImage: data.personality.icon).font(style.font(13, .bold))
                }
                Spacer()
                Text("Tunes").font(style.font(13, .heavy)).opacity(0.7)
            }
        }
    }

    private var periodLabel: String {
        switch data.range {
        case .year: String(Calendar.current.component(.year, from: .now))
        case .month: "Last 30 days"
        case .week: "This week"
        case .all: "All time"
        }
    }

    @ViewBuilder private var listLayout: some View {
        if let img = artistImage, style.size != .square {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: Self.width - 56, height: style.size == .story ? 220 : 130)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        HStack(alignment: .top, spacing: 18) {
            if style.showArtists {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Top artists").font(style.font(11, .heavy)).opacity(0.75)
                    ForEach(Array(data.topArtists.prefix(5).enumerated()), id: \.offset) { i, a in
                        Text("\(i + 1)  \(a.artist.name)").font(style.font(15, .bold)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if style.showSongs {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Top songs").font(style.font(11, .heavy)).opacity(0.75)
                    ForEach(Array(data.topSongs.prefix(5).enumerated()), id: \.offset) { i, s in
                        Text("\(i + 1)  \(s.title)").font(style.font(15, .bold)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        stats
    }

    @ViewBuilder private var bigLayout: some View {
        if style.showMinutes {
            Text("\(Int(data.total / 60))").font(style.font(style.size == .square ? 70 : 96)).minimumScaleFactor(0.5).lineLimit(1)
            Text("minutes of music").font(style.font(20, .bold)).padding(.top, -10)
        }
        if style.showArtists, let a = data.topArtists.first {
            Text("Top artist").font(style.font(11, .heavy)).opacity(0.75)
            Text(a.artist.name).font(style.font(28)).lineLimit(1).minimumScaleFactor(0.6)
        }
        if style.showSongs, let s = data.topSongs.first {
            Text("Top song").font(style.font(11, .heavy)).opacity(0.75)
            Text(s.title).font(style.font(24)).lineLimit(2).minimumScaleFactor(0.6)
        }
        HStack(spacing: 20) {
            if style.showGenre, let g = data.genres.first { stat("Top genre", g.name) }
            if style.showStreak, data.streak.days > 1 { stat("Streak", "\(data.streak.days) days") }
        }
    }

    @ViewBuilder private var coverLayout: some View {
        HStack(spacing: 14) {
            if let img = songImage ?? artistImage {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: style.size == .square ? 110 : 150, height: style.size == .square ? 110 : 150)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("No. 1 song").font(style.font(11, .heavy)).opacity(0.75)
                Text(data.topSongs.first?.title ?? "").font(style.font(22)).lineLimit(3).minimumScaleFactor(0.6)
                Text(data.topSongs.first?.artist.name ?? "").font(style.font(14, .bold)).opacity(0.85)
            }
        }
        if style.showArtists {
            Text(data.topArtists.prefix(5).map(\.artist.name).joined(separator: " · "))
                .font(style.font(15, .bold)).lineLimit(3)
        }
        stats
    }

    private var stats: some View {
        HStack(spacing: 20) {
            if style.showMinutes { stat("Minutes", "\(Int(data.total / 60))") }
            if style.showGenre, let g = data.genres.first { stat("Top genre", g.name) }
            if style.showStreak, data.streak.days > 1 { stat("Streak", "\(data.streak.days)d") }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(style.font(11, .heavy)).opacity(0.75)
            Text(value).font(style.font(22)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

struct PatternView: View {
    let pattern: ShareCardStyle.Pattern
    let color: Color

    var body: some View {
        Canvas { gc, size in
            switch pattern {
            case .plain: break
            case .circles:
                for (x, y, r) in [(0.9, 0.08, 0.38), (0.05, 0.62, 0.3), (0.75, 0.9, 0.22)] {
                    let rr = size.width * r
                    gc.fill(Path(ellipseIn: CGRect(x: size.width * x - rr, y: size.height * y - rr, width: rr * 2, height: rr * 2)), with: .color(color.opacity(0.55)))
                }
            case .waves:
                for i in 0..<6 {
                    var p = Path()
                    let baseY = size.height * (0.15 + Double(i) * 0.16)
                    p.move(to: CGPoint(x: 0, y: baseY))
                    stride(from: 0.0, through: Double(size.width), by: 6).forEach { x in
                        p.addLine(to: CGPoint(x: x, y: baseY + sin(x / 38 + Double(i)) * 14))
                    }
                    gc.stroke(p, with: .color(color.opacity(0.5)), lineWidth: 6)
                }
            case .grid:
                let step: CGFloat = 30
                var p = Path()
                stride(from: 0, through: size.width, by: step).forEach { x in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                stride(from: 0, through: size.height, by: step).forEach { y in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                gc.stroke(p, with: .color(color.opacity(0.45)), lineWidth: 1.5)
            case .stripes:
                var p = Path()
                stride(from: -size.height, through: size.width, by: 34).forEach { x in
                    p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                }
                gc.stroke(p, with: .color(color.opacity(0.45)), lineWidth: 12)
            case .stars:
                var rng = SeededRNG(seed: 7)
                for _ in 0..<26 {
                    let x = Double.random(in: 0...Double(size.width), using: &rng)
                    let y = Double.random(in: 0...Double(size.height), using: &rng)
                    let r = Double.random(in: 4...14, using: &rng)
                    gc.fill(star(CGPoint(x: x, y: y), r), with: .color(color.opacity(0.7)))
                }
            }
        }
    }

    private func star(_ c: CGPoint, _ r: Double) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let rr = i.isMultiple(of: 2) ? r : r * 0.45
            let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct ShareCardEditor: View {
    let data: WrappedData
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var style = ShareCardStyle()
    @State private var rendered: UIImage?
    @State private var artistImage: UIImage?
    @State private var songImage: UIImage?
    @State private var tab = 0

    private var card: ShareCard {
        ShareCard(data: data, style: style, name: app.prefs.displayName, artistImage: artistImage, songImage: songImage)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let h = ShareCard.width / style.size.aspect
                    let scale = min(geo.size.width / ShareCard.width, geo.size.height / h) * 0.94
                    card
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        .scaleEffect(scale)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: style)
                }
                .padding(.vertical, 8)
                Picker("", selection: $tab) {
                    Text("Colors").tag(0); Text("Style").tag(1); Text("Info").tag(2); Text("Size").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                Group {
                    switch tab {
                    case 0: colors
                    case 1: looks
                    case 2: info
                    default: sizes
                    }
                }
                .frame(height: 150)
                HStack(spacing: 10) {
                    Button {
                        withAnimation { style = .random() }
                        app.haptic(.medium)
                    } label: { Image(systemName: "dice.fill").font(.title3) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Surprise me")
                    Button { save() } label: { Label("Save", systemImage: "square.and.arrow.down").lineLimit(1).frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .disabled(rendered == nil)
                    if let rendered {
                        ShareLink(item: Image(uiImage: rendered), preview: SharePreview("My Wrapped", image: Image(uiImage: rendered))) {
                            Label("Share", systemImage: "square.and.arrow.up").lineLimit(1).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .padding()
            }
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                if let a = data.topArtists.first?.artist {
                    artistImage = await ImageCache.shared.image(local: a.localPictureURL, remote: a.pictureURL, maxPixel: 600)
                }
                if let s = data.topSongs.first {
                    songImage = await ImageCache.shared.image(local: Paths.songArtwork(s.songID), remote: s.artworkURL, maxPixel: 600)
                }
                render()
            }
            .onChange(of: style) { _, _ in render() }
        }
    }

    private var colors: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ShareCardStyle.themes, id: \.0) { t in
                            Button {
                                style.background = t.1; style.shapes = t.2; style.text = t.3
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle().fill(t.1)
                                        Circle().fill(t.2).frame(width: 20).offset(x: 10, y: -10)
                                        Text("Aa").font(.caption.bold()).foregroundStyle(t.3)
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                    Text(t.0).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                HStack(spacing: 0) {
                    colorWell("Background", $style.background)
                    colorWell("Shapes", $style.shapes)
                    colorWell("Text", $style.text)
                }
                .padding(.horizontal)
            }
            .padding(.top, 12)
        }
    }

    /// A color picker with its name centered underneath, so the three line up evenly.
    private func colorWell(_ title: String, _ color: Binding<Color>) -> some View {
        VStack(spacing: 4) {
            ColorPicker(title, selection: color, supportsOpacity: false)
                .labelsHidden()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var looks: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                chipRow("Pattern", ShareCardStyle.Pattern.allCases.map(\.rawValue), style.pattern.rawValue) { style.pattern = .init(rawValue: $0) ?? .plain }
                chipRow("Font", ShareCardStyle.Typeface.allCases.map(\.rawValue), style.typeface.rawValue) { style.typeface = .init(rawValue: $0) ?? .rounded }
                chipRow("Layout", ShareCardStyle.Layout.allCases.map(\.rawValue), style.layout.rawValue) { style.layout = .init(rawValue: $0) ?? .list }
            }
            .padding(.top, 12)
        }
    }

    private var info: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                Toggle("Name", isOn: $style.showName)
                Toggle("Minutes", isOn: $style.showMinutes)
                Toggle("Artists", isOn: $style.showArtists)
                Toggle("Songs", isOn: $style.showSongs)
                Toggle("Genre", isOn: $style.showGenre)
                Toggle("Personality", isOn: $style.showPersonality)
                Toggle("Streak", isOn: $style.showStreak)
            }
            .font(.subheadline)
            .padding()
        }
    }

    private var sizes: some View {
        VStack {
            chipRow("Size", ShareCardStyle.Size.allCases.map(\.rawValue), style.size.rawValue) { style.size = .init(rawValue: $0) ?? .story }
            Text("Story fits Instagram and Snapchat stories. Post is 4:5 for feeds.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
        .padding(.top, 12)
    }

    private func chipRow(_ title: String, _ options: [String], _ selected: String, set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { o in Chip(title: o, selected: o == selected) { withAnimation { set(o) } } }
                }
                .padding(.horizontal)
            }
        }
    }

    private func render() {
        let r = ImageRenderer(content: card)
        r.scale = 3
        rendered = r.uiImage
    }

    private func save() {
        guard let img = rendered else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        app.haptic(.success)
        app.show("Saved to Photos")
    }
}
