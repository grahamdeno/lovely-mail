import SwiftUI

struct PeopleView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    private var people: [Person] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.people.filter {
            q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.email.localizedCaseInsensitiveContains(q)
        }.sorted { left, right in
            let a = store.conversation(with: left).last?.date ?? .distantPast
            let b = store.conversation(with: right).last?.date ?? .distantPast
            return a == b ? left.name < right.name : a > b
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("People").font(.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(store.mode == .sample ? "Demo" : "Loaded mail")
                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                }.padding(.bottom, 16)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
                    TextField("Find a person", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Find a person by name or email address")
                }
                .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 12)
                if people.isEmpty {
                    Text(query.isEmpty ? "No people in the loaded mail yet." : "No matching people.")
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
                                if store.people.contains(where: { $0.id != person.id && $0.name == person.name }) {
                                    Text(person.email).font(.caption).foregroundStyle(CalmStyle.secondary)
                                }
                                if let latest {
                                    let preview = ConversationPresentation.preview(latest, summary: store.post(for: latest)?.summary)
                                    Text((latest.isFromMe ? "You: " : "") + (preview.label.map { $0 + ": " } ?? "") + preview.text)
                                        .font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                                }
                            }
                            if store.activePosts.contains(where: { $0.email.from.id == person.id && $0.email.isUnread }) {
                                Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).padding(.top, 7)
                                    .accessibilityLabel("Unread loaded messages")
                            }
                        }
                        .padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityHint("Opens the loaded conversation")
                    Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                }
                Text(store.mode == .sample ? "Fictional connections and messages." : "People from loaded mail, not your complete address book.")
                    .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 20)
            }.padding(20)
        }.background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
    }
    @ViewBuilder private func time(_ email: Email?) -> some View {
        if let email {
            Text(MailTime.label(email.date)).font(.caption).foregroundStyle(CalmStyle.secondary)
        }
    }
}
