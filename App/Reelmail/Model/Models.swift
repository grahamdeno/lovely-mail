import SwiftUI

struct Person: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let email: String
    /// 0...1, picks a muted avatar color.
    let hue: Double

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var color: Color { Color(hue: hue, saturation: 0.32, brightness: 0.52) }

    /// Automated senders never "need a reply".
    var isAutomated: Bool {
        let local = email.split(separator: "@").first.map { String($0).lowercased() } ?? ""
        let automated = ["no-reply", "noreply", "do-not-reply", "receipts", "notices", "billing",
                         "news", "hello", "updates", "trips", "care", "office", "accounts", "info"]
        return automated.contains(local)
    }
}

struct Email: Identifiable, Hashable, Sendable {
    let id: String
    let threadId: String
    let from: Person
    let to: [String]
    let subject: String
    let date: Date
    /// Plain text body. Never logged.
    let body: String
    var isUnread: Bool = true
    var isFromMe: Bool = false
}

enum PostCategory: String, CaseIterable, Codable, Sendable {
    case people, school, work, money, travel, events, newsletter, updates

    var label: String {
        switch self {
        case .people: return "People"
        case .school: return "School"
        case .work: return "Work"
        case .money: return "Money"
        case .travel: return "Travel"
        case .events: return "Plans"
        case .newsletter: return "Reading"
        case .updates: return "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .people: return "person.2.fill"
        case .school: return "backpack.fill"
        case .work: return "briefcase.fill"
        case .money: return "creditcard.fill"
        case .travel: return "airplane"
        case .events: return "calendar"
        case .newsletter: return "newspaper.fill"
        case .updates: return "bell.fill"
        }
    }

    var defaultImageQuery: String {
        switch self {
        case .people: return "friends outdoors"
        case .school: return "school hallway"
        case .work: return "desk notebook"
        case .money: return "paper receipt"
        case .travel: return "airport window"
        case .events: return "park trail"
        case .newsletter: return "morning coffee"
        case .updates: return "mailbox"
        }
    }
}

enum SummaryEngine: String, Sendable {
    case appleIntelligence = "Apple Intelligence"
    case fallback = "Fallback"
}

/// What a summarizer produces for one email. Plain value type used across the app.
struct EmailSummary: Hashable, Sendable {
    var headline: String
    var blurb: String
    var needsReply: Bool
    var category: PostCategory
    var imageQuery: String
    var sensitive: Bool
    var dates: [String]
    var engine: SummaryEngine
}

struct Post: Identifiable, Hashable {
    var email: Email
    var summary: EmailSummary
    var id: String { email.id }
}

enum DataMode: String { case sample = "Sample mode", gmail = "Gmail (read-only)" }
