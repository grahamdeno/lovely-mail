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

                ProfileCard(title: "Mail source", value: store.mode == .gmail ? "Gmail" : "Demo", detail: sourceDetail)

                if store.needsReconnect {
                    Text("Google signed you out. While Lovely is in testing this happens every 7 days. Your loaded mail is still here.")
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
                            Label(store.needsReconnect ? "Reconnect Gmail" : "Connect Gmail", systemImage: "envelope.badge.shield.half.filled").frame(maxWidth: .infinity)
                        }.buttonStyle(CalmActionStyle(prominent: true))
                    }
                }
                if let error = store.errorMessage, !store.needsReconnect {
                    Text(error).font(.caption).foregroundStyle(CalmStyle.secondary)
                }

                let status = ModelStatus.current
                ProfileCard(title: "On-device AI", value: status.title, detail: status.detail)

                OtherAddressesCard()

                ProfileCard(title: "Your rules", value: rulesSummary, detail: "Long-press a message to filter a sender or move it to Reading. Rules change this app only.")
                Button { showingFiltered = true } label: { Label("Review filtered senders", systemImage: "line.3.horizontal.decrease.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
                if !store.hiddenPosts.isEmpty {
                    Button { store.restoreAll() } label: { Label("Show hidden mail (\(store.hiddenPosts.count))", systemImage: "eye").frame(maxWidth: .infinity) }
                        .buttonStyle(CalmActionStyle())
                }
                Button { router.open(.sortingReview) } label: { Label("Review sorting", systemImage: "checkmark.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
                Button { router.open(.summaryLab) } label: { Label("Summary Lab", systemImage: "flask").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())

                Text("Lovely reads your Gmail and writes summaries on this iPhone. The one change it can make is moving a message to Gmail's Trash when you swipe it there, and you can undo that. It never sends mail, never deletes anything for good, and never changes labels. Loaded mail is kept encrypted on this phone and removed when you disconnect.")
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

/// Other addresses of yours. Mail from them is "Notes to self". You declare them; Lovely never guesses from names.
struct OtherAddressesCard: View {
    @Environment(FeedStore.self) private var store
    @State private var newAddress = ""
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your other addresses").font(.caption).foregroundStyle(CalmStyle.secondary)
            Text("Mail you send yourself from these shows under Notes to self, not Waiting on you.")
                .font(.caption).foregroundStyle(CalmStyle.secondary)
            ForEach(store.otherAddresses, id: \.self) { address in
                HStack {
                    Text(address).font(.subheadline).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Remove") { store.removeOtherAddress(address) }
                        .font(.subheadline).foregroundStyle(CalmStyle.blue).frame(minWidth: 44, minHeight: 44)
                }
            }
            HStack(spacing: 8) {
                TextField("name@example.com", text: $newAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    .padding(10).background(CalmStyle.background, in: RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.done).onSubmit(add)
                Button("Add", action: add).buttonStyle(CalmActionStyle(prominent: true))
                    .disabled(newAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(store.pendingOtherAddresses.sorted(), id: \.self) { address in
                Text("\(address) will be saved when your Gmail finishes loading.").font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(CalmStyle.roseInk) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }
    private func add() {
        switch store.addOtherAddress(newAddress) {
        case .added, .pending: problem = nil; newAddress = ""
        case .invalid: problem = "That doesn't look like an email address."
        case .notSaved(let reason): problem = reason
        }
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
