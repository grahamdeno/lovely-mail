import SwiftUI

@main
struct ReelmailApp: App {
    @State private var store = FeedStore()
    @State private var router = Router()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(appearance.colorScheme)
                .task { await store.load() }
        }
    }
}

/// Light, dark, or follow the iPhone. Chosen in Profile; saved on this phone.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "lovely.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
}

enum AppTab: Int, CaseIterable, Identifiable {
    // Ordered for a right thumb: the most used tabs sit on the right.
    case profile, search, new, people, home

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .profile: return "Profile"
        case .search: return "Search"
        case .new: return "New"
        case .people: return "People"
        case .home: return "Home"
        }
    }

    var symbol: String {
        switch self {
        case .profile: return "person.crop.square"
        case .search: return "magnifyingglass"
        case .new: return "square.and.pencil"
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

    func open(_ route: Route) { path.append(route) }
}
