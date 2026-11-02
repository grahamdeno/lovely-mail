import SwiftUI

/// Search runs locally over the loaded mail and its on-device summaries.
struct SearchView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pinned: title and search field stay visible while results scroll.
            VStack(alignment: .leading, spacing: 0) {
                Text("Search").font(.title.weight(.bold)).accessibilityAddTraits(.isHeader).padding(.bottom, 12)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
                    TextField("People, subjects, anything", text: $query)
                        .focused($focused).submitLabel(.search).autocorrectionDisabled()
                }
                .padding(14).background(CalmStyle.field, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            .background(CalmStyle.background)
            Rectangle().fill(CalmStyle.divider).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let results = store.search(query)
                    if query.isEmpty {
                        Text("Searches the mail loaded on this phone. Nothing leaves it.")
                            .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 12)
                    } else if results.isEmpty {
                        Text("No matches in loaded mail.").font(.subheadline).foregroundStyle(CalmStyle.secondary).padding(.top, 12)
                    }
                    ForEach(results) { post in
                        MailRow(post: post, assessment: store.assessment(for: post),
                                onNotWaiting: { store.markNotWaiting(post, wholeSender: $0) },
                                onTrash: { Task { await store.moveToTrash(post) } })
                        Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .onAppear { focused = true }
    }
}
