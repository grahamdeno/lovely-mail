import SwiftUI

@main
struct ReelmailApp: App {
    @State private var store = FeedStore()
    @State private var router = Router()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

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
            .environment(store)
            .environment(router)
            .id(appearance)
            .preferredColorScheme(appearance.colorScheme)
            .task { await store.load() }
    }
}

/// Light, dark, or follow the iPhone. Chosen in Settings; saved on this phone.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark, neon
    static let storageKey = "lovely.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Automatic"
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
    case settings
    /// Review sorting and Summary Lab, inside Settings.
    case testingTools
    /// The privacy paragraph, inside Settings.
    case aboutPrivacy
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
    /// A nudge or follow-up draft showing.
    var nudge: NudgeRequest?

    func open(_ route: Route) { path.append(route) }
}
