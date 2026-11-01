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
        VStack(alignment: .leading, spacing: RM.Space.m) {
            HStack {
                Text("Draft reply").font(RM.Typo.title).foregroundStyle(.white)
                Spacer()
                Text(engine == .appleIntelligence ? "Written on device" : "Template")
                    .font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
            }
            Text("To \(post.email.from.name) · \(GmailCompose.replySubject(post.email.subject))")
                .font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary).lineLimit(1)

            ZStack {
                TextEditor(text: $draft)
                    .scrollContentBackground(.hidden)
                    .font(RM.Typo.body)
                    .foregroundStyle(.white)
                    .padding(RM.Space.s)
                    .background(RM.Palette.surface)
                    .rmCorner(RM.Radius.card)
                if loading { ProgressView().tint(.white) }
            }

            HStack(spacing: RM.Space.s) {
                Button {
                    UIPasteboard.general.string = draft
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(RMButtonStyle(kind: .ghostDark))
                Spacer()
                Button { openInGmail() } label: { Label("Open in Gmail", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(RMButtonStyle(kind: .ghostLight))
                    .background(Color.white)
                    .rmCorner(RM.Radius.button)
            }
            Text("Reelmail never sends email. You review and send it yourself in Gmail.")
                .font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
        }
        .padding(RM.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RM.Palette.sheet)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(RM.Radius.sheet)
        .task { await makeDraft() }
    }

    private func makeDraft() async {
        let drafter = ReplyDrafterFactory.best()
        let fallback = TemplateReplyDrafter()
        do {
            draft = try await drafter.draft(replyTo: post.email, myName: store.me.firstName)
            engine = drafter.engine
        } catch {
            draft = (try? await fallback.draft(replyTo: post.email, myName: store.me.firstName)) ?? ""
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
