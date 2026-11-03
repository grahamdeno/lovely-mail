import Foundation

/// The top of a person's page: a short, blunt summary of your history with them, three numbers,
/// what is open both ways, and recent topics. Built on the phone from loaded mail only. Pure, so it is tested.
struct PersonProfile: Equatable {
    struct OpenItem: Equatable, Identifiable {
        let id: String
        let text: String
        let detail: String
        /// True when they asked you; false when you said you would do something.
        let theirs: Bool
    }

    let shortVersion: String
    let total: Int
    let fromYou: Int
    let since: Date?
    /// Median time from their message to your next reply in the same thread.
    let usualReply: TimeInterval?
    let open: [OpenItem]
    let topics: [String]

    static let promiseWindow: TimeInterval = 30 * 86_400

    /// `theirs`: their mail to you. `mine`: your mail to them. `waitingAsk`: the ask for each of their messages
    /// that is in Waiting on you, by message id.
    static func make(person: Person, theirs: [Email], mine: [Email], waitingAsk: [String: String],
                     isOrganization: Bool, now: Date) -> PersonProfile {
        let all = (theirs + mine).sorted { $0.date < $1.date }
        let since = all.first?.date

        // Reply time: their message → your next message in the same thread.
        var gaps: [TimeInterval] = []
        for email in theirs {
            if let reply = mine.filter({ $0.threadId == email.threadId && $0.date > email.date }).min(by: { $0.date < $1.date }) {
                gaps.append(reply.date.timeIntervalSince(email.date))
            }
        }
        let usual = median(gaps)

        var open: [OpenItem] = []
        for email in theirs.sorted(by: { $0.date > $1.date }) {
            if let ask = waitingAsk[email.id] {
                open.append(OpenItem(id: "ask-" + email.id, text: ask,
                                     detail: "\(person.firstName) asked " + FeedTriage.relativeAge(of: email.date, now: now), theirs: true))
            }
        }
        for email in mine.sorted(by: { $0.date > $1.date }) where now.timeIntervalSince(email.date) <= promiseWindow {
            guard let promise = promiseSentence(in: email.body) else { continue }
            // A later message from them in the same thread usually means it was handled.
            if theirs.contains(where: { $0.threadId == email.threadId && $0.date > email.date }) { continue }
            open.append(OpenItem(id: "promise-" + email.id, text: promise,
                                 detail: "You said " + FeedTriage.relativeAge(of: email.date, now: now), theirs: false))
            if open.filter({ !$0.theirs }).count >= 2 { break }
        }

        var topics: [String] = []
        for email in all.reversed() {
            let topic = FallbackSummarizer.cleanSubject(email.subject, fallbackBody: "")
            guard !topic.isEmpty, topic.count <= 40, !topics.contains(where: { $0.caseInsensitiveCompare(topic) == .orderedSame }) else { continue }
            topics.append(topic)
            if topics.count == 4 { break }
        }

        let summary = shortVersion(person: person, total: all.count, fromYou: mine.count, since: since,
                                   usual: usual, open: open, topics: topics, isOrganization: isOrganization)
        return PersonProfile(shortVersion: summary, total: all.count, fromYou: mine.count, since: since,
                             usualReply: usual, open: open, topics: topics)
    }

    static func shortVersion(person: Person, total: Int, fromYou: Int, since: Date?, usual: TimeInterval?,
                             open: [OpenItem], topics: [String], isOrganization: Bool) -> String {
        var parts: [String] = []
        let sinceText = since.map { " since " + $0.formatted(.dateTime.month(.abbreviated).year()) } ?? ""
        if isOrganization {
            parts.append("\(person.name). \(total) email\(total == 1 ? "" : "s")\(sinceText).")
        } else {
            parts.append("You've traded \(total) email\(total == 1 ? "" : "s") with \(person.firstName)\(sinceText).")
        }
        if let first = topics.first {
            parts.append(topics.count > 1 ? "Lately: \(first) and \(topics[1])." : "Lately: \(first).")
        }
        if fromYou == 0 {
            parts.append(isOrganization ? "You've never written back." : "You haven't replied yet.")
        } else if let usual {
            parts.append("You usually reply within \(duration(usual)).")
        }
        if let ask = open.first(where: \.theirs) {
            parts.append("Waiting on you: \u{201C}\(ask.text)\u{201D}")
        } else if let promise = open.first(where: { !$0.theirs }) {
            parts.append("You owe them: \u{201C}\(promise.text)\u{201D}")
        } else {
            parts.append(isOrganization ? "Nothing needs you." : "Nothing open.")
        }
        return parts.joined(separator: " ")
    }

    /// "1 hr", "5 hr", "2 days".
    static func duration(_ interval: TimeInterval) -> String {
        let hours = interval / 3600
        if hours < 1 { return "an hour" }
        if hours < 36 { return "\(Int(hours.rounded())) hr" }
        return "\(Int((hours / 24).rounded())) days"
    }

    /// Uses the strict commitment rules (PromiseRules), not the old loose phrase list.
    static func promiseSentence(in body: String) -> String? {
        PromiseRules.sentence(in: body)
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
}
