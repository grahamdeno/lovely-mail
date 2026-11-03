import SwiftUI

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
                    .listRowInsets(insets).listRowBackground(CalmStyle.background).listRowSeparatorTint(CalmStyle.divider)
            }
            Text("Senders group by company domain. Long-press a sender to split it out, or use Merge to join another organization.")
                .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.vertical, 16)
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
                    Text(group.name).font(.title2.weight(.bold)).lineLimit(2)
                    Text(group.domain ?? "Grouped by sender name").font(.subheadline).foregroundStyle(CalmStyle.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("THE SHORT VERSION").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                Text(profile.shortVersion).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 8) {
                stat("\(group.posts.count)", profile.since.map { "emails since " + $0.formatted(.dateTime.month(.abbreviated)) } ?? "emails")
                stat("\(recent)", "last 30 days")
                stat("\(needsYou)", "need you")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(2)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func rows(_ posts: [Post]) -> some View {
        ForEach(posts) { post in
            MailRow(post: post, assessment: store.assessment(for: post), compact: true,
                    onTrash: { Task { await store.moveToTrash(post) } })
                .listRowInsets(insets).listRowBackground(CalmStyle.background).listRowSeparatorTint(CalmStyle.divider)
        }
    }

    private func senderRow(_ address: String, count: Int, groupCount: Int) -> some View {
        let rule = store.rules.decision(messageID: "", sender: address).destination
        let isSplit = store.rules.organizationOverrides[address] != nil
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(address).font(.subheadline).lineLimit(1).truncationMode(.middle)
                Text(rule == .reading ? "\(count) · goes to Reading" : rule == .filtered ? "\(count) · filtered" : "\(count) message\(count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button { store.setSenderRule(address, destination: .reading) } label: { Label("Send to Reading", systemImage: "newspaper") }
                Button { store.setSenderRule(address, destination: .filtered) } label: { Label("Filter this sender", systemImage: "line.3.horizontal.decrease.circle") }
                if rule != .inbox {
                    Button { store.setSenderRule(address, destination: nil) } label: { Label("Remove sender rule", systemImage: "arrow.uturn.backward") }
                }
                if isSplit {
                    Button { store.splitOut(sender: address, false) } label: { Label("Group automatically again", systemImage: "arrow.triangle.merge") }
                } else if groupCount > 1 {
                    Button { store.splitOut(sender: address) } label: { Label("Split this sender out", systemImage: "arrow.triangle.branch") }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Options for \(address)")
        }
        .padding(.vertical, 6)
    }
}
