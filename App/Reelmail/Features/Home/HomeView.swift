import SwiftUI

struct HomeView: View {
    @Environment(FeedStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HomeHeader()
            VStack(spacing: 0) {
                LensCarousel()
                    .padding(.top, RM.Space.l)
                ReelView(posts: store.visiblePosts)
                    .padding(.top, RM.Space.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RM.Palette.sheet)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: RM.Radius.sheet,
                                              topTrailingRadius: RM.Radius.sheet,
                                              style: .continuous))
        }
        .background(RM.Palette.header)
    }
}

/// Matte off-white header: my avatar, "Inbox · N new", bell, search, then story avatars.
struct HomeHeader: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: RM.Space.m) {
            HStack(spacing: RM.Space.s) {
                Button { router.tab = .profile } label: { AvatarView(person: store.me, size: 40) }
                    .accessibilityLabel("Your profile")
                Text("Inbox · \(store.unreadCount) new")
                    .font(RM.Typo.caption)
                    .foregroundStyle(RM.Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.white)
                    .rmCorner(RM.Radius.button)
                Spacer()
                HeaderIconButton(systemName: "bell", label: "Notifications") {
                    store.lens = .needsYou
                }
                HeaderIconButton(systemName: "magnifyingglass", label: "Search") {
                    router.tab = .search
                }
            }
            .padding(.horizontal, RM.Space.l)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: RM.Space.m) {
                    ForEach(store.people) { person in
                        Button { router.open(.person(person)) } label: {
                            VStack(spacing: 6) {
                                AvatarView(person: person, size: 56, needsReply: store.needsReply(person))
                                Text(person.firstName)
                                    .font(RM.Typo.micro)
                                    .foregroundStyle(RM.Palette.ink)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                    }
                }
                .padding(.horizontal, RM.Space.l)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, RM.Space.s)
        .padding(.bottom, RM.Space.l)
        .background(RM.Palette.header)
    }
}
