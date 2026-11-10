import SwiftUI

/// The split pill (owner, Nov 9): a small Home and People pill beside one "Ask or search" field, in place of the tab bar.
/// Typing shows search results right away with Ask Lovely on top; return on a question asks Lovely. Easy to roll back:
/// Settings > Look and feel > Split pill off brings back the tab bar and Home's ask field.
/// Corners match the app's fields and buttons (14, continuous), not capsules.
struct SplitPillBar: View {
    static let corner: CGFloat = 14
    @Environment(Router.self) private var router
    @FocusState private var focused: Bool

    static let settingKey = "lovely.nav.splitPill"
    static var isOn: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    var body: some View {
        @Bindable var router = router
        HStack(spacing: 8) {
            if !focused && router.searchText.isEmpty {
                HStack(spacing: 2) {
                    segment(.home, symbol: "house", label: "Home")
                    segment(.people, symbol: "person.2", label: "People")
                }
                .padding(3)
                .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).strokeBorder(CalmStyle.divider))
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
                TextField("Ask or search", text: $router.searchText)
                    .focused($focused).submitLabel(.search).autocorrectionDisabled()
                    .onSubmit { submit() }
                    .accessibilityIdentifier("pill.field")
                if focused || !router.searchText.isEmpty {
                    Button("Cancel") { router.searchText = ""; focused = false }
                        .font(.subheadline).foregroundStyle(CalmStyle.blue)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).strokeBorder(CalmStyle.divider))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: focused)
    }

    private func segment(_ tab: AppTab, symbol: String, label: String) -> some View {
        let on = router.tab == tab
        return Button { router.tab = tab } label: {
            Image(systemName: on ? symbol + ".fill" : symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(on ? CalmStyle.blue : CalmStyle.secondary)
                .frame(width: 44, height: 38)
                .background(on ? CalmStyle.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: Self.corner - 3, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("pill.\(label.lowercased())")
    }

    /// Return on a question (a "?" or four or more words) asks Lovely; a word or a name stays a search.
    private func submit() {
        let text = router.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SplitPillBar.isQuestion(text) else { focused = false; return }
        AskLovelyUsage().recordAsk()
        router.searchText = ""
        focused = false
        router.open(.askLovely(text))
    }

    static func isQuestion(_ text: String) -> Bool {
        text.contains("?") || text.split(separator: " ").count >= 4
    }
}
