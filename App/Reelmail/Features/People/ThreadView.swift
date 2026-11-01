import SwiftUI

/// A chronological view over loaded mail, not a claim of complete mailbox history.
struct ThreadView: View {
    @Environment(FeedStore.self) private var store
    let person: Person

    var body: some View {
        let messages = store.conversation(with: person)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(person.name).font(.title.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(person.email).font(.subheadline).textSelection(.enabled)
                    Label(store.mode == .sample ? "Demo conversation · fictional mail" : "Partial Gmail history",
                          systemImage: "info.circle")
                        .font(.caption.weight(.medium))
                    Text(store.mode == .sample
                         ? "Incoming and outgoing sample messages appear together below."
                         : "Only loaded inbox messages are shown. Sent and archived history are not imported yet.")
                        .font(.caption).foregroundStyle(Color(hex: 0x626C69))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

                if messages.isEmpty {
                    Label("No loaded messages with this person", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline).padding(.vertical, 24)
                }

                ForEach(messages) { email in
                    TimelineMessage(email: email, summary: store.post(for: email)?.summary)
                }
            }
            .padding(20)
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

private struct TimelineMessage: View {
    let email: Email
    let summary: EmailSummary?

    private var sensitive: Bool { summary?.sensitive == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(email.isFromMe ? "You" : email.from.name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(email.isFromMe ? "Sent" : "Received")
                    .font(.caption).foregroundStyle(Color(hex: 0x626C69))
            }
            Text(email.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(Color(hex: 0x626C69))
            Text(sensitive ? "Private message" : email.subject)
                .font(.headline)
            if sensitive {
                Label("Private details hidden. Expand the source to read.", systemImage: "lock")
                    .font(.subheadline)
            } else if let summary {
                Text(summary.blurb).font(.body)
                Text("Generated summary · verify important details in the source")
                    .font(.caption).foregroundStyle(Color(hex: 0x626C69))
            } else {
                Text("Summary unavailable. Expand the source to read this message.")
                    .font(.subheadline).foregroundStyle(Color(hex: 0x626C69))
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("From: \(email.from.email)")
                    Text("To: \(email.to.joined(separator: ", "))")
                    Text("Recipient details reflect the current import; CC and Reply-To are not available in this view.")
                        .font(.caption).foregroundStyle(Color(hex: 0x626C69))
                    Divider()
                    Text(email.body.isEmpty ? "No readable body was imported." : email.body)
                        .font(.body)
                }
                .font(.subheadline)
                .textSelection(.enabled)
                .padding(.top, 12)
            } label: {
                Label("Source email · plain text", systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
            .tint(Color(hex: 0x176B63))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(email.isFromMe ? Color(hex: 0xEAF2EF) : Color.white,
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(Color(hex: 0xE4E8E3), lineWidth: 1)
        }
    }
}
