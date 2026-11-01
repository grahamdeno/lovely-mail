import Foundation

/// The lens carousel: different ways to look at the same mail.
enum Lens: String, CaseIterable, Identifiable {
    case brief, needsYou, comingUp, people, money, catchUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief: return "Today's brief"
        case .needsYou: return "Needs you"
        case .comingUp: return "Coming up"
        case .people: return "People"
        case .money: return "Money"
        case .catchUp: return "Catch up later"
        }
    }

    var symbol: String {
        switch self {
        case .brief: return "sun.max"
        case .needsYou: return "arrowshape.turn.up.left"
        case .comingUp: return "calendar"
        case .people: return "person.2"
        case .money: return "creditcard"
        case .catchUp: return "bookmark"
        }
    }

    func includes(_ post: Post) -> Bool {
        let s = post.summary
        switch self {
        case .brief: return s.needsReply || !s.dates.isEmpty || post.email.isUnread
        case .needsYou: return s.needsReply
        case .comingUp: return !s.dates.isEmpty
        case .people: return !post.email.from.isAutomated
        case .money: return s.category == .money
        case .catchUp: return s.category == .newsletter
        }
    }
}

/// Category chips above the tab bar.
enum FeedChip: String, CaseIterable, Identifiable {
    case forYou, unread, people, work, plans, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: return "For you"
        case .unread: return "Unread"
        case .people: return "People"
        case .work: return "Work"
        case .plans: return "Plans"
        case .updates: return "Updates"
        }
    }

    func includes(_ post: Post) -> Bool {
        switch self {
        case .forYou: return true
        case .unread: return post.email.isUnread
        case .people: return post.summary.category == .people
        case .work: return post.summary.category == .work
        case .plans: return [.events, .travel, .school].contains(post.summary.category)
        case .updates: return [.updates, .money, .newsletter].contains(post.summary.category)
        }
    }
}
