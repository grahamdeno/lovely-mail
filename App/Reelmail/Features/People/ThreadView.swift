import SwiftUI

struct ThreadView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let person: Person
    @State private var showingInfo = false
    var body: some View {
        let messages = store.conversation(with: person)
        let latestIncoming = messages.last { !$0.isFromMe }.flatMap { store.post(for: $0) }
        ScrollView {
            LazyVStack(spacing: 10) {
                Text(store.mode == .sample ? "Demo · fictional conversation" : "Recent mail with \(person.firstName) · read-only")
                    .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.bottom, 4)
                if messages.isEmpty { Text("No loaded messages with this person.").padding(.vertical, 24) }
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, email in
                    let previous: Email? = index > 0 ? messages[index - 1] : nil
                    let summary = store.post(for: email)?.summary
                    if previous.map({ !Calendar.current.isDate(email.date, inSameDayAs: $0.date) }) ?? true {
                        Text(email.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.vertical, 8)
                    }
                    if previous?.threadId != email.threadId {
                        Text(ConversationPresentation.isSensitive(email, summary: summary) ? "Private topic" : email.subject)
                            .font(.caption.weight(.medium)).foregroundStyle(CalmStyle.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 4)
                    }
                    ConversationBubble(email: email, summary: summary,
                        grouped: ConversationPresentation.groups(email, after: previous))
                }
            }.padding(16)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .safeAreaInset(edge: .bottom) {
            if let latestIncoming {
                HStack {
                    Text("Draft here, send in Gmail").font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer()
                    Button { router.draftPostID = latestIncoming.id } label: { Label("Draft reply", systemImage: "arrowshape.turn.up.left") }
                        .buttonStyle(CalmActionStyle(prominent: true)).lineLimit(1).fixedSize()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .navigationTitle(person.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showingInfo = true } label: {
                    HStack(spacing: 8) {
                        CalmAvatar(person: person, size: 28)
                        Text(person.name).font(.headline).foregroundStyle(CalmStyle.ink).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(CalmStyle.secondary)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("Conversation details for \(person.name)")
            }
        }
        .toolbarBackground(CalmStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .sheet(isPresented: $showingInfo) {
            ConversationInfoSheet(person: person, mode: store.mode)
        }
    }
}

private struct ConversationBubble: View {
    let email: Email
    let summary: EmailSummary?
    let grouped: Bool
    @State private var showingDetails = false
    private var secondaryInk: Color { email.isFromMe ? Color.white.opacity(0.9) : CalmStyle.secondary }
    var body: some View {
        let preview = ConversationPresentation.preview(email, summary: summary)
        HStack(alignment: .bottom, spacing: 0) {
            if email.isFromMe { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 6) {
                if email.to.count > 1 {
                    Label("Additional recipients · see source", systemImage: "person.2")
                        .font(.caption).foregroundStyle(secondaryInk)
                }
                if let label = preview.label {
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(secondaryInk)
                }
                if preview.concealed {
                    Label(preview.text, systemImage: "lock").font(.body)
                } else {
                    Text(preview.text).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                HStack(spacing: 12) {
                    if !grouped { Text(email.date.formatted(date: .omitted, time: .shortened)).font(.caption2) }
                    Button { showingDetails = true } label: {
                        Text("Source").font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Show original email and details")
                }.foregroundStyle(secondaryInk)
            }
            .foregroundStyle(email.isFromMe ? Color.white : CalmStyle.ink)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            .background(email.isFromMe ? CalmStyle.blue : CalmStyle.bubble, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(email.isFromMe ? "Your email" : "Email from \(email.from.name)")
            if !email.isFromMe { Spacer(minLength: 36) }
        }
        .padding(.top, grouped ? 0 : 6)
        .sheet(isPresented: $showingDetails) { EmailSourceSheet(email: email) }
    }
}

private struct ConversationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let person: Person
    let mode: DataMode
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(person.name).font(.title2.weight(.semibold))
                    Text(person.email).textSelection(.enabled)
                    Text(mode == .sample ? "Fictional incoming and outgoing demo mail." : "Recent Primary inbox mail and your sent replies from the last 90 days. Older history stays in Gmail.")
                    Text("Short messages show original imported text. Longer messages show a labeled summary or excerpt when available. Generated summaries can be imperfect; verify details in the source.")
                    Text("Read-only. Nothing can be sent from this screen.")
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
            .navigationTitle("Conversation details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CalmStyle.blue).preferredColorScheme(.light)
    }
}

private struct EmailSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let email: Email
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(email.subject).font(.headline)
                    Text("From: \(email.from.email)")
                    Text("To: \(email.to.joined(separator: ", "))")
                    Text(email.date.formatted(date: .abbreviated, time: .shortened))
                    if !email.cc.isEmpty { Text("Cc: \(email.cc.joined(separator: ", "))") }
                    Divider()
                    Text(email.body.isEmpty ? "No readable body was imported." : email.body).font(.body)
                }.font(.subheadline).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
            .navigationTitle("Source email").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CalmStyle.blue).preferredColorScheme(.light)
    }
}
