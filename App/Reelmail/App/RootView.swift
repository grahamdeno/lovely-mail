import SwiftUI

struct RootView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    private var inSession: Bool { router.path.last == .session || router.path.last == .backlog }
    /// Split pill (Nov 9) replaces the tab bar; Settings > Look and feel turns it off to get the tab bar back.
    @AppStorage(SplitPillBar.settingKey) private var splitPill = true
    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            ZStack {
                // On People the pill's field filters the People list in place; elsewhere it opens search.
                if splitPill, !router.searchText.isEmpty, router.tab != .people {
                    SearchView(pill: true)
                } else {
                    switch router.tab {
                    case .home: HomeView()
                    case .people: PeopleView()
                    case .search: splitPill ? AnyView(HomeView()) : AnyView(SearchView())
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CalmStyle.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if splitPill { SplitPillBar() } else { RollingTabBar(selection: $router.tab) }
                }
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
                    case .comingUp: ComingUpListView()
                    case .energy: EnergyView()
                    case .money: MoneyView()
                    case .kids: KidsView()
                    case .brief: BriefView()
                    case .walkthrough: WalkthroughView()
                    case .kid(let id): KidView(kidID: id)
                    case .insightSettings: InsightSettingsView()
                    case .forwardingAddresses: ForwardingAddressesView()
                    case .gmailFilters: GmailFiltersView()
                    case .gmailActivity: GmailActivityView()
                    case .screenedOut: ScreenedOutView()
                    case .settings: SettingsView()
                    case .testingTools: TestingToolsView()
                    case .aboutPrivacy: AboutPrivacyView()
                    case .session: SessionView()
                    case .backlog: SessionView(backlog: true)
                    case .engineSettings: EngineSettingsView()
                    case .engineScorecard: EngineScorecardView()
                    case .cleanup: CleanupView()
                    case .shortTermCleanup: CleanupView(kind: .shortTerm)
                    case .notes: NotesThreadView()
                    case .settingsAccount: SettingsAccountView()
                    case .settingsRules: SettingsRulesView()
                    case .settingsCategories: CategoriesView()
                    case .category(let id): CategoryDetailView(id: id)
                    case .categoryResort: CategoryResortView()
                    case .settingsBrief: SettingsBriefView()
                    case .settingsLook: SettingsLookView()
                    case .settingsAI: SettingsAIView()
                    case .settingsPrivacy: SettingsPrivacyView()
                    case .later: LaterListView()
                    case .photoEvents: PhotoEventsView()
                    case .askLovely(let q): AskLovelyView(firstQuestion: q)
                    }
                }
                .toolbarBackground(CalmStyle.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
        }
        .tint(CalmStyle.blue)
        .overlay(alignment: inSession ? .top : .bottom) {
            if inSession {
                // The session has its main button at the bottom, so its Undo sits under the header instead.
                UndoBanner(limit: 1).padding(.top, typeSize.isAccessibilitySize ? 140 : 92)
            } else {
                UndoBanner(limit: 1).padding(.bottom, typeSize.isAccessibilitySize ? 112 : 76)  // clears the taller tab bar at the largest text sizes
            }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) { if FixtureMode.isRequested { FixtureRequestsOverlay() } }
        #endif
        .sheet(item: Binding(
            get: { router.draftPostID.flatMap { id in store.posts.first { $0.id == id } } },
            set: { router.draftPostID = $0?.id }
        )) { post in DraftReplySheet(post: post) }
        .sheet(item: Binding(get: { router.nudge }, set: { router.nudge = $0 })) { request in NudgeSheet(request: request) }
        .sheet(item: Binding(get: { store.gmailFilterOffer }, set: { store.gmailFilterOffer = $0 })) { offer in
            ActionPreviewSheet(preview: offer.preview, confirmTitle: "Filter in Gmail") { confirmed in
                store.createGmailFilter(offer, confirmed: confirmed)
            }
        }
    }
}
