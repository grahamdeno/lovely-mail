import SwiftUI

/// Settings › Forwarding addresses. Mail is forwarded only to addresses listed here.
struct ForwardingAddressesView: View {
    @Environment(FeedStore.self) private var store
    @State private var addresses = ForwardAllowlist().addresses
    @State private var entry = ""
    @State private var preview: ActionPreview?
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                ForEach(addresses, id: \.self) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a)
                        Button(ShoeboxRule.address() == a ? "This is your Shoebox address" : "Use as Shoebox address") { ShoeboxRule.setAddress(a); addresses = ForwardAllowlist().addresses }
                            .font(.caption).disabled(ShoeboxRule.address() == a)
                        Button("Ask Gmail to verify") { preview = ActionPreview(kind: .forwardingAddress, title: "Add a forwarding address in Gmail",
                            lines: ["Gmail will email a confirmation code to this address.", "You confirm it once, then filters can forward to it."], recipients: [a]) }
                            .font(.caption)
                    }
                }
                .onDelete { offsets in offsets.map { addresses[$0] }.forEach { ForwardAllowlist().remove($0) }; addresses = ForwardAllowlist().addresses }
                HStack {
                    TextField("Add an address", text: $entry).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                    Button("Add") { if ForwardAllowlist().add(entry) { entry = ""; addresses = ForwardAllowlist().addresses } else { status = "That does not look like an email address." } }
                        .disabled(entry.isEmpty)
                }
            } header: { Text("Allowed addresses") } footer: {
                Text("Lovely forwards mail only to these. Add your Shoebox address here first.")
            }
            if let status { Section { Text(status).font(.caption) } }
        }
        .navigationTitle("Forwarding addresses").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { p in
            ActionPreviewSheet(preview: p, confirmTitle: "Ask Gmail") { confirmed in
                guard let actions = store.actions, let address = p.recipients.first else { status = "Connect Gmail first."; return }
                Task {
                    do { try await actions.addForwardingAddress(address, confirmed: confirmed); status = "Gmail sent a code to \(address). Confirm it there once." }
                    catch { status = error.localizedDescription }
                }
            }
        }
    }
}

/// Settings › Gmail filters: only filters Lovely made.
struct GmailFiltersView: View {
    @Environment(FeedStore.self) private var store
    @State private var filters = FilterRegistry().filters
    @State private var preview: ActionPreview?
    @State private var status: String?

    var body: some View {
        List {
            if filters.isEmpty { Text("Lovely has not made any filters.").foregroundStyle(CalmStyle.secondary) }
            ForEach(filters) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Text("From " + f.sender)
                    if let to = f.forwardTo { Text("Forwards to " + to).font(.caption).foregroundStyle(CalmStyle.secondary) }
                    if f.label != nil { Text("Adds a Lovely label").font(.caption).foregroundStyle(CalmStyle.secondary) }
                    Button("Delete", role: .destructive) {
                        preview = ActionPreview(id: f.gmailID, kind: .deleteFilter, title: "Delete this filter",
                                                lines: ["Mail from \(f.sender) will no longer be forwarded or labeled by it.", "Mail already forwarded stays where it went."])
                    }.font(.caption)
                }
            }
            if let status { Text(status).font(.caption) }
        }
        .navigationTitle("Gmail filters").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { p in
            ActionPreviewSheet(preview: p, confirmTitle: "Delete filter") { confirmed in
                guard let actions = store.actions else { status = "Connect Gmail first."; return }
                Task {
                    do { try await actions.deleteFilter(id: p.id, confirmed: confirmed); filters = FilterRegistry().filters }
                    catch { status = error.localizedDescription }
                }
            }
        }
    }
}

/// Settings › Gmail activity: everything Lovely sent, forwarded, filed or filtered.
struct GmailActivityView: View {
    @State private var entries = ActivityLog().entries

    var body: some View {
        List {
            if entries.isEmpty { Text("Lovely has not changed anything in Gmail beyond Trash and Done.").foregroundStyle(CalmStyle.secondary) }
            ForEach(entries.reversed()) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.summary)
                    Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(CalmStyle.secondary)
                }
            }
        }
        .navigationTitle("Gmail activity").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Clear") { ActivityLog().clear(); entries = [] }.disabled(entries.isEmpty) }
    }
}
