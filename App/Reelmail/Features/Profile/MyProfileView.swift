import SwiftUI

/// Account, connection state, rules and the Summary Lab.
struct MyProfileView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showingFiltered = false

    private var sourceDetail: String {
        switch (store.mode, store.gmailConfigured) {
        case (.gmail, _):
            var parts = [store.account ?? ""]
            parts.append("\(store.posts.count) inbox messages, \(store.sentByMe.count) sent")
            if let fetched = store.lastFetched { parts.append("updated " + MailTime.label(fetched).lowercased()) }
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        case (.sample, true): return "Fictional mail. Connect Gmail to see your own."
        case (.sample, false): return "This build has no Gmail configuration, so it shows fictional mail."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Profile").font(.title.weight(.bold)).accessibilityAddTraits(.isHeader).padding(.bottom, 2)

                ProfileCard(title: "Mail source", value: store.mode == .gmail ? "Gmail, read-only" : "Demo", detail: sourceDetail)

                if store.needsReconnect {
                    Text("Google signed you out. While Reelmail is in testing this happens every 7 days. Your loaded mail is still here.")
                        .font(.subheadline).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
                }
                if store.gmailConfigured {
                    if store.mode == .gmail, !store.needsReconnect {
                        Button { Task { await store.disconnectGmail() } } label: {
                            Label("Disconnect Gmail", systemImage: "envelope.badge.shield.half.filled").frame(maxWidth: .infinity)
                        }.buttonStyle(CalmActionStyle())
                    } else {
                        Button { Task { await store.connectGmail() } } label: {
                            Label(store.needsReconnect ? "Reconnect Gmail" : "Connect Gmail (read-only)", systemImage: "envelope.badge.shield.half.filled").frame(maxWidth: .infinity)
                        }.buttonStyle(CalmActionStyle(prominent: true))
                    }
                }
                if let error = store.errorMessage, !store.needsReconnect {
                    Text(error).font(.caption).foregroundStyle(CalmStyle.secondary)
                }

                let status = ModelStatus.current
                ProfileCard(title: "On-device AI", value: status.title, detail: status.detail)

                ProfileCard(title: "Your rules", value: rulesSummary, detail: "Long-press a message to filter a sender or move it to Reading. Rules change this app only.")
                Button { showingFiltered = true } label: { Label("Review filtered senders", systemImage: "line.3.horizontal.decrease.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
                if !store.hiddenPosts.isEmpty {
                    Button { store.restoreAll() } label: { Label("Show hidden mail (\(store.hiddenPosts.count))", systemImage: "eye").frame(maxWidth: .infinity) }
                        .buttonStyle(CalmActionStyle())
                }
                Button { router.open(.summaryLab) } label: { Label("Summary Lab", systemImage: "flask").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())

                Text("Reelmail reads Gmail with read-only permission, writes summaries on this iPhone, and never sends, deletes or changes your mail. Loaded mail is kept encrypted on this phone and removed when you disconnect.")
                    .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 6)
            }
            .padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .sheet(isPresented: $showingFiltered) { FilteredMailReview() }
    }

    private var rulesSummary: String {
        let filtered = Set(store.filteredPosts.map(\.email.from.email)).count
        return filtered == 0 ? "No senders filtered" : (filtered == 1 ? "1 sender filtered" : "\(filtered) senders filtered")
    }
}

struct ProfileCard: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(CalmStyle.secondary)
            Text(value).font(.headline)
            Text(detail).font(.caption).foregroundStyle(CalmStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
