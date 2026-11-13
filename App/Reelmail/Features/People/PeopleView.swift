import SwiftUI

struct PeopleView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @AppStorage(SplitPillBar.settingKey) private var splitPill = true
    /// With the split pill on, its field filters this list: one search field per screen (owner, Nov 9).
    private var activeQuery: String { query }
    private var people: [Person] {
        let q = activeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.contacts(.people).filter {
            q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.email.localizedCaseInsensitiveContains(q)
        }.sorted { left, right in
            let a = store.lastContact(left), b = store.lastContact(right)
            return a == b ? left.name < right.name : a > b
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            // Pinned: title and search stay visible while the list scrolls.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("People").font(.lovely(size: 32, weight: .semibold)).tracking(-0.8).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(store.mode == .sample ? "Demo" : "Loaded mail")
                        .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                }.padding(.bottom, 12)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CalmStyle.ink).accessibilityHidden(true)
                    TextField("Find a person or organization", text: $query)
                        .font(.lovely(.body))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Find a person by name or email address")
                }
                .padding(.horizontal, 16).frame(minHeight: 56).lifeCard(corner: 18)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            .background(CalmStyle.background)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let people = self.people
                    let groups = self.groups
                    let searching = !activeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if SplitPillBar.isQuestion(activeQuery) {
                        Button {
                            let text = activeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                            AskLovelyUsage().recordAsk(); router.searchText = ""; router.open(.askLovely(text))
                        } label: {
                            Label("Ask Lovely: \u{201C}\(activeQuery.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}", systemImage: "bubble.left")
                                .font(.lovely(.subheadline, .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous))
                        }
                        .buttonStyle(.plain).foregroundStyle(CalmStyle.blue).padding(.top, 12)
                    }
                    // Hidden while searching: results already include matching organizations.
                    if !searching, !groups.isEmpty {
                        OrganizationsShortcut(groups: groups).padding(.top, 4)
                    }
                    if people.isEmpty, groups.isEmpty {
                        Text(activeQuery.isEmpty ? "No people or organizations in the loaded mail yet." : "No matches.")
                            .font(.lovely(.body)).padding(.vertical, 24)
                    }
                    ForEach(people) { person in
                        let latest = store.conversation(with: person).last
                        Button { router.open(.thread(person)) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CalmAvatar(person: person, size: 44, waiting: store.needsReply(person))
                                VStack(alignment: .leading, spacing: 5) {
                                    ViewThatFits(in: .horizontal) {
                                        HStack { Text(person.name).font(.lovely(.headline)); Spacer(minLength: 8); time(latest) }
                                        VStack(alignment: .leading, spacing: 4) { Text(person.name).font(.lovely(.headline)); time(latest) }
                                    }
                                    if store.sharesName(person) {
                                        Text(person.email).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                                    }
                                    if let latest {
                                        Text(ConversationPresentation.rowText(latest, summary: store.post(for: latest)?.summary))
                                            .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                                    }
                                }
                                if store.hasUnread(person) {
                                    Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).padding(.top, 7)
                                        .accessibilityLabel("Unread loaded messages")
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .lifeCard(corner: 20)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Opens the loaded conversation")
                    }
                    if !groups.isEmpty {
                        // Searching shows every match; otherwise the three most recent, and the title opens the rest.
                        Button { router.open(.organizationList) } label: {
                            DigestTitle(text: "Organizations", count: groups.count, chevron: true)
                        }
                        .buttonStyle(.plain).padding(.top, 10).accessibilityHint("Shows all organizations")
                        ForEach(searching ? groups : Array(groups.prefix(3))) { group in
                            OrganizationRow(group: group).padding(.horizontal, 14).lifeCard(corner: 20)
                        }
                    }
                    Text(store.mode == .sample ? "Fictional connections and messages." : "People from loaded mail, not your complete address book.")
                        .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).padding(.top, 20)
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
    }
    /// Organizations, grouped by company, for the Organizations and All views.
    private var groups: [HomeDigest.OrganizationGroup] {
        let q = activeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.organizationGroups.filter { g in
            q.isEmpty || g.matches(q)
        }
    }

    @ViewBuilder private func time(_ email: Email?) -> some View {
        if let email {
            Text(MailTime.label(email.date)).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
    }
}

/// "Organizations · 12 ›" with up to four logos, under the search field. Opens the full list.
struct OrganizationsShortcut: View {
    @Environment(Router.self) private var router
    let groups: [HomeDigest.OrganizationGroup]
    var body: some View {
        Button { router.open(.organizationList) } label: {
            HStack(spacing: 10) {
                Text("Organizations · \(groups.count)").font(.lovely(.subheadline, .semibold))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    ForEach(groups.prefix(4)) { group in
                        CalmAvatar(person: group.posts[0].email.from, size: 26, organization: true, domain: group.domain)
                    }
                }
                Image(systemName: "chevron.right").font(.lovely(.caption, .bold)).foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).frame(minHeight: 60).frame(maxWidth: .infinity)
            .lifeCard(corner: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Organizations, \(groups.count)").accessibilityHint("Shows all organizations")
    }
}
