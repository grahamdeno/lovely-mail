import SwiftUI

/// Custom tab bar. The active tab is a white rounded square that rolls to the next tab,
/// turning 90° per tab like a die, with a spring. Icons stay upright. Reduce Motion: instant.
struct RollingTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let barHeight: CGFloat = 56
    static let indicatorSize: CGFloat = barHeight - RM.Radius.tabBarPadding * 2  // 44

    /// Degrees of roll for a tab index: one quarter turn per tab travelled.
    static func rotation(forIndex index: Int) -> Double { Double(index) * 90 }

    var body: some View {
        GeometryReader { geo in
            let tabs = AppTab.allCases
            let pad = RM.Radius.tabBarPadding
            let slot = (geo.size.width - pad * 2) / CGFloat(tabs.count)
            let index = selection.rawValue
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: RM.Radius.activeTab, style: .continuous)
                    .fill(Color.white)
                    .frame(width: Self.indicatorSize, height: Self.indicatorSize)
                    .rotationEffect(.degrees(Self.rotation(forIndex: index)))
                    .offset(x: pad + slot * CGFloat(index) + (slot - Self.indicatorSize) / 2)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        Button {
                            select(tab)
                        } label: {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(tab == selection ? RM.Palette.ink : RM.Palette.secondary)
                                .frame(width: slot, height: Self.barHeight)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(tab == selection ? .isSelected : [])
                    }
                }
                .padding(.horizontal, pad)
            }
            .frame(height: Self.barHeight)
        }
        .frame(height: Self.barHeight)
        .background(RM.Palette.surface)
        .rmCorner(RM.Radius.tabBar)
        .overlay(
            RoundedRectangle(cornerRadius: RM.Radius.tabBar, style: .continuous)
                .strokeBorder(RM.Palette.hairline, lineWidth: 1)
        )
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func select(_ tab: AppTab) {
        guard tab != selection else { return }
        if reduceMotion {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { selection = tab }
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { selection = tab }
        }
    }
}
