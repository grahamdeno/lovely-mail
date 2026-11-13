import SwiftUI

/// Moves mail filed under the first categories (Money, Kids, Orders, Personal) to the new ones, one group at a
/// time. Each group: preview, the owner's tap, 10-second Undo. Only Lovely labels change.
struct CategoryResortView: View {
    @Environment(FeedStore.self) private var store
    @State private var groups: [CategoryResort.Group] = []
    @State private var truncated = false
    @State private var loading = false
    @State private var failed: String?
    @State private var preview: ActionPreview?
    @State private var pending: CategoryResort.Group?
    @State private var moved: Set<String> = []

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) { ProgressView(); Text("Reading your Lovely labels…").foregroundStyle(CalmStyle.secondary) }
                    .listRowBackground(CalmStyle.card)
            } else if let failed {
                Text(failed).foregroundStyle(CalmStyle.secondary).listRowBackground(CalmStyle.card)
            } else if groups.isEmpty {
                Text("Nothing to move. Your filed mail already matches your categories.")
                    .foregroundStyle(CalmStyle.secondary).listRowBackground(CalmStyle.card)
            } else {
                Section {
                    ForEach(groups) { g in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.title).font(.lovely(.body, .medium))
                                Text((g.examples.first.map { $0 + " \u{00B7} " } ?? "") + "\(g.messageIDs.count) email\(g.messageIDs.count == 1 ? "" : "s")")
                                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if moved.contains(g.id) {
                                Label("Moved", systemImage: "checkmark").font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.secondary)
                            } else {
                                Button("Move") { pending = g; preview = CategoryResort.preview(g) }
                                    .buttonStyle(.borderedProminent).accessibilityIdentifier("resort.move.\(g.id)")
                            }
                        }
                        .frame(minHeight: 44)
                    }
                } header: { Text("Each group moves when you tap") } footer: {
                    Text("Adds the new Lovely label and removes the old one. Your own labels, the inbox and read status don't change. Undo for 10 seconds after each."
                         + (truncated ? " Showing the most recent 150 emails per label; run it again for the rest." : ""))
                }
                .listRowBackground(CalmStyle.card)
            }
        }
        .calmForm()
        .navigationTitle("Move to new categories").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $preview) { p in
            ActionPreviewSheet(preview: p, confirmTitle: "Move") { confirmed in
                guard let g = pending else { return }
                moved.insert(g.id)
                store.applyResort(g, confirmed: confirmed) { error in
                    if error != nil { moved.remove(g.id); failed = "Couldn't move \(g.title). Nothing else changed. Try again." }
                }
            }
        }
    }

    private func load() async {
        guard store.mode == .gmail, store.actions != nil else { failed = "Connect Gmail with filing turned on to move mail."; return }
        loading = true; failed = nil
        defer { loading = false }
        do {
            let plan = try await store.resortPlan()
            groups = plan.groups; truncated = plan.truncated
        } catch {
            failed = RefreshProblem.message(for: error)
        }
    }
}
