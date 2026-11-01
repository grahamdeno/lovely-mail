import SwiftUI

struct RootView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            ZStack {
                switch router.tab {
                case .home: HomeView()
                case .people: PeopleView()
                case .new: NewMessageView()
                case .search: SearchView()
                case .profile: MyProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0xF7F6F2))
            .safeAreaInset(edge: .top, spacing: 0) {
                if router.tab == .home && store.mode == .sample { DemoTriageReviewLink() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RollingTabBar(selection: $router.tab)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0xF7F6F2))
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case .email(let id): OpenEmailView(postID: id)
                    case .person(let p): ConnectionProfileView(person: p)
                    case .thread(let p): ThreadView(person: p)
                    case .summaryLab: SummaryLabView()
                    }
                }
                .toolbarBackground(route.isCalmTimeline ? Color(hex: 0xF7F6F2) : RM.Palette.sheet, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(route.isCalmTimeline ? .light : .dark, for: .navigationBar)
            }
        }
        .sheet(item: Binding(
            get: { router.draftPostID.flatMap { id in store.posts.first { $0.id == id } } },
            set: { router.draftPostID = $0?.id }
        )) { post in
            DraftReplySheet(post: post)
        }
    }
}

private extension Route {
    var isCalmTimeline: Bool {
        if case .thread = self { return true }
        return false
    }
}

/// Retained for source compatibility; no longer displayed above the main navigation.
struct ChipRow: View {
    @Environment(FeedStore.self) private var store

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: RM.Space.s) {
                ForEach(FeedChip.allCases) { chip in
                    let selected = store.chip == chip
                    Button { store.chip = chip } label: {
                        Text(chip.title)
                            .font(RM.Typo.caption)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .foregroundStyle(selected ? RM.Palette.ink : RM.Palette.secondary)
                            .background(selected ? Color.white : RM.Palette.surface)
                            .rmCorner(RM.Radius.button)
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, RM.Space.l)
        }
        .scrollIndicators(.hidden)
    }
}
