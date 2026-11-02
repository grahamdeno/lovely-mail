import Foundation

/// Where a message sits in the feed. Order is the feed's priority, top to bottom.
enum FeedSection: Int, CaseIterable, Identifiable, Comparable {
    /// A person asked something and no reply from you is newer than the ask.
    case waiting
    /// Mail from people, with nothing open.
    case people
    /// Automated mail that carries a date: forms, appointments, travel, bills.
    case dated
    /// Receipts, shipping, account notices.
    case updates
    /// Newsletters and anything you routed to Reading.
    case reading

    var id: Int { rawValue }
    static func < (a: FeedSection, b: FeedSection) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .waiting: return "Waiting on you"
        case .people: return "People"
        case .dated: return "Coming up"
        case .updates: return "Updates"
        case .reading: return "Reading"
        }
    }
}

/// Home filter pills. `all` shows every section in priority order.
enum FeedFilter: String, CaseIterable, Identifiable {
    case all, waiting, people, updates, reading
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .waiting: return "Waiting on you"
        case .people: return "People"
        case .updates: return "Updates"
        case .reading: return "Reading"
        }
    }
    func includes(_ section: FeedSection) -> Bool {
        switch self {
        case .all: return true
        case .waiting: return section == .waiting
        case .people: return section == .people || section == .waiting
        case .updates: return section == .updates || section == .dated
        case .reading: return section == .reading
        }
    }
}

/// Pure sorting rules. Views never decide these.
enum FeedTriage {
    /// The newest message you sent in each thread, by thread id.
    static func latestReplies(in sent: [Email]) -> [String: Date] {
        var out: [String: Date] = [:]
        for email in sent where email.isFromMe {
            if let existing = out[email.threadId], existing >= email.date { continue }
            out[email.threadId] = email.date
        }
        return out
    }

    /// True while a person's question has no reply from you dated after it.
    /// A reply that only promises to follow up still counts as a reply here; the message then moves to
    /// People rather than disappearing, so it stays visible.
    static func isWaiting(_ post: Post, replies: [String: Date]) -> Bool {
        guard post.summary.needsReply, !post.email.isAutomated, !post.email.isFromMe else { return false }
        if let reply = replies[post.email.threadId], reply > post.email.date { return false }
        return true
    }

    static func section(for post: Post, route: LocalMailDestination, replies: [String: Date]) -> FeedSection {
        if route == .reading { return .reading }
        if post.summary.category == .newsletter { return .reading }
        if isWaiting(post, replies: replies) { return .waiting }
        if !post.email.isAutomated { return .people }
        if !post.summary.dates.isEmpty || [.school, .travel, .events].contains(post.summary.category) { return .dated }
        return .updates
    }
}

/// Reply detection that ignores the parts of an email no one is asking you about.
enum ReplySignals {
    private static let asks = ["let me know", "can you", "could you", "would you", "please confirm", "rsvp",
                               "are you free", "please reply", "your thoughts", "what do you think", "any word",
                               "did you", "do you", "will you", "wondering if", "thoughts?"]

    /// The author's own words: no quoted earlier mail, no signature block, no link-heavy footer lines.
    static func authoredText(_ body: String) -> String {
        var kept: [String] = []
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "--" || line == "-- " || line.hasPrefix("—") && line.count < 4 { break }
            if line.range(of: #"^On .+ wrote:$"#, options: .regularExpression) != nil { break }
            if line.hasPrefix("-----Original Message-----") || line.hasPrefix("From: ") && kept.count > 2 { break }
            if line.hasPrefix(">") { continue }
            let lower = line.lowercased()
            if lower.contains("unsubscribe") || lower.contains("http://") || lower.contains("https://") { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    static func needsReply(body: String, automated: Bool, category: PostCategory) -> Bool {
        guard !automated, category != .newsletter else { return false }
        let text = authoredText(body)
        let lower = text.lowercased()
        if asks.contains(where: { lower.contains($0) }) { return true }
        // A question mark counts only when it ends a sentence the author wrote.
        return text.range(of: #"[A-Za-z][^.!?\n]{2,}\?(\s|$)"#, options: .regularExpression) != nil
    }
}
