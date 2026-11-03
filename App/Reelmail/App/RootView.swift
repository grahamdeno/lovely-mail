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
                case .search: SearchView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CalmStyle.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RollingTabBar(selection: $router.tab)
                    .padding(.horizontal, 16).padding(.vertical, 8).background(CalmStyle.background)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case .email(let id): OpenEmailView(postID: id)
                    case .thread(let p): ThreadView(person: p)
                    case .summaryLab: SummaryLabView()
                    case .sortingReview: SortingReviewView()
                    case .mailList(let key): DigestListView(key: key)
                    case .organization(let key): OrganizationView(key: key)
                    case .organizationList: OrganizationListView()
                    case .promises: PromisesListView()
                    case .waitingOnThem: WaitingOnThemListView()
                    case .settings: SettingsView()
                    case .testingTools: TestingToolsView()
                    case .aboutPrivacy: AboutPrivacyView()
                    }
                }
                .toolbarBackground(CalmStyle.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
        }
        .tint(CalmStyle.blue)
        .sheet(item: Binding(
            get: { router.draftPostID.flatMap { id in store.posts.first { $0.id == id } } },
            set: { router.draftPostID = $0?.id }
        )) { post in DraftReplySheet(post: post) }
        .sheet(item: Binding(get: { router.nudge }, set: { router.nudge = $0 })) { request in NudgeSheet(request: request) }
    }
}
