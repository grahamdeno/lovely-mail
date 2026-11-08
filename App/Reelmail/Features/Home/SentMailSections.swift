import SwiftUI
import UIKit

/// A draft to a person you wrote to: a nudge on something unanswered, or a follow-up on a promise.
/// Lovely never sends; Copy or Open in Gmail.
struct NudgeRequest: Identifiable, Equatable {
    let id: String
    let email: Email       // the mail you sent
    let text: String
}

/// "To Dana · 3 days ago" for mail you sent.
func sentLine(_ email: Email, now: Date, store: FeedStore) -> String {
    let people = PromiseRules.recipientLine(email) { address in
        let person = GmailMessageParser.person(fromHeader: email.to.first { EmailPresentation.address(in: $0) == address } ?? address)
        return person.name.contains("@") ? nil : person.firstName
    }
    return "To \(people) · \(HomeDigest.age(of: email.date, now: now)) ago"
}

private func recipientFirstName(_ email: Email) -> String {
    GmailMessageParser.person(fromHeader: email.to.first ?? "").firstName
}

/// One thing you said you would do.
struct PromiseCard: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let item: PromiseRules.Item
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\u{201C}\(item.text)\u{201D}").font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(sentLine(item.email, now: Date(), store: store)).font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            HStack(spacing: 8) {
                Button { store.closePromise(item) } label: { Label("Done", systemImage: "checkmark") }
                    .buttonStyle(CalmActionStyle(prominent: true)).lineLimit(1)
                    .accessibilityHint("Removes it from You said you would")
                Button {
                    router.nudge = NudgeRequest(id: item.id, email: item.email, text: "Hi \(recipientFirstName(item.email)),\n\n")
                } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                    .buttonStyle(CalmActionStyle()).lineLimit(1)
                Spacer(minLength: 0)
                Menu {
                    Button { store.closePromise(item, notAPromise: true) } label: { Label("Not a promise", systemImage: "xmark.circle") }
                    Button { openInGmail(item.email) } label: { Label("Open in Gmail", systemImage: "arrow.up.forward.app") }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(CalmStyle.blue).frame(width: 44, height: 40)
                }
                .accessibilityLabel("More actions")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func openInGmail(_ email: Email) {
        let to = EmailPresentation.address(in: email.to.first ?? "")
        let subject = GmailCompose.replySubject(email.subject)
        guard let app = GmailCompose.appURL(to: to, subject: subject, body: "") else { return }
        openURL(app) { ok in if !ok, let web = GmailCompose.webURL(to: to, subject: subject, body: "") { openURL(web) } }
    }
}

/// "Waiting on them · 3 ›": one quiet row that opens the list.
struct WaitingOnThemRow: View {
    @Environment(Router.self) private var router
    let count: Int
    var body: some View {
        Button { router.open(.waitingOnThem) } label: {
            HStack(spacing: 10) {
                Text("Waiting on them · \(count)").font(.subheadline.weight(.medium)).foregroundStyle(CalmStyle.ink)
                Spacer()
                Text("Asks with no answer yet").font(.caption).foregroundStyle(CalmStyle.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// On a person's page: your open ask to them, with Nudge and Got it. Same actions as the list.
struct ThreadAskRow: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let item: WaitingOnThem.Item
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You asked " + HomeDigest.age(of: item.email.date, now: Date()) + " ago, no answer yet").font(.subheadline.weight(.medium))
            Text("\u{201C}\(item.ask)\u{201D}").font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(2)
            HStack(spacing: 8) {
                Button {
                    let first = GmailMessageParser.person(fromHeader: item.email.to.first ?? "").firstName
                    router.nudge = NudgeRequest(id: item.id, email: item.email,
                                                text: WaitingOnThem.nudgeText(recipientFirstName: first, myFirstName: store.me.firstName))
                } label: { Label("Nudge", systemImage: "hand.tap") }
                    .buttonStyle(CalmActionStyle(prominent: true)).lineLimit(1)
                Button { store.dismissWaiting(item); onDismiss() } label: { Label("Got it", systemImage: "checkmark") }
                    .buttonStyle(CalmActionStyle()).lineLimit(1)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Everything you asked that nobody has answered, with Nudge and Got it.
struct WaitingOnThemListView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var toast: String?

    var body: some View {
        let items = store.waitingOnThem
        List {
            if items.isEmpty {
                Text("Nothing you asked is waiting on an answer.").font(.subheadline).foregroundStyle(CalmStyle.secondary)
                    .listRowBackground(CalmStyle.background).listRowSeparator(.hidden)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(GmailMessageParser.person(fromHeader: item.email.to.first ?? "").name)
                            .font(.headline).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(HomeDigest.age(of: item.email.date, now: Date())).font(.caption).foregroundStyle(CalmStyle.secondary)
                    }
                    Text("\u{201C}\(item.ask)\u{201D}").font(.subheadline).foregroundStyle(CalmStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            let first = GmailMessageParser.person(fromHeader: item.email.to.first ?? "").firstName
                            router.nudge = NudgeRequest(id: item.id, email: item.email,
                                                        text: WaitingOnThem.nudgeText(recipientFirstName: first, myFirstName: store.me.firstName))
                        } label: { Label("Nudge", systemImage: "hand.tap") }
                            .buttonStyle(CalmActionStyle(prominent: true)).lineLimit(1)
                        Button { store.dismissWaiting(item); toast = item.id } label: { Label("Got it", systemImage: "checkmark") }
                            .buttonStyle(CalmActionStyle()).lineLimit(1)
                    }
                }
                .padding(.vertical, 10)
                .listRowBackground(CalmStyle.background).listRowSeparatorTint(CalmStyle.divider)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Waiting on them").navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let id = toast {
                UndoBar(text: "Removed from Waiting on them") { store.restoreWaiting(id); toast = nil }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                    .task(id: id) { try? await Task.sleep(for: .seconds(6)); if toast == id { toast = nil } }
            }
        }
    }
}

/// Every open promise.
struct PromisesListView: View {
    @Environment(FeedStore.self) private var store
    var body: some View {
        let items = store.promises
        ScrollView {
            LazyVStack(spacing: 10) {
                if items.isEmpty {
                    Text("Nothing you promised is open.").font(.subheadline).foregroundStyle(CalmStyle.secondary).padding(.top, 24)
                }
                ForEach(items) { PromiseCard(item: $0) }
            }.padding(.horizontal, 20).padding(.top, 8)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("You said you would").navigationBarTitleDisplayMode(.inline)
    }
}

/// A draft the owner edits and sends from Gmail. Lovely never sends.
struct NudgeSheet: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let request: NudgeRequest
    @State private var draft: String
    @State private var copied = false

    init(request: NudgeRequest) {
        self.request = request
        _draft = State(initialValue: request.text)
    }

    private var to: String { EmailPresentation.address(in: request.email.to.first ?? "") }
    private var subject: String { GmailCompose.replySubject(request.email.subject) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Draft").font(.title3.weight(.semibold))
            Text("To \(to) · \(subject)").font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(1)
            TextEditor(text: $draft).scrollContentBackground(.hidden).font(.body).padding(8)
                .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 8) {
                Button { UIPasteboard.general.string = draft; copied = true } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(CalmActionStyle())
                Spacer()
                Button { open() } label: { Label("Open in Gmail", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(CalmActionStyle(prominent: true))
            }
            Text("This one opens in Gmail for you to send.").font(.caption).foregroundStyle(CalmStyle.secondary)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .presentationDetents([.medium, .large]).presentationCornerRadius(24)
    }

    private func open() {
        guard let app = GmailCompose.appURL(to: to, subject: subject, body: draft) else { return }
        openURL(app) { ok in if !ok, let web = GmailCompose.webURL(to: to, subject: subject, body: draft) { openURL(web) } }
    }
}
