import SwiftUI
import UIKit

/// Shows a suggested reply. Only "Copy" and "Open in Gmail". Reelmail never sends.
struct DraftReplySheet: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let post: Post

    @State private var draft = ""
    @State private var engine: SummaryEngine = .fallback
    @State private var loading = true
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Draft reply").font(.title3.weight(.semibold))
                Spacer()
                Text(engine == .appleIntelligence ? "Written on this iPhone" : "Starter text")
                    .font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            Text("To \(post.email.from.name) · \(GmailCompose.replySubject(post.email.subject))")
                .font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(1)

            ZStack {
                TextEditor(text: $draft)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                if loading { ProgressView() }
            }

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = draft
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(CalmActionStyle())
                Spacer()
                Button { openInGmail() } label: { Label("Open in Gmail", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(CalmActionStyle(prominent: true))
            }
            Text("Lovely never sends email. Review and send it yourself in Gmail.")
                .font(.caption).foregroundStyle(CalmStyle.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
        .preferredColorScheme(.light)
        .task { await makeDraft() }
    }

    private var myName: String {
        store.mode == .gmail ? "" : store.me.firstName
    }

    private func makeDraft() async {
        let drafter = ReplyDrafterFactory.best()
        let fallback = TemplateReplyDrafter()
        do {
            draft = try await drafter.draft(replyTo: post.email, myName: myName)
            engine = drafter.engine
        } catch {
            draft = (try? await fallback.draft(replyTo: post.email, myName: myName)) ?? ""
            engine = .fallback
        }
        loading = false
    }

    private func openInGmail() {
        let subject = GmailCompose.replySubject(post.email.subject)
        let to = post.email.from.email
        guard let app = GmailCompose.appURL(to: to, subject: subject, body: draft) else { return }
        openURL(app) { accepted in
            if !accepted, let web = GmailCompose.webURL(to: to, subject: subject, body: draft) {
                openURL(web)
            }
        }
    }
}
