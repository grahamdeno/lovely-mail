import SwiftUI

/// Three primary destinations. Legacy name and geometry helpers remain for compatibility.
struct RollingTabBar: View {
    @Binding var selection: AppTab

    static let barHeight: CGFloat = 56
    static let indicatorSize: CGFloat = barHeight - RM.Radius.tabBarPadding * 2
    static func rotation(forIndex index: Int) -> Double { Double(index) * 90 }
    private let tabs: [AppTab] = [.home, .people, .search]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.body.weight(.semibold))
                        Text(tab.title).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(selection == tab ? Color(hex: 0x176B63) : Color(hex: 0x626C69))
                    .frame(maxWidth: .infinity, minHeight: Self.barHeight)
                    .background(selection == tab ? Color(hex: 0xEAF2EF) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Color(hex: 0xF7F6F2), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(Color(hex: 0xE4E8E3), lineWidth: 1)
        }
    }
}
