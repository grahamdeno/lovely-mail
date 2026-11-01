import SwiftUI

struct PeopleView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    private var topics: [MailTopic] { MailTopic.make(posts: store.activePosts, sent: store.sentByMe) }
    private var people: [Person] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = topics
        return store.people.filter {
            q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.email.localizedCaseInsensitiveContains(q)
        }.sorted { leftPerson, rightPerson in
            let left = snapshot.first(where: { $0.person.id == leftPerson.id })?.updatedAt ?? .distantPast
            let right = snapshot.first(where: { $0.person.id == rightPerson.id })?.updatedAt ?? .distantPast
            return left == right ? leftPerson.name < rightPerson.name : left > right
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("People").font(.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(store.mode == .sample ? "Demo" : "Partial history").font(.caption).foregroundStyle(CalmStyle.secondary)
                }.padding(.bottom, 16)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
                    TextField("Find a person", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Find a person by name or email address")
                }.padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 14)).padding(.bottom, 12)
                if people.isEmpty { Text(query.isEmpty ? "No conversations yet." : "No matching people.").padding(.vertical, 24) }
                ForEach(people) { person in
                    let topic = topics.first { $0.person.id == person.id }
                    Button { router.open(.thread(person)) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            CalmAvatar(person: person, size: 44)
                            VStack(alignment: .leading, spacing: 5) {
                                ViewThatFits(in: .horizontal) {
                                    HStack { Text(person.name).font(.headline); Spacer(minLength: 8); time(topic) }
                                    VStack(alignment: .leading, spacing: 4) { Text(person.name).font(.headline); time(topic) }
                                }
                                if store.people.contains(where: { $0.id != person.id && $0.name == person.name }) {
                                    Text(person.email).font(.caption).foregroundStyle(CalmStyle.secondary)
                                }
                                if let topic {
                                    Text(topic.title).font(.subheadline).lineLimit(1)
                                    Text((topic.preview.label.map { $0 + ": " } ?? "") + topic.preview.text)
                                        .font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                                }
                            }
                            if store.activePosts.contains(where: { $0.email.from.id == person.id && $0.email.isUnread }) {
                                Circle().fill(CalmStyle.blue).frame(width: 6, height: 6).padding(.top, 7).accessibilityLabel("Unread loaded messages")
                            }
                        }.padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityHint("Opens the conversation and original messages")
                    Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                }
                Text(store.mode == .sample ? "Fictional conversations." : "Loaded inbox only. Sent history is not imported yet.")
                    .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 20)
            }.padding(20)
        }.background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
    }
    @ViewBuilder private func time(_ topic: MailTopic?) -> some View {
        if let topic { Text(MailTime.label(topic.updatedAt)).font(.caption).foregroundStyle(CalmStyle.secondary) }
    }
}
