import SwiftUI

/// Clean up old login codes, or short-term mail past two weeks: Lovely shows every message first, then one tap moves
/// them to Gmail's Trash.
struct CleanupView: View {
    enum Kind { case logins, shortTerm }
    var kind: Kind = .logins
    @Environment(FeedStore.self) private var store
    @State private var age = AccountsCleanup.defaultAgeDays
    @State private var found: [MessageStub]?
    @State private var searching = false
    @State private var moved: Int?
    @State private var auto = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(kind == .logins
                         ? "Login codes, new-device checks and password resets you no longer need. Nothing moves until you tap the button, and Gmail keeps Trash for 30 days."
                         : "Mail you chose to keep for \(ShortTerm.keepDays) days, now past that. Gmail keeps Trash for 30 days.")
                        .font(.callout).foregroundStyle(CalmStyle.secondary)
                    if kind == .shortTerm {
                        Toggle("Move to Trash automatically after \(ShortTerm.keepDays) days", isOn: $auto)
                            .onChange(of: auto) { _, on in UserDefaults.standard.set(on, forKey: ShortTerm.autoKey(account: store.account ?? "")) }
                            .accessibilityIdentifier("shortTerm.auto")
                        Text(auto ? "Starred mail and mail from people you write to are never moved. You get the usual Undo bar."
                                  : "Off: Home tells you when some have expired, and nothing moves until you tap.")
                            .font(.caption).foregroundStyle(CalmStyle.secondary)
                    }
                    if kind == .logins {
                        Picker("Older than", selection: $age) {
                            Text("90 days").tag(90)
                            Text("1 year").tag(365)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: age) { _, _ in Task { await search() } }
                    }
                    if searching { ProgressView().frame(maxWidth: .infinity) }
                    if let moved {
                        Label("\(moved) moved to Trash.", systemImage: "checkmark.circle").font(.callout)
                    }
                    if let found {
                        if found.isEmpty {
                            Text("Nothing to clean up.").font(.headline)
                        } else {
                            Text(found.count == 1 ? "1 email" : "\(found.count) emails").font(.headline)
                            VStack(spacing: 0) {
                                ForEach(found.prefix(60), id: \.id) { stub in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stub.fromName.isEmpty ? stub.fromAddress : stub.fromName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(stub.subject).font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                                        Text(stub.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(CalmStyle.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    if stub.id != found.prefix(60).last?.id { Divider().overlay(CalmStyle.divider) }
                                }
                            }
                            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                            if found.count > 60 {
                                Text("and \(found.count - 60) more like these").font(.caption).foregroundStyle(CalmStyle.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            if let found, !found.isEmpty {
                Button("Move \(found.count) to Trash") {
                    let list = found
                    self.found = []
                    if kind == .logins { store.trashOldAccountNotices(list) { n in moved = n } }
                    else { store.trashExpiredShortTerm(list) { n in moved = n } }
                }
                .buttonStyle(SessionButtonStyle()).padding(20)
                .accessibilityIdentifier("cleanup.trash")
            }
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .navigationTitle(kind == .logins ? "Old login emails" : "Short-term mail").navigationBarTitleDisplayMode(.inline)
        .task {
            auto = ShortTerm.autoTrash(account: store.account ?? "")
            if found == nil { await search() }
        }
    }

    private func search() async {
        searching = true
        defer { searching = false }
        do { found = kind == .logins ? try await store.findOldAccountNotices(ageDays: age) : try await store.findExpiredShortTerm() }
        catch { found = []; store.errorMessage = "Could not search Gmail. \(error.localizedDescription)" }
    }
}
