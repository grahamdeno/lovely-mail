import SwiftUI

struct RollingTabBar: View {
    @Binding var selection: AppTab
    static let barHeight: CGFloat = 56
    static let indicatorSize: CGFloat = barHeight - RM.Radius.tabBarPadding * 2
    static func rotation(forIndex index: Int) -> Double { Double(index) * 90 }
    private let tabs: [AppTab] = [.home, .people, .search]
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.body.weight(.semibold))
                        if !typeSize.isAccessibilitySize { Text(tab.title).font(.caption.weight(.medium)).lineLimit(1) }
                    }
                    .foregroundStyle(selection == tab ? CalmStyle.blue : CalmStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: Self.barHeight)
                    .background(selection == tab ? CalmStyle.blue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(tab.title).accessibilityIdentifier("tab." + tab.title.lowercased())
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }.padding(6)
            .background(CalmStyle.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(CalmStyle.divider, lineWidth: 1) }
    }
}
