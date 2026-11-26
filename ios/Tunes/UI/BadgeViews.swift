import SwiftUI

/// Every badge, with its tier and progress.
struct BadgesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var statuses: [BadgeStatus] = []
    @State private var selected: BadgeStatus?

    var body: some View {
        let earnedTiers = statuses.reduce(0) { $0 + $1.tier.rawValue }
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 18) {
                    count(.gold); count(.silver); count(.bronze)
                }
                .padding(.top, 8)
                Text("\(earnedTiers) of \(statuses.count * 3) medals earned").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 22) {
                    ForEach(statuses) { s in
                        Button { selected = s } label: {
                            VStack(spacing: 8) {
                                MedalView(icon: s.def.icon, tier: s.tier, size: 76, progress: s.progressToNext)
                                Text(s.def.name).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(s.tier == .none ? "\(s.value)/\(s.def.tiers[0])" : s.tier.label)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal)
                Text("Badges are just for fun and showing off. You can put them on your Home screen in Customize Home.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            }
        }
        .themeBackground()
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { s in BadgeDetail(status: s).presentationDetents([.medium]) }
        .onAppear { statuses = Badges.evaluate(); Badges.refreshFacts { statuses = Badges.evaluate() } }
    }

    private func count(_ tier: BadgeTier) -> some View {
        VStack(spacing: 4) {
            MedalView(icon: "medal.fill", tier: tier, size: 40)
            Text("\(statuses.filter { $0.tier >= tier }.count)").font(.headline.monospacedDigit())
        }
    }
}

/// One badge up close: what it's for and how far you are.
struct BadgeDetail: View {
    let status: BadgeStatus
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 14) {
            MedalView(icon: status.def.icon, tier: status.tier, size: 120)
                .padding(.top, 24)
            Text(status.def.name).font(.title2.bold())
            Text(status.def.blurb).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 14) {
                ForEach([BadgeTier.bronze, .silver, .gold], id: \.self) { t in
                    let goal = status.def.tiers[t.rawValue - 1]
                    VStack(spacing: 6) {
                        MedalView(icon: status.def.icon, tier: status.tier >= t ? t : .none, size: 46)
                        Text("\(Fmt.count(goal)) \(status.def.unit)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            if let next = status.def.next(after: status.value) {
                VStack(spacing: 6) {
                    ProgressView(value: status.progressToNext).tint(look.accent)
                    Text("\(Fmt.count(status.value)) of \(Fmt.count(next)) \(status.def.unit)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            } else {
                Label("Maxed out", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.yellow)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .themeBackground()
    }
}

/// The badges row for Profile and Home: your best medals, with a link to all of them.
struct BadgeShelf: View {
    var size: CGFloat = 64
    @Environment(AppModel.self) private var app
    @State private var earned: [BadgeStatus] = []

    var body: some View {
        Group {
            if earned.isEmpty {
                HStack(spacing: 12) {
                    MedalView(icon: "medal.fill", tier: .none, size: size * 0.75)
                    Text("No badges yet. Listen, explore and make playlists to earn bronze, silver and gold.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(earned) { s in
                            VStack(spacing: 6) {
                                MedalView(icon: s.def.icon, tier: s.tier, size: size)
                                Text(s.def.name).font(.caption2.weight(.semibold)).lineLimit(1).frame(width: size + 16)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .onAppear { earned = app.earnedBadges }
    }
}
