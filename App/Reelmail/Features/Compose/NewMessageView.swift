import SwiftUI

/// Reelmail doesn't compose or send. "New" hands off to Gmail.
struct NewMessageView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New").font(.lovely(.title, .bold)).accessibilityAddTraits(.isHeader)
            Text("Write it in Gmail").font(.lovely(.headline))
            Text("Lovely reads your mail and drafts replies, but it never sends. New emails open in Gmail so you stay in control.")
                .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
            Button {
                if let app = GmailCompose.appURL(to: "", subject: "", body: "") {
                    openURL(app) { ok in
                        if !ok, let web = GmailCompose.webURL(to: "", subject: "", body: "") { openURL(web) }
                    }
                }
            } label: {
                Label("Open Gmail", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
            }
            .buttonStyle(CalmActionStyle(prominent: true))
            Spacer()
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
    }
}
