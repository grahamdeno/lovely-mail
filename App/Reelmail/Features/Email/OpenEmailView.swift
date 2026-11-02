import SwiftUI

/// The original email: full headers and untouched text, with the summary above it for context.
struct OpenEmailView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    let postID: String

    var body: some View {
        if let post = store.posts.first(where: { $0.id == postID }) {
            let email = post.email
            let assessment = store.assessment(for: post)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        CalmAvatar(person: email.from, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(email.from.name).font(.headline)
                            Text(email.from.email).font(.caption).foregroundStyle(CalmStyle.secondary).textSelection(.enabled)
                        }
                        Spacer()
                    }
                    Text(email.subject.isEmpty ? "(no subject)" : email.subject).font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 6) {
                        HeaderLine(key: "To", value: email.to.joined(separator: ", "))
                        if !email.cc.isEmpty { HeaderLine(key: "Cc", value: email.cc.joined(separator: ", ")) }
                        HeaderLine(key: "Date", value: email.date.formatted(date: .abbreviated, time: .shortened))
                    }
                    WhyItsHere(post: post, assessment: assessment)
                    if !ConversationPresentation.isSensitive(email, summary: post.summary) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.summary.engine == .appleIntelligence ? "Summary" : "Excerpt")
                                .font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
                            Text(post.summary.blurb).font(.subheadline)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CalmStyle.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }
                    HStack(spacing: 8) {
                        if !store.isAutomated(post) {
                            Button { router.draftPostID = post.id } label: { Label("Draft reply", systemImage: "arrowshape.turn.up.left") }
                                .buttonStyle(CalmActionStyle(prominent: true)).lineLimit(1).fixedSize()
                        }
                        Button { openInGmail(email) } label: { Label("Open in Gmail", systemImage: "arrow.up.forward.app") }
                            .buttonStyle(CalmActionStyle()).lineLimit(1).fixedSize()
                        Spacer(minLength: 0)
                        Button { store.hide(post); router.path.removeLast() } label: {
                            Text("Hide").font(.subheadline).foregroundStyle(CalmStyle.secondary).frame(minWidth: 44, minHeight: 40)
                        }.buttonStyle(.plain).accessibilityLabel("Hide in Lovely")
                        Button { Task { await store.moveToTrash(post) }; router.path.removeLast() } label: {
                            Text("Trash").font(.subheadline).foregroundStyle(CalmStyle.roseInk).frame(minWidth: 44, minHeight: 40)
                        }.buttonStyle(.plain).accessibilityLabel("Move to Gmail Trash")
                    }
                    Text(email.body.isEmpty ? "No readable text was imported." : email.body)
                        .font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    Text("Hide only affects this app. Trash moves the message to Gmail\u{2019}s Trash, where it stays for 30 days.")
                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                }
                .padding(20)
            }
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
            .navigationTitle("Source email").navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Email not found", systemImage: "envelope").background(CalmStyle.background)
        }
    }

    private func openInGmail(_ email: Email) {
        // Reply context only; nothing is sent. The user presses Send in Gmail.
        let subject = GmailCompose.replySubject(email.subject)
        guard let app = GmailCompose.appURL(to: email.from.email, subject: subject, body: "") else { return }
        openURL(app) { ok in
            if !ok, let web = GmailCompose.webURL(to: email.from.email, subject: subject, body: "") { openURL(web) }
        }
    }
}

/// The triage decision in plain words, with the one correction that matters.
struct WhyItsHere: View {
    @Environment(FeedStore.self) private var store
    let post: Post
    let assessment: TriageAssessment
    /// A display name is never proof of identity, so a match only prompts a question; you decide.
    private var looksLikeYou: Bool {
        let mine = store.me.name.lowercased()
        return mine.count > 3 && mine != "you" && post.email.from.name.lowercased() == mine
            && post.email.from.email.lowercased() != store.account?.lowercased()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(assessment.section.title).font(.caption.weight(.semibold))
                    .foregroundStyle(assessment.section == .waiting ? CalmStyle.roseInk : CalmStyle.secondary)
                Text("·").font(.caption).foregroundStyle(CalmStyle.secondary)
                Text(assessment.reason).font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            if assessment.section == .notes {
                if store.otherAddresses.contains(post.email.from.email.lowercased()) {
                    Button("This isn't my address") { store.removeOtherAddress(post.email.from.email) }
                        .buttonStyle(CalmActionStyle()).lineLimit(1).fixedSize()
                }
            } else if looksLikeYou {
                Text("This name matches yours. Is it another address of yours?").font(.caption).foregroundStyle(CalmStyle.secondary)
                Button("Yes, \(post.email.from.email) is mine") { store.addOtherAddress(post.email.from.email) }
                    .buttonStyle(CalmActionStyle()).lineLimit(1).minimumScaleFactor(0.8)
            }
            if assessment.section == .waiting {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { corrections }
                    VStack(alignment: .leading, spacing: 8) { corrections }
                }
            } else if store.isMarkedNotWaiting(post) {
                Button("Put back in Waiting") { store.undoNotWaiting(post) }.buttonStyle(CalmActionStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var corrections: some View {
        Button("Not waiting on me") { store.markNotWaiting(post, wholeSender: false) }
            .buttonStyle(CalmActionStyle()).lineLimit(1).fixedSize()
        Button("Never for \(post.email.from.firstName)") { store.markNotWaiting(post, wholeSender: true) }
            .buttonStyle(CalmActionStyle()).lineLimit(1).fixedSize()
    }
}

struct HeaderLine: View {
    let key: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key).font(.caption).foregroundStyle(CalmStyle.secondary).frame(width: 36, alignment: .leading)
            Text(value).font(.caption).textSelection(.enabled)
        }
    }
}
