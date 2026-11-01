import SwiftUI

/// Reelmail doesn't compose or send. "New" hands off to Gmail.
struct NewMessageView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScreenScaffold(title: "New") {
            VStack(alignment: .leading, spacing: RM.Space.l) {
                Text("Write it in Gmail")
                    .font(RM.Typo.headline).foregroundStyle(.white)
                Text("Reelmail reads your mail and drafts replies, but it never sends. New emails open in Gmail so you stay in control.")
                    .font(RM.Typo.callout).foregroundStyle(RM.Palette.secondary)
                Button {
                    if let app = GmailCompose.appURL(to: "", subject: "", body: "") {
                        openURL(app) { ok in
                            if !ok, let web = GmailCompose.webURL(to: "", subject: "", body: "") { openURL(web) }
                        }
                    }
                } label: {
                    Label("Open Gmail", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                }
                .buttonStyle(RMButtonStyle(kind: .ghostLight))
                .background(Color.white)
                .rmCorner(RM.Radius.button)
            }
            .padding(RM.Space.l)
        }
    }
}
