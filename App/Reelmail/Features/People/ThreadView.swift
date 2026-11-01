import SwiftUI

struct ThreadView: View {
    @Environment(FeedStore.self) private var store
    let person: Person

    var body: some View {
        let messages = store.conversation(with: person)
        ScrollView {
            LazyVStack(spacing: 12) {
                VStack(spacing: 8) {
                    AvatarView(person: person, size: 48).accessibilityHidden(true)
                    Text(person.name).font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(store.mode == .sample ? "Fictional demo conversation" : "Partial Gmail history")
                        .font(.caption).foregroundStyle(Color(hex: 0x626C69))
                    DisclosureGroup("Conversation details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(person.email).textSelection(.enabled)
                            Text(store.mode == .sample
                                 ? "Incoming and outgoing fictional mail."
                                 : "Only loaded inbox mail is shown; sent and archived history are not imported yet.")
                            Text("Short messages show imported original text. Longer messages may show a labeled summary or excerpt. Verify important details in the email. Read-only; no sending here.")
                        }
                        .font(.caption).padding(.top, 8)
                    }
                    .font(.caption).tint(Color(hex: 0x176B63))
                }
                .padding(.bottom, 16)

                if messages.isEmpty {
                    Text("No loaded messages with this person.")
                        .font(.body).foregroundStyle(Color(hex: 0x626C69))
                }

                ForEach(Array(messages.enumerated()), id: \.element.id) { index, email in
                    let previous: Email? = index > 0 ? messages[index - 1] : nil
                    let summary = store.post(for: email)?.summary
                    let grouped = ConversationPresentation.groups(email, after: previous)
                    if previous == nil || !Calendar.current.isDate(email.date, inSameDayAs: previous!.date) {
                        Text(email.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(hex: 0x626C69))
                            .padding(.vertical, 8)
                    }
                    if previous?.threadId != email.threadId {
                        Text(ConversationPresentation.isSensitive(email, summary: summary) ? "Private email topic" : email.subject)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(hex: 0x626C69))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    ConversationBubble(email: email, summary: summary, grouped: grouped)
                }
            }
            .padding(16)
        }
        .background(Color(hex: 0xF7F6F2))
        .foregroundStyle(Color(hex: 0x202827))
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: 0xF7F6F2), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
    }
}

private struct ConversationBubble: View {
    let email: Email
    let summary: EmailSummary?
    let grouped: Bool
    @State private var showingDetails = false

    private var secondaryInk: Color {
        email.isFromMe ? Color.white.opacity(0.9) : Color(hex: 0x626C69)
    }

    var body: some View {
        let preview = ConversationPresentation.preview(email, summary: summary)
        HStack(alignment: .bottom, spacing: 0) {
            if email.isFromMe { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 6) {
                if email.to.count > 1 {
                    Label("Additional recipients · see details", systemImage: "person.2")
                        .font(.caption).foregroundStyle(secondaryInk)
                }
                if let label = preview.label {
                    Text(label).font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryInk)
                }
                if preview.concealed {
                    Label(preview.text, systemImage: "lock").font(.body)
                } else {
                    Text(preview.text).font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                HStack(spacing: 12) {
                    if !grouped {
                        Text(email.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                    }
                    Button { showingDetails = true } label: {
                        Text("Details").font(.caption)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show original email and details")
                }
                .foregroundStyle(secondaryInk)
            }
            .foregroundStyle(email.isFromMe ? Color.white : Color(hex: 0x202827))
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(email.isFromMe ? Color(hex: 0x245FCC) : Color(hex: 0xECEEEA),
                        in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(email.isFromMe ? "Your email" : "Email from \(email.from.name)")
            if !email.isFromMe { Spacer(minLength: 36) }
        }
        .padding(.top, grouped ? 0 : 6)
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(email.subject).font(.headline)
                        Text("From: \(email.from.email)")
                        Text("To: \(email.to.joined(separator: ", "))")
                        Text(email.date.formatted(date: .abbreviated, time: .shortened))
                        Text("Imported plain text; CC and Reply-To are not yet available.")
                            .font(.caption).foregroundStyle(Color(hex: 0x626C69))
                        Divider()
                        Text(email.body.isEmpty ? "No readable body was imported." : email.body)
                            .font(.body)
                    }
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .background(Color(hex: 0xF7F6F2))
                .foregroundStyle(Color(hex: 0x202827))
                .navigationTitle("Email details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingDetails = false }
                    }
                }
                .tint(Color(hex: 0x245FCC))
            }
            .preferredColorScheme(.light)
        }
    }
}
