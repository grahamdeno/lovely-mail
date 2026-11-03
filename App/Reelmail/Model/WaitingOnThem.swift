import Foundation

/// "Waiting on them": something you asked, sent to a few people, with no answer yet.
/// Deliberately strict; see docs/sprint3-design.md. Pure, so it is tested without views or network.
enum WaitingOnThem {
    static let minAge: TimeInterval = 3 * 86_400
    static let maxAge: TimeInterval = 21 * 86_400
    static let maxRecipients = 3
    /// Thread lookups per refresh (read-only, 10 quota units each).
    static let maxLookups = 20

    struct Item: Equatable, Identifiable {
        let id: String           // the sent message id
        let email: Email
        let ask: String
        /// The first To address, as written.
        var recipient: String { email.to.first.map(EmailPresentation.address(in:)) ?? "" }
    }

    /// Your sent asks that pass every rule except "nobody has answered" (which needs the thread).
    /// One per thread: your latest ask. `dismissed` holds the ids you removed with Got it.
    static func candidates(sent: [Email], context: TriageContext, dismissed: Set<String>, now: Date) -> [Item] {
        var latestByThread: [String: Item] = [:]
        for email in sent where email.isFromMe || context.isMine(email) {
            let age = now.timeIntervalSince(email.date)
            guard age >= minAge, age <= maxAge, !dismissed.contains(email.id) else { continue }
            guard (1...maxRecipients).contains(email.to.count), allRealRecipients(email, context: context) else { continue }
            guard let ask = ReplySignals.askSentence(in: email.body) else { continue }
            if let existing = latestByThread[email.threadId], existing.email.date >= email.date { continue }
            latestByThread[email.threadId] = Item(id: email.id, email: email, ask: ask)
        }
        return latestByThread.values.sorted { $0.email.date > $1.email.date }
    }

    /// True when mail already loaded shows someone else wrote in the thread after your ask.
    static func answeredInLoadedMail(_ item: Item, inbox: [Email], context: TriageContext) -> Bool {
        inbox.contains { $0.threadId == item.email.threadId && $0.date > item.email.date && !context.isMine($0) }
    }

    /// True when no inbox mail is loaded for the thread at all, so a read-only thread lookup is needed to be sure.
    static func needsLookup(_ item: Item, inbox: [Email]) -> Bool {
        !inbox.contains { $0.threadId == item.email.threadId }
    }

    /// True when a thread lookup shows someone other than you wrote after your ask.
    static func answered(_ item: Item, senders: [ThreadSender], context: TriageContext) -> Bool {
        senders.contains { sender in
            let address = TriageContext.canonical(sender.address)
            let mine = context.myAddresses.contains(address) || context.otherAddresses.contains(address)
            return !mine && sender.date > item.email.date
        }
    }

    /// The items to show, given what is loaded and what lookups found.
    /// `lookups`: thread id → senders, for threads that were looked up. A thread that needs a lookup and has none
    /// yet (cap reached, offline) stays out: a wrong item costs more than a late one.
    static func open(candidates: [Item], inbox: [Email], context: TriageContext, lookups: [String: [ThreadSender]]) -> [Item] {
        candidates.filter { item in
            if answeredInLoadedMail(item, inbox: inbox, context: context) { return false }
            if needsLookup(item, inbox: inbox) {
                guard let senders = lookups[item.email.threadId] else { return false }
                return !answered(item, senders: senders, context: context)
            }
            return true
        }
    }

    /// Which candidates to look up now: those that need it, newest first, not already looked up, up to the cap.
    static func lookupTargets(candidates: [Item], inbox: [Email], already: Set<String>) -> [Item] {
        Array(candidates.filter { needsLookup($0, inbox: inbox) && !already.contains($0.email.threadId) }.prefix(maxLookups))
    }

    private static func allRealRecipients(_ email: Email, context: TriageContext) -> Bool {
        email.to.allSatisfy { raw in
            let address = EmailPresentation.address(in: raw)
            guard !address.isEmpty else { return false }
            let canonical = TriageContext.canonical(address)
            if context.myAddresses.contains(canonical) || context.otherAddresses.contains(canonical) { return false }
            return !SenderSignals.looksAutomated(address: address)
        }
    }

    /// "Hi Dana, checking on this when you have a minute. Thanks, Graham"
    static func nudgeText(recipientFirstName: String, myFirstName: String) -> String {
        let base = "Hi \(recipientFirstName), checking on this when you have a minute. Thanks"
        return myFirstName.isEmpty || myFirstName.lowercased() == "you" ? base + "." : base + ", " + myFirstName
    }
}
