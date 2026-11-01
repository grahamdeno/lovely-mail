import SwiftUI

struct PeopleView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""

    private var people: [Person] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.people.filter {
            q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.email.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("People").font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Pick up the conversation.")
                    .font(.body).foregroundStyle(Color(hex: 0x626C69))
                Label(store.mode == .sample ? "Demo · fictional connections" : "People from loaded inbox mail",
                      systemImage: "person.2")
                    .font(.caption).foregroundStyle(Color(hex: 0x626C69))
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Find a person or email address", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))

                if people.isEmpty {
                    Text(query.isEmpty ? "No people in the loaded mail yet." : "No matching people. Try a name or email address.")
                        .font(.body).foregroundStyle(Color(hex: 0x626C69))
                        .padding(.vertical, 24)
                }

                ForEach(people) { person in
                    let latest = store.posts(from: person).max { $0.email.date < $1.email.date }
                    Button { router.open(.thread(person)) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            AvatarView(person: person, size: 44)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(person.name).font(.headline)
                                Text(person.email).font(.caption)
                                    .foregroundStyle(Color(hex: 0x626C69))
                                if let latest {
                                    Text(latest.summary.sensitive ? "Private message" : latest.summary.headline)
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Latest loaded message · \(latest.email.date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(Color(hex: 0x626C69))
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption)
                                .foregroundStyle(Color(hex: 0x176B63))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the loaded conversation timeline")
                }
                Text("This list reflects loaded mail and the current sender heuristic, not your complete address book.")
                    .font(.caption).foregroundStyle(Color(hex: 0x626C69))
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .background(Color(hex: 0xF7F6F2))
        .foregroundStyle(Color(hex: 0x202827))
    }
}
