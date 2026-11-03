import SwiftUI

struct PeopleView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var kind: FeedStore.ContactKind = .people
    private var people: [Person] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Organizations are listed as grouped companies below, so this list is people only.
        return (kind == .organizations ? [] : store.contacts(.people)).filter {
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
                    Text("People").font(.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(store.mode == .sample ? "Demo" : "Loaded mail")
                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                }.padding(.bottom, 12)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
                    TextField("Find a person", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Find a person by name or email address")
                }
                .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
                Picker("Show", selection: $kind) {
                    ForEach(FeedStore.ContactKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.top, 10)
                .accessibilityLabel("Show people, organizations or all")
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            .background(CalmStyle.background)
            Rectangle().fill(CalmStyle.divider).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let people = self.people
                    let groups = self.groups
                    if people.isEmpty, groups.isEmpty {
                        Text(query.isEmpty ? (kind == .organizations ? "No organizations in the loaded mail yet." : "No people in the loaded mail yet.")
                                           : "No matches.")
                            .font(.body).padding(.vertical, 24)
                    }
                    ForEach(people) { person in
                        let latest = store.conversation(with: person).last
                        Button { router.open(.thread(person)) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CalmAvatar(person: person, size: 44, waiting: store.needsReply(person))
                                VStack(alignment: .leading, spacing: 5) {
                                    ViewThatFits(in: .horizontal) {
                                        HStack { Text(person.name).font(.headline); Spacer(minLength: 8); time(latest) }
                                        VStack(alignment: .leading, spacing: 4) { Text(person.name).font(.headline); time(latest) }
                                    }
                                    if store.sharesName(person) {
                                        Text(person.email).font(.caption).foregroundStyle(CalmStyle.secondary)
                                    }
                                    if let latest {
                                        let preview = ConversationPresentation.preview(latest, summary: store.post(for: latest)?.summary)
                                        Text((latest.isFromMe ? "You: " : "") + FallbackSummarizer.firstSentence(of: preview.text))
                                            .font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                                    }
                                }
                                if store.hasUnread(person) {
                                    Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).padding(.top, 7)
                                        .accessibilityLabel("Unread loaded messages")
                                }
                            }
                            .padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Opens the loaded conversation")
                        Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                    }
                    if !groups.isEmpty {
                        if kind == .all {
                            Text("ORGANIZATIONS").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                                .padding(.top, 22).padding(.bottom, 4)
                        }
                        ForEach(groups) { group in
                            Button { router.open(.organization(group.id)) } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    CalmAvatar(person: group.posts[0].email.from, size: 44, organization: true, domain: group.domain)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack { Text(group.name).font(.headline).lineLimit(1); Spacer(minLength: 8); time(group.posts.first?.email) }
                                        Text(group.senders.count > 1 ? "\(group.posts.count) messages from \(group.senders.count) senders" : "\(group.posts.count) message\(group.posts.count == 1 ? "" : "s")")
                                            .font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityHint("Opens this organization")
                            Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                        }
                    }
                    Text(store.mode == .sample ? "Fictional connections and messages." : "People from loaded mail, not your complete address book.")
                        .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 20)
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
    }
    /// Organizations, grouped by company, for the Organizations and All views.
    private var groups: [HomeDigest.OrganizationGroup] {
        guard kind != .people else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.organizationGroups.filter { g in
            q.isEmpty || g.name.localizedCaseInsensitiveContains(q) || g.senders.contains { $0.address.localizedCaseInsensitiveContains(q) }
        }
    }

    @ViewBuilder private func time(_ email: Email?) -> some View {
        if let email {
            Text(MailTime.label(email.date)).font(.caption).foregroundStyle(CalmStyle.secondary)
        }
    }
}
