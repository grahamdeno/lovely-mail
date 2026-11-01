import SwiftUI

/// Vertical paging reel of post cards.
struct ReelView: View {
    let posts: [Post]

    var body: some View {
        if posts.isEmpty {
            VStack(spacing: RM.Space.s) {
                Image(systemName: "checkmark.circle").font(.system(size: 32))
                Text("All caught up here").font(RM.Typo.title)
            }
            .foregroundStyle(RM.Palette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        PostCard(post: post)
                            .padding(.horizontal, RM.Radius.sheetPadding)
                            .padding(.bottom, RM.Space.s)
                            .containerRelativeFrame(.vertical)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
        }
    }
}

/// One post: photo art, white fade-up scrim, ink headline and blurb, and the action row.
struct PostCard: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let post: Post

    var body: some View {
        let art = store.photos.art(for: post.summary, seed: post.id)
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [art.top, art.bottom], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) {
                    Image(systemName: art.symbol)
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 56)
                }

            // White fade up from the bottom, so ink text reads on any photo.
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.30),
                                   .init(color: .white.opacity(0.92), location: 0.58),
                                   .init(color: .white, location: 1)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: RM.Space.s) {
                HStack(spacing: RM.Space.s) {
                    AvatarView(person: post.email.from, size: 28)
                    Text(post.email.from.name).font(RM.Typo.caption).foregroundStyle(RM.Palette.ink)
                    Text("· " + post.email.date.formatted(.relative(presentation: .named)))
                        .font(RM.Typo.caption).foregroundStyle(RM.Palette.ink.opacity(0.55))
                    Spacer()
                    if post.summary.needsReply { NeedsReplyTag(onLight: true) }
                }
                Text(post.summary.headline)
                    .font(RM.Typo.headline)
                    .foregroundStyle(RM.Palette.ink)
                    .lineLimit(2)
                Text(post.summary.sensitive ? "Contains private details. Open to view." : post.summary.blurb)
                    .font(RM.Typo.callout)
                    .foregroundStyle(RM.Palette.ink.opacity(0.75))
                    .lineLimit(3)
                PostActionRow(post: post, onLight: true)
                    .padding(.top, RM.Space.xs)
            }
            .padding(RM.Radius.cardPadding + 4)
        }
        .rmCorner(RM.Radius.card)
        .contentShape(Rectangle())
        .onTapGesture {
            store.markRead(post)
            router.open(.email(post.id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(post.email.from.name). \(post.summary.headline)")
    }
}

/// Snooze, Archive, and Draft reply (primary, on the right under the thumb).
struct PostActionRow: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let post: Post
    var onLight: Bool
    var showBack: Bool = false

    var body: some View {
        HStack(spacing: RM.Space.s) {
            if showBack {
                Button { router.path.removeLast() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(RMButtonStyle(kind: ghost))
                    .accessibilityLabel("Back")
            }
            Button {
                withAnimation { store.snooze(post) }
                if showBack { router.path.removeLast() }
            } label: { Label("Snooze", systemImage: "clock").labelStyle(ghostLabel) }
                .buttonStyle(RMButtonStyle(kind: ghost))
            Button {
                withAnimation { store.archive(post) }
                if showBack { router.path.removeLast() }
            } label: { Label("Archive", systemImage: "archivebox").labelStyle(ghostLabel) }
                .buttonStyle(RMButtonStyle(kind: ghost))
            Spacer(minLength: 0)
            Button { router.draftPostID = post.id } label: {
                Label("Draft reply", systemImage: "arrowshape.turn.up.left.fill").labelStyle(CompactLabelStyle())
            }
            .buttonStyle(RMButtonStyle(kind: onLight ? .primary : .ghostLight))
            .background(onLight ? Color.clear : Color.white)
            .rmCorner(RM.Radius.button)
        }
    }

    private var ghostLabel: AdaptiveLabelStyle { AdaptiveLabelStyle(iconOnly: showBack) }

    private var ghost: RMButtonStyleKind { onLight ? .ghostLight : .ghostDark }
}

/// Icon + short title, tight spacing.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

/// Icon-only where space is tight (the open-email bar), icon + title otherwise.
struct AdaptiveLabelStyle: LabelStyle {
    var iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            if !iconOnly { configuration.title }
        }
    }
}
