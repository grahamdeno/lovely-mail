import SwiftUI

/// Search runs locally over the loaded mail and its on-device summaries.
struct SearchView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Search").font(.title.weight(.bold)).accessibilityAddTraits(.isHeader).padding(.bottom, 16)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
                    TextField("People, subjects, anything", text: $query)
                        .focused($focused).submitLabel(.search).autocorrectionDisabled()
                }
                .padding(14).background(CalmStyle.field, in: RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 12)
                let results = store.search(query)
                if query.isEmpty {
                    Text("Searches the mail loaded on this phone. Nothing leaves it.")
                        .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 8)
                } else if results.isEmpty {
                    Text("No matches in loaded mail.").font(.subheadline).foregroundStyle(CalmStyle.secondary).padding(.top, 8)
                }
                ForEach(results) { post in
                    MailRow(post: post, section: store.section(for: post))
                    Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                }
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focused = true }
    }
}
