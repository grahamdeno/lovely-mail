import SwiftUI

/// Home's glance cards: a soft wash of the card's color, the big fact in full color. One color per kind, the same
/// everywhere. Rose stays for "waiting on you"; a real problem is amber with a warning mark.
struct GlanceGrid: View {
    @Environment(Router.self) private var router
    let cards: [GlanceCard]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(cards) { card in
                Button { router.open(route(card.kind)) } label: { GlanceCardView(card: card) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(identifier(card.kind))
            }
        }
    }

    private func route(_ kind: GlanceCard.Kind) -> Route {
        switch kind {
        case .comingUp: .comingUp
        case .money: .money
        case .kids: .kids
        case .energy: .energy
        case .earlier: .mailList("earlier")
        case .organizations: .organizationList
        }
    }

    private func identifier(_ kind: GlanceCard.Kind) -> String {
        switch kind {
        case .money: "home.row.money"
        case .kids: "home.row.kids"
        case .energy: "home.row.energy"
        default: "home.card." + kind.rawValue
        }
    }
}

struct GlanceCardView: View {
    let card: GlanceCard

    var body: some View {
        let tint = card.warning ? CalmStyle.warningInk : GlanceStyle.color(card.kind)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if card.warning { Image(systemName: "exclamationmark.triangle.fill").font(.caption) }
                Text(card.label).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(card.warning ? CalmStyle.warningInk : CalmStyle.secondary)
            Text(card.headline).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(card.detail).font(.footnote).foregroundStyle(CalmStyle.ink).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(card.warning ? CalmStyle.warning : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// One color per kind of card. Money green, Kids amber, Energy teal, Coming up airmail blue, the rest muted.
enum GlanceStyle {
    static func color(_ kind: GlanceCard.Kind) -> Color {
        switch kind {
        case .comingUp: CalmStyle.blue
        case .money: Color(light: 0x2F7D4F, dark: 0x6CCB8F, neon: 0x3DFF9A)
        case .kids: Color(light: 0xB06A00, dark: 0xF0B35A, neon: 0xFFC83D)
        case .energy: Color(light: 0x187A80, dark: 0x5CC8CE, neon: 0x2EF2FF)
        case .earlier, .organizations: CalmStyle.secondary
        }
    }
}
