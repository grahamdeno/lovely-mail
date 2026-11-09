import SwiftUI

struct Person: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let email: String
    /// 0...1, picks a muted avatar color.
    let hue: Double

    /// "Dana" for "Dana Brooks". Names that start with a title or an article stay whole:
    /// "St. Andrews Reserve", "Dr. Patel", "The Rink".
    var firstName: String {
        let parts = name.split(separator: " ")
        guard let first = parts.first.map(String.init) else { return name }
        if parts.count > 1, first.hasSuffix(".") || ["the", "a", "mr", "mrs", "ms", "dr"].contains(first.lowercased()) { return name }
        return first
    }

    var initials: String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." || $0 == "_" }).prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var color: Color { Color(hue: hue, saturation: 0.32, brightness: 0.52) }

    /// Address-only guess. Live mail also carries header and label signals; see `Email.isAutomated`.
    var isAutomated: Bool { SenderSignals.looksAutomated(address: email) }
}

struct Email: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let threadId: String
    let from: Person
    let to: [String]
    var cc: [String] = []
    let subject: String
    let date: Date
    /// Plain text body. Never logged.
    let body: String
    var isUnread: Bool = true
    var isFromMe: Bool = false
    /// Bulk, notification or list mail according to Gmail's own signals (category tabs, list headers)
    /// plus the address shape. Automated mail never counts as a person waiting on you.
    var bulk: Bool = false
    /// Gmail filed it under its Promotions tab. Optional so mail cached before this field still decodes.
    var promotionalMark: Bool?
    var isPromotional: Bool { promotionalMark ?? false }
    /// The mail's own headers say it is an automatic reply. Optional so mail cached before this field still decodes.
    var autoReplyMark: Bool?
    var isMarkedAutoReply: Bool { autoReplyMark ?? false }
    /// Gmail's Authentication-Results header (SPF, DKIM, DMARC), for the sender check. Optional: older cached mail has none.
    var authResults: String?
    /// The Reply-To address when it is set, for the sender check.
    var replyTo: String?
    /// Out-of-office and other automatic replies: by header, subject or wording.
    var isAutoReply: Bool { AutoReply.isAutoReply(self) }

    init(id: String, threadId: String, from: Person, to: [String], cc: [String] = [], subject: String, date: Date,
         body: String, isUnread: Bool = true, isFromMe: Bool = false, bulk: Bool = false, promotional: Bool = false,
         autoReply: Bool = false) {
        self.id = id; self.threadId = threadId; self.from = from; self.to = to; self.cc = cc
        self.subject = subject; self.date = date; self.body = body
        self.isUnread = isUnread; self.isFromMe = isFromMe; self.bulk = bulk
        self.promotionalMark = promotional ? true : nil
        self.autoReplyMark = autoReply ? true : nil
    }

    var isAutomated: Bool { bulk || from.isAutomated }
    var recipients: [String] { to + cc }
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

enum SummaryEngine: String, Sendable, Codable {
    case appleIntelligence = "Apple Intelligence"
    case fallback = "Fallback"
}

/// What a summarizer produces for one email. Plain value type used across the app.
struct EmailSummary: Hashable, Sendable, Codable {
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

enum DataMode: String { case sample = "Sample mode", gmail = "Gmail" }

/// Signals that a sender is a system, list or company rather than a person.
enum SenderSignals {
    private static let exactLocalParts: Set<String> = [
        "no-reply", "noreply", "do-not-reply", "donotreply", "receipts", "notices", "billing", "news",
        "hello", "updates", "trips", "care", "office", "accounts", "info", "support", "notifications",
        "notification", "alerts", "alert", "newsletter", "team", "marketing", "sales", "orders", "service",
        "customerservice", "help", "mailer", "mailer-daemon", "postmaster", "digest", "community",
        "invoice", "invoices", "receipt", "ebill", "confirmation", "confirmations", "reminders", "appointments",
        "statements", "returns", "admin", "sender", "assistance", "policy", "claims",
    ]
    private static let fragments = ["noreply", "no-reply", "donotreply", "do-not-reply", "notification", "mailer", "newsletter", "unsubscribe", "bounce", "auto-", "automated"]

    static func looksAutomated(address: String) -> Bool {
        let local = address.split(separator: "@").first.map { String($0).lowercased() } ?? ""
        if exactLocalParts.contains(local) { return true }
        // Machine-made sender ids such as se-32-54555085-24931459@send.example.
        if local.range(of: #"\d{6,}"#, options: .regularExpression) != nil { return true }
        return fragments.contains { local.contains($0) }
    }

    /// Gmail labels that mean the message landed outside the Primary tab.
    static let bulkLabels: Set<String> = ["CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES", "CATEGORY_FORUMS"]

    static func isBulk(labelIds: [String], hasListHeaders: Bool, precedence: String?, address: String) -> Bool {
        if hasListHeaders { return true }
        if labelIds.contains(where: bulkLabels.contains) { return true }
        if let precedence, ["bulk", "list", "junk"].contains(precedence.lowercased()) { return true }
        return looksAutomated(address: address)
    }
}
