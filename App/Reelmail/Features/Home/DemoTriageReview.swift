import SwiftUI

struct DemoTriageReviewLink: View {
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            Label("Try filtering · demo only", systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(hex: 0x176B63))
        .background(Color(hex: 0xF7F6F2))
        .sheet(isPresented: $presented) { DemoTriageReview() }
    }
}

private struct DemoTriageReview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rules = LocalTriageRules(accountID: "demo-review")
    @State private var selected: LocalMailDestination = .inbox
    @State private var pendingSender: String?
    private let destinations: [LocalMailDestination] = [.inbox, .reading, .filtered]

    private var messages: [Email] {
        SampleData.emails.filter { rules.decision(messageID: $0.id, sender: $0.from.email).destination == selected }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("Your choices, less noise.").font(.title.weight(.semibold))
                    Text("Fictional mail only. Decisions are saved on this device for this demo review. They do not change Home, real mail, or Gmail. No AI spam classifier is active here.")
                        .font(.subheadline).foregroundStyle(Color(hex: 0x626C69))
                    if let error = rules.persistenceError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(Color(hex: 0x956018))
                    }
                    Picker("Review group", selection: $selected) {
                        ForEach(destinations, id: \.self) { destination in
                            Text(destination.rawValue.capitalized).tag(destination)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("\(messages.count) messages").font(.caption)
                    if messages.isEmpty {
                        Text("Nothing in this group. Use a message’s Organize menu to try routing.")
                            .font(.body).padding(.vertical, 24)
                    }
                    ForEach(messages) { email in
                        reviewCard(email)
                    }
                }
                .padding(20)
            }
            .background(Color(hex: 0xF7F6F2))
            .foregroundStyle(Color(hex: 0x202827))
            .navigationTitle("Filtering demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Filter this sender in the demo?",
                isPresented: Binding(get: { pendingSender != nil }, set: { if !$0 { pendingSender = nil } }),
                titleVisibility: .visible) {
                Button("Save sender rule") {
                    if let sender = pendingSender { rules.setSender(sender, destination: .filtered) }
                    pendingSender = nil
                }
                Button("Cancel", role: .cancel) { pendingSender = nil }
            } message: {
                Text("All demo messages from \(pendingSender ?? "this sender") will use this rule unless a message has its own decision. You can remove the sender rule from any of its messages.")
            }
        }
    }

    private func reviewCard(_ email: Email) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(email.from.name).font(.headline)
            Text(email.subject).font(.subheadline)
            Text(rules.decision(messageID: email.id, sender: email.from.email).reason)
                .font(.caption).foregroundStyle(Color(hex: 0x626C69))
            Menu {
                Button("Keep this message in demo Inbox") { rules.setMessage(email.id, destination: .inbox) }
                Button("Move this message to demo Reading") { rules.setMessage(email.id, destination: .reading) }
                Button("Filter this message in demo") { rules.setMessage(email.id, destination: .filtered) }
                Divider()
                Button("Always filter this demo sender…") { pendingSender = email.from.email }
                Button("Remove this message’s decision") { rules.setMessage(email.id, destination: nil) }
                Button("Remove this sender’s rule") { rules.setSender(email.from.email, destination: nil) }
            } label: {
                Label("Organize", systemImage: "ellipsis.circle").frame(minHeight: 44)
            }
            .disabled(rules.persistenceError != nil)
            .tint(Color(hex: 0x176B63))
            DisclosureGroup("View fictional source") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(email.from.email)
                    Text(email.body)
                }
                .font(.subheadline).textSelection(.enabled).padding(.top, 8)
            }
            .tint(Color(hex: 0x176B63))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
    }
}
