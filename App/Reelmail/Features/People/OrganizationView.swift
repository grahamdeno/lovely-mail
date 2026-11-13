import SwiftUI

/// A row for one organization: logo, name, last message time, how many messages from how many senders.
struct OrganizationRow: View {
    @Environment(Router.self) private var router
    let group: HomeDigest.OrganizationGroup
    var body: some View {
        Button { router.open(.organization(group.id)) } label: {
            HStack(alignment: .center, spacing: 12) {
                CalmAvatar(person: group.posts[0].email.from, size: 44, organization: true, domain: group.domain)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(group.name).font(.lovely(.headline)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MailTime.label(group.latest)).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                    }
                    Text(group.senders.count > 1 ? "\(group.posts.count) messages from \(group.senders.count) senders"
                                                 : "\(group.posts.count) message\(group.posts.count == 1 ? "" : "s")")
                        .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                }
            }
            .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityHint("Opens this organization")
    }
}

extension HomeDigest.OrganizationGroup {
    /// Matches the name, the company domain or any sending address.
    func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || (domain?.localizedCaseInsensitiveContains(query) ?? false)
            || senders.contains { $0.address.localizedCaseInsensitiveContains(query) }
    }
}

/// Every organization in loaded mail, A to Z. Search matches the name and the domain.
struct OrganizationListView: View {
    @Environment(FeedStore.self) private var store
    @State private var query = ""
    private var groups: [HomeDigest.OrganizationGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.organizationGroups
            .filter { q.isEmpty || $0.matches(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        let groups = self.groups
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if groups.isEmpty, !query.isEmpty { Text("No matches.").padding(.vertical, 24) }
                ForEach(groups) { group in
                    OrganizationRow(group: group)
                    Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                }
            }.padding(.horizontal, 20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Organizations").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or domain")
        .autocorrectionDisabled().textInputAutocapitalization(.never)
    }
}

/// One organization: every sender of one company together, with what needs you on top and each sending
/// address listed so you can quiet one (say, marketing) and keep the rest.
struct OrganizationView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let key: String

    private let insets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)

    var body: some View {
        Group {
            if let group = store.organizationGroup(key) {
                content(group)
            } else {
                Text("No mail from this organization is loaded right now.").foregroundStyle(CalmStyle.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(CalmStyle.background)
            }
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ group: HomeDigest.OrganizationGroup) -> some View {
        let profile = store.profile(for: group)
        let needsYou = group.posts.filter { [.waiting, .dated].contains(store.section(for: $0)) }
        let rest = group.posts.filter { ![.waiting, .dated].contains(store.section(for: $0)) }
        let recent = group.posts.filter { Date().timeIntervalSince($0.email.date) <= 30 * 86_400 }.count
        return List {
            header(group, profile: profile, recent: recent, needsYou: needsYou.count)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden).listRowBackground(CalmStyle.background)

            if !needsYou.isEmpty {
                DigestTitle(text: "Needs you", count: needsYou.count, rose: true)
                    .listRowInsets(insets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
                rows(needsYou)
            }
            ForEach([FeedSection.updates, .reading, .people, .notes], id: \.self) { section in
                let posts = rest.filter { store.section(for: $0) == section }
                if !posts.isEmpty {
                    DigestTitle(text: section.title, count: posts.count)
                        .listRowInsets(insets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
                    rows(posts)
                }
            }

            DigestTitle(text: "Senders", count: group.senders.count)
                .listRowInsets(insets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
            ForEach(group.senders, id: \.address) { sender in
                senderRow(sender.address, count: sender.count, groupCount: group.senders.count)
                    .lifeListRow()
            }
            if let domain = group.domain?.lowercased(), !LocalTriageRules.publicDomains.contains(domain) {
                let key = "@" + domain
                let on = store.rules.filteredSenders.contains(key)
                Button {
                    if on { store.unfilterSender(key) } else { store.filterSender(key) }
                } label: {
                    Label(on ? "Show mail from \(domain) again" : "Filter everything from \(domain)",
                          systemImage: on ? "arrow.uturn.backward" : "line.3.horizontal.decrease.circle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain).foregroundStyle(on ? CalmStyle.blue : CalmStyle.roseInk)
                .listRowInsets(insets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
            }
            Text("Senders group by company domain. Long-press a sender to split it out, or use Merge to join another organization.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).padding(.vertical, 16)
                .listRowInsets(insets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let others = store.organizationGroups.filter { $0.id != group.id }
                if !others.isEmpty {
                    Menu {
                        Section("Merge \(group.name) into") {
                            ForEach(others.prefix(30)) { other in
                                Button(other.name) { store.merge(group, into: other); dismiss() }
                            }
                        }
                    } label: { Text("Merge") }
                }
            }
        }
    }

    private func header(_ group: HomeDigest.OrganizationGroup, profile: PersonProfile, recent: Int, needsYou: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CalmAvatar(person: group.posts[0].email.from, size: 56, organization: true, domain: group.domain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.lovely(.title2, .bold)).lineLimit(2)
                    Text(group.domain ?? "Grouped by sender name").font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("THE SHORT VERSION").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                Text(profile.shortVersion).font(.lovely(.body)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 8) {
                stat("\(group.posts.count)", profile.since.map { "emails since " + $0.formatted(.dateTime.month(.abbreviated)) } ?? "emails")
                stat("\(recent)", "last 30 days")
                stat("\(needsYou)", "need you")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.lovely(.title3, .bold)).lineLimit(1)
            Text(label).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
        }
        // Every tile fills the row's height so the three line up even when one label wraps.
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func rows(_ posts: [Post]) -> some View {
        ForEach(posts) { post in
            MailRow(post: post, assessment: store.assessment(for: post), compact: true,
                    onTrash: { Task { await store.moveToTrash(post) } })
                .lifeListRow()
        }
    }

    private func senderRow(_ address: String, count: Int, groupCount: Int) -> some View {
        let rule = store.rules.decision(messageID: "", sender: address).destination
        let isSplit = store.rules.organizationOverrides[address] != nil
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(address).font(.lovely(.subheadline)).lineLimit(1).truncationMode(.middle)
                Text(rule == .reading ? "\(count) · goes to Reading" : rule == .filtered ? "\(count) · filtered" : "\(count) message\(count == 1 ? "" : "s")")
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button { store.setSenderRule(address, destination: .reading) } label: { Label("Send to Reading", systemImage: "newspaper") }
                Button { store.filterSender(address) } label: { Label("Filter this sender", systemImage: "line.3.horizontal.decrease.circle") }
                if rule != .inbox {
                    Button { store.setSenderRule(address, destination: nil) } label: { Label("Remove sender rule", systemImage: "arrow.uturn.backward") }
                }
                if isSplit {
                    Button { store.splitOut(sender: address, false) } label: { Label("Group automatically again", systemImage: "arrow.triangle.merge") }
                } else if groupCount > 1 {
                    Button { store.splitOut(sender: address) } label: { Label("Split this sender out", systemImage: "arrow.triangle.branch") }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.lovely(.title3)).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Options for \(address)")
        }
        .padding(.vertical, 6)
    }
}
