import SwiftUI

/// My profile: data source, Gmail connection, privacy, and the Summary Lab.
struct MyProfileView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScreenScaffold(title: "Profile") {
            ScrollView {
                VStack(alignment: .leading, spacing: RM.Space.m) {
                    HStack(spacing: RM.Space.m) {
                        Image("AppIconImage")
                            .resizable()
                            .frame(width: 56, height: 56)
                            .rmCorner(RM.Radius.avatar(size: 56))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("reelmail").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                            Text("Email, reeled.").font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
                        }
                    }
                    .padding(.bottom, RM.Space.s)

                    InfoCard(title: "Mail source", value: store.mode.rawValue,
                             detail: store.gmailConfigured
                                ? "Read-only access. Reelmail can't send, delete or change your mail."
                                : "Gmail isn't configured in this build, so you're seeing sample emails.")

                    if store.gmailConfigured {
                        Button {
                            Task {
                                if store.mode == .gmail { await store.disconnectGmail() } else { await store.connectGmail() }
                            }
                        } label: {
                            Label(store.mode == .gmail ? "Disconnect Gmail" : "Connect Gmail (read-only)",
                                  systemImage: "envelope.badge.shield.half.filled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RMButtonStyle(kind: .ghostLight))
                        .background(Color.white)
                        .rmCorner(RM.Radius.button)
                    }

                    let status = ModelStatus.current
                    InfoCard(title: "On-device AI", value: status.title, detail: status.detail)

                    Button { router.open(.summaryLab) } label: {
                        HStack {
                            Label("Summary Lab", systemImage: "flask")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RMButtonStyle(kind: .ghostDark))

                    Button { store.restoreAll() } label: {
                        Label("Bring back archived and snoozed", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RMButtonStyle(kind: .ghostDark))

                    Text("Privacy: Reelmail reads Gmail with read-only permission, summarizes on this iPhone with Apple Intelligence, and never sends email.")
                        .font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
                        .padding(.top, RM.Space.s)

                    if let error = store.errorMessage {
                        Text(error).font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
                    }
                }
                .padding(RM.Space.l)
            }
        }
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
            Text(value).font(RM.Typo.title).foregroundStyle(.white)
            Text(detail).font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
        }
        .padding(RM.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RM.Palette.surface)
        .rmCorner(RM.Radius.card)
    }
}
