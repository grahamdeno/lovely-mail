import SwiftUI

/// Full email with the on-device summary on top and a bottom action bar in thumb reach.
struct OpenEmailView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let postID: String

    var body: some View {
        if let post = store.posts.first(where: { $0.id == postID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: RM.Space.l) {
                    Button { router.open(.person(post.email.from)) } label: {
                        HStack(spacing: RM.Space.m) {
                            AvatarView(person: post.email.from, size: 44, needsReply: post.summary.needsReply)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.email.from.name).font(RM.Typo.title).foregroundStyle(.white)
                                Text(post.email.from.email).font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
                            }
                            Spacer()
                            Text(post.email.date.formatted(date: .abbreviated, time: .shortened))
                                .font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Text(post.email.subject).font(RM.Typo.headline).foregroundStyle(.white)

                    SummaryBox(summary: post.summary)

                    Text(post.email.body)
                        .font(RM.Typo.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                }
                .padding(RM.Space.l)
            }
            .background(RM.Palette.sheet)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PostActionRow(post: post, onLight: false, showBack: true)
                    .padding(RM.Radius.cardPadding)
                    .background(RM.Palette.surface)
                    .rmCorner(RM.Radius.card)
                    .padding(.horizontal, RM.Space.l)
                    .padding(.bottom, RM.Space.s)
            }
        } else {
            ContentUnavailableView("Email not found", systemImage: "envelope")
                .background(RM.Palette.sheet)
        }
    }
}

struct SummaryBox: View {
    let summary: EmailSummary

    var body: some View {
        VStack(alignment: .leading, spacing: RM.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: summary.engine == .appleIntelligence ? "sparkles" : "text.alignleft")
                Text(summary.engine == .appleIntelligence ? "Summary · on device" : "Quick summary")
                Spacer()
                if summary.needsReply { NeedsReplyTag(onLight: false) }
            }
            .font(RM.Typo.micro)
            .foregroundStyle(RM.Palette.secondary)
            Text(summary.headline).font(RM.Typo.title).foregroundStyle(.white)
            Text(summary.blurb).font(RM.Typo.callout).foregroundStyle(.white.opacity(0.8))
            if !summary.dates.isEmpty {
                Text(summary.dates.joined(separator: " · "))
                    .font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
            }
        }
        .padding(RM.Space.m)
        .background(RM.Palette.surface)
        .rmCorner(RM.Radius.card)
    }
}
