import SwiftUI
import UserNotifications

@main
struct ReelmailApp: App {
    @State private var store: FeedStore
    @State private var router = Router()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @Environment(\.scenePhase) private var scenePhase
    /// The opening animation, on a cold start only (this state is created once per launch).
    @State private var showIntro = LaunchAnimation.isOn && !UIAccessibility.isReduceMotionEnabled

    init() {
        let store: FeedStore
        #if DEBUG
        // UI audit only: fictional mail, a fake Gmail and no network. Never present in release builds.
        if let fixture = FixtureMode.makeStoreIfRequested() { store = fixture } else { store = Self.makeStandardStore() }
        #else
        store = Self.makeStandardStore()
        #endif
        _store = State(initialValue: store)
        MorningBriefScheduler.register(store: store)
        UNUserNotificationCenter.current().delegate = NotificationOpener.shared
    }

    private static func makeStandardStore() -> FeedStore {
        // Restore typed settings from iCloud before anything reads them.
        SettingsSync.standard.start()
        let store = FeedStore()
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default, queue: .main) { _ in
            if SettingsSync.standard.pull() { MainActor.assumeIsolated { store.bumpForScreening() } }
        }
        return store
    }

    var body: some Scene {
        WindowGroup {
            themedRoot()
        }
    }

    /// Neon is a palette, not an iOS appearance: the flag is set before the views are built,
    /// and the whole tree is rebuilt (by id) when the choice changes.
    private func themedRoot() -> some View {
        ThemeState.neon = appearance == .neon
        return RootView()
            .overlay {
                if !store.hasStarted { LaunchSplash().transition(.opacity) }
            }
            .overlay { if showIntro { LaunchAnimation { showIntro = false } } }
            .animation(.easeOut(duration: 0.3), value: store.hasStarted)
            .environment(store)
            .environment(router)
            .id(appearance)
            .preferredColorScheme(appearance.colorScheme)
            .task { await store.load(); await store.replayAutomaticChanges() }
            // The brief is rebuilt from the mail loaded right now after each refresh and when the app leaves the screen.
            .onChange(of: store.lastFetched) { _, _ in Task { await MorningBriefScheduler.reschedule(store: store) } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    InteractionLog().recordOpen()
                    store.saveIfWaiting()
                    Task { await store.replayAutomaticChanges() }
                    if let route = NotificationOpener.pending { NotificationOpener.pending = nil; router.open(route) }
                }
                // The app switcher or Control Center: send held changes now too, in case Lovely is closed from there.
                if phase == .inactive { store.undo.flushAll() }
                if phase == .background {
                    // Send held Gmail changes now; iOS cuts the network soon after Lovely leaves the screen.
                    store.undo.flushAll()
                    Task { await MorningBriefScheduler.reschedule(store: store) }
                }
            }
    }
}

/// Light, dark, or follow the iPhone. Chosen in Settings; saved on this phone.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark, neon
    static let storageKey = "lovely.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        case .neon: return "Neon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .neon: return .dark
        }
    }
}

enum Route: Hashable {
    case email(String)
    case thread(Person)
    case summaryLab
    case sortingReview
    /// "earlier", or "org:<group id>" from the Home digest.
    case mailList(String)
    /// An organization's page, by group key.
    case organization(String)
    case organizationList
    /// Everything you promised, and everything you asked that has no answer yet.
    case promises
    case waitingOnThem
    case comingUp
    /// Energy and water read from mail.
    case energy
    /// Bills, accounts and renewals read from mail.
    case money
    /// Children and the mail about them.
    case kids
    /// The morning brief as a full page.
    case brief
    /// Cards, one piece of mail at a time.
    case walkthrough
    case kid(String)
    /// Households and children, inside Settings.
    case insightSettings
    case forwardingAddresses
    case gmailFilters
    case gmailActivity
    case screenedOut
    case settings
    /// Review sorting and Summary Lab, inside Settings.
    case testingTools
    /// The privacy paragraph, inside Settings.
    case aboutPrivacy
    /// The inbox session (Sprint 7): unread mail, one decision at a time.
    case session
    /// The same session over read mail still in the inbox, a page at a time.
    case backlog
    /// Apple only, Claude or Grok for the inbox session, keys and compare mode.
    case engineSettings
    /// Every enabled engine against the fictional scorecard sentences.
    case engineScorecard
    /// Old login codes and device checks, listed, then moved to Trash with one tap.
    case cleanup
    case shortTermCleanup
    case notes
    case glance
    // Settings pages (Nov 9 redesign) and the Later list (moved from Settings to a Home chip).
    case settingsAccount, settingsRules, settingsBrief, settingsLook, settingsAI, settingsPrivacy
    case later
    /// Events read from a photo of a calendar, added to the Work calendar.
    case photoEvents
    /// Ask Lovely about your mail, from Home.
    case askLovely(String)
}

enum AppTab: Int, CaseIterable, Identifiable {
    // Ordered for a right thumb: the most used tabs sit on the right.
    case search, people, home

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .search: return "Search"
        case .people: return "People"
        case .home: return "Home"
        }
    }

    var symbol: String {
        switch self {
        case .search: return "magnifyingglass"
        case .people: return "person.2"
        case .home: return "house"
        }
    }
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []
    var tab: AppTab = .home
    /// Post id whose draft-reply sheet is showing.
    var draftPostID: String?
    /// Open the draft sheet with Reply all selected.
    var draftReplyAll = false
    /// A nudge or follow-up draft showing.
    var nudge: NudgeRequest?

    func open(_ route: Route) { path.append(route) }
}
