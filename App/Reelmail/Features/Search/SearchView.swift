import SwiftUI

/// Search runs locally over the loaded mail and its on-device summaries.
struct SearchView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    /// Split pill on: the bottom field types here, so this page shows results only (with Ask Lovely on top).
    var pill = false
    private var activeQuery: String { pill ? router.searchText : query }
    @FocusState private var focused: Bool
    /// People and Organizations show their best five so Mail stays in view.
    private static let groupLimit = 5

    var body: some View {
        VStack(spacing: 0) {
            if pill {
                Button { router.open(.askLovely(router.searchText)); router.searchText = "" } label: {
                    Label("Ask Lovely about \u{201C}\(router.searchText)\u{201D}", systemImage: "sparkles")
                        .font(.subheadline.weight(.medium)).foregroundStyle(CalmStyle.onBlue).lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 14)
                        .background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous))
                }
                .buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)
                .accessibilityIdentifier("search.askLovely")
            } else {
            // Pinned: title and search field stay visible while results scroll.
            VStack(alignment: .leading, spacing: 0) {
                Text("Search").font(.title.weight(.bold)).accessibilityAddTraits(.isHeader).padding(.bottom, 12)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
                    TextField("People, organizations, subjects", text: $query)
                        .focused($focused).submitLabel(.search).autocorrectionDisabled()
                }
                .padding(14).background(CalmStyle.field, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            .background(CalmStyle.background)
            }
            Rectangle().fill(CalmStyle.divider).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let results = store.search(activeQuery)
                    let people = store.searchPeople(activeQuery)
                    let groups = store.searchOrganizations(activeQuery)
                    if activeQuery.isEmpty {
                        Text("Searches the mail loaded on this phone. Nothing leaves it.")
                            .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 12)
                    } else if results.isEmpty, people.isEmpty, groups.isEmpty {
                        Text("No matches in loaded mail.").font(.subheadline).foregroundStyle(CalmStyle.secondary).padding(.top, 12)
                    }
                    if !people.isEmpty {
                        DigestTitle(text: "People", count: people.count).padding(.top, 10)
                        ForEach(people.prefix(Self.groupLimit)) { person in
                            Button { router.open(.thread(person)) } label: {
                                HStack(spacing: 12) {
                                    CalmAvatar(person: person, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(person.name).font(.headline).lineLimit(1)
                                        Text(person.email).font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityHint("Opens the conversation")
                            Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                        }
                    }
                    if !groups.isEmpty {
                        DigestTitle(text: "Organizations", count: groups.count).padding(.top, 10)
                        ForEach(groups.prefix(Self.groupLimit)) { group in
                            OrganizationRow(group: group)
                            Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                        }
                    }
                    if !results.isEmpty, !people.isEmpty || !groups.isEmpty {
                        DigestTitle(text: "Mail", count: results.count).padding(.top, 10)
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
