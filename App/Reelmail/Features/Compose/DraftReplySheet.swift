import SwiftUI
import UIKit

/// Shows a suggested reply. Only "Copy" and "Open in Gmail". Reelmail never sends.
struct DraftReplySheet: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    let post: Post
    @State private var replyAll = false

    @State private var draft = ""
    @State private var engine: SummaryEngine = .fallback
    @State private var loading = true
    @State private var copied = false
    @State private var sendPreview: ActionPreview?

    var body: some View { sheetBody.lifeSheet() }


    @ViewBuilder private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Draft reply").font(.lovely(.title3, .semibold))
                Spacer()
                Text(engine == .appleIntelligence ? "Written on this iPhone" : "Starter text")
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            if offersReplyAll {
                Picker("Reply to", selection: $replyAll) {
                    Text("Reply").tag(false)
                    Text("Reply all").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Text(ReplyRecipients.summaryLine(plan, email: post.email))
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
            Text(GmailCompose.replySubject(post.email.subject))
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)

            ZStack {
                TextEditor(text: $draft)
                    .scrollContentBackground(.hidden)
                    .font(.lovely(.body))
                    .padding(8)
                    .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("draft.editor")
                if loading { ProgressView() }
            }

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = draft
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(CalmActionStyle())
                Spacer()
                if sendable {
                    Button { previewSend() } label: { Label("Send", systemImage: "paperplane") }.accessibilityIdentifier("draft.send")
                        .buttonStyle(CalmActionStyle(prominent: true)).disabled(!canSend).opacity(canSend ? 1 : 0.5)
                }
                Button { openInGmail() } label: { Label("Open in Gmail", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(CalmActionStyle(prominent: !sendable))
            }
            Text(sendable ? "Lovely sends only what you approve. After you confirm, you have 10 seconds to undo."
                         : "Review and send it yourself in Gmail.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
        
        .sheet(item: $sendPreview) { p in
            ActionPreviewSheet(preview: p, confirmTitle: "Send") { confirmed in send(confirmed) }
        }
        .task { replyAll = router.draftReplyAll && offersReplyAll; router.draftReplyAll = false; await makeDraft() }
    }

    private var mine: Set<String> { Set([store.account ?? ""] + store.otherAddresses).subtracting([""]) }
    private var offersReplyAll: Bool { ReplyRecipients.offersReplyAll(post.email, mine: mine, organization: store.isAutomated(post)) }
    private var plan: ReplyRecipients.Plan {
        replyAll && offersReplyAll ? ReplyRecipients.replyAll(post.email, mine: mine) : ReplyRecipients.reply(post.email)
    }

    private var myName: String {
        store.mode == .gmail ? "" : store.me.firstName
    }

    private func makeDraft() async {
        // A reply you sent and then undid comes back as you left it.
        if let saved = store.savedDrafts.removeValue(forKey: post.id) {
            draft = saved; engine = .fallback; loading = false; return
        }
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

    /// One recipient and no one copied: the only kind of reply Lovely sends itself. Decided before the draft loads,
    /// so the sheet doesn't change its mind while you watch.
    private var sendable: Bool {
        store.actions != nil && plan.to.count == 1 && plan.cc.isEmpty && !post.email.isFromMe
    }

    /// And a draft you can see.
    private var canSend: Bool { sendable && !loading && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var recipient: String { plan.to.first.map { EmailPresentation.address(in: $0).lowercased() } ?? "" }

    private func previewSend() {
        let subject = GmailCompose.replySubject(post.email.subject)
        sendPreview = ActionPreview(kind: .send, title: "Send this reply", lines: ["Subject: \(subject)", draft], recipients: [recipient])
    }

    private func send(_ confirmed: ConfirmedAction) {
        guard let actions = store.actions else { return }
        let subject = GmailCompose.replySubject(post.email.subject)
        let to = recipient, body = draft, thread = post.email.threadId, postID = post.id
        let store = store
        store.undo.enqueue(title: "Sending reply to \(to)",
                           work: { try await actions.sendReply(to: to, subject: subject, body: body, threadID: thread, inReplyTo: nil, confirmed: confirmed) },
                           finished: { error in
                               if let error { store.savedDrafts[postID] = body; store.errorMessage = "The reply was not sent. Your text is saved; tap Reply to try again. \(error.localizedDescription)" }
                           },
                           undone: { store.savedDrafts[postID] = body; store.errorMessage = "Not sent. Your reply is saved; tap Reply to finish it." })
        dismiss()
    }

    private func openInGmail() {
        let subject = GmailCompose.replySubject(post.email.subject)
        let to = plan.toLine, cc = plan.ccLine
        guard let app = GmailCompose.appURL(to: to, cc: cc, subject: subject, body: draft) else { return }
        openURL(app) { accepted in
            if !accepted, let web = GmailCompose.webURL(to: to, cc: cc, subject: subject, body: draft) {
                openURL(web)
            }
        }
    }
}
