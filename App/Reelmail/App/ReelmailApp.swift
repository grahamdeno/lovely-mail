import SwiftUI

@main
struct ReelmailApp: App {
    @State private var store = FeedStore()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(.light)
                .task { await store.load() }
        }
    }
}

enum Route: Hashable {
    case email(String)
    case thread(Person)
    case summaryLab
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
