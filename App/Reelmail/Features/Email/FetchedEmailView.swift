import SwiftUI

/// An email that is not among the loaded inbox mail (older bills and account mail on Money, for example).
/// Read once from Gmail (read-only) and shown plainly, with a way to open Gmail. Nothing is changed.
struct FetchedEmailView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.openURL) private var openURL
    let messageID: String
    @State private var email: Email?
    @State private var failed = false

    var body: some View {
        Group {
            if let email {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(email.from.name.isEmpty ? email.from.email : email.from.name).font(.subheadline).foregroundStyle(CalmStyle.secondary)
                        Text(email.subject.isEmpty ? "(no subject)" : email.subject).font(.title3.weight(.bold))
                        Text(email.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(CalmStyle.secondary)
                        Divider()
                        Text(email.body).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button { openInGmail() } label: { Label("Open in Gmail", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity) }
                            .buttonStyle(CalmActionStyle()).padding(.top, 8)
                    }
                    .padding(20)
                }
            } else if failed || store.mode != .gmail {
                ContentUnavailableView("Email not found", systemImage: "envelope",
                                       description: Text("It may have been deleted, or Gmail could not be reached. Try again with a signal."))
            } else {
                ProgressView("Opening from Gmail").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: messageID) {
            guard store.mode == .gmail, email == nil else { return }
            do { email = try await store.gmail.getMessage(id: messageID, account: store.account) } catch { failed = true }
        }
    }

    private func openInGmail() {
        if let app = URL(string: "googlegmail:///"), let web = URL(string: "https://mail.google.com/mail/u/0/#all/" + messageID) {
            openURL(web) { ok in if !ok { openURL(app) } }
        }
    }
}
