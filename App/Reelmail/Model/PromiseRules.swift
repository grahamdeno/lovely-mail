import Foundation

/// "You said you would": commitments in mail you sent. Deliberately strict; see docs/sprint3-design.md.
/// Pure, so it is tested without views.
enum PromiseRules {
    /// How long a promise stays on Home. The person page keeps it for `PersonProfile.promiseWindow`.
    static let homeWindow: TimeInterval = 14 * 86_400

    private static let actions = "send|get you|get back to you|get it|call|follow up|check|look into|look at|find|forward|share|review|sign|pay|"
        + "schedule|book|set up|put together|draft|update you|confirm|ask|reach out|circle back|text|email|write up|bring|"
        + "drop off|pick up|order|fix|submit|file|handle|take care of|loop you in|let you know"
    private static let lead = #"\b(i'll|i will|i'm going to|i am going to)\s+(also\s+|just\s+|try to\s+|go ahead and\s+)?("# + actions + #")\b"#
    private static let letMe = #"\blet me\s+(check|look into|look at|find|ask)\b"#

    /// True when one sentence commits the sender to doing something specific for the recipient.
    static func isCommitment(_ sentence: String) -> Bool {
        let lower = ReplySignals.normalizeQuotes(sentence).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.count >= 8, !lower.hasSuffix("?") else { return false }
        // Conditional offers and "let me know" are not commitments.
        if lower.hasPrefix("if ") || lower.contains(" if ") || lower.contains("let me know") { return false }
        return lower.range(of: lead, options: .regularExpression) != nil
            || lower.range(of: letMe, options: .regularExpression) != nil
    }

    /// The first committing sentence in the author's own words, trimmed for display.
    static func sentence(in body: String) -> String? {
        let text = ReplySignals.authoredText(body)
        for line in text.components(separatedBy: .newlines) {
            var current = ""
            for ch in line + "." {
                current.append(ch)
                guard ".!?".contains(ch) else { continue }
                let sentence = current.trimmingCharacters(in: .whitespaces)
                current = ""
                if isCommitment(sentence) {
                    return sentence.count > 120 ? String(sentence.prefix(117)) + "…" : sentence
                }
            }
        }
        return nil
    }

    struct Item: Equatable, Identifiable {
        let id: String          // the sent message id
        let email: Email
        let text: String
        var recipient: String { email.to.first.map(EmailPresentation.address(in:)) ?? "" }
    }

    /// Open promises for Home. `sent` is your sent mail, `inbox` their mail, `closed` the ids you marked Done or Not a promise.
    /// `veto` may only remove items.
    static func open(sent: [Email], inbox: [Email], context: TriageContext, closed: Set<String>,
                     veto: (Email, String) -> Bool = { _, _ in true }, now: Date) -> [Item] {
        var items: [Item] = []
        for email in sent.sorted(by: { $0.date > $1.date }) {
            let age = now.timeIntervalSince(email.date)
            guard age >= 0, age <= homeWindow, !closed.contains(email.id) else { continue }
            guard hasRealRecipient(email, context: context) else { continue }
            guard let text = sentence(in: email.body) else { continue }
            // Closed by a later message from you or from them in the same thread.
            if sent.contains(where: { $0.threadId == email.threadId && $0.date > email.date }) { continue }
            if inbox.contains(where: { $0.threadId == email.threadId && $0.date > email.date }) { continue }
            guard veto(email, text) else { continue }
            items.append(Item(id: email.id, email: email, text: text))
        }
        return items
    }

    /// At least one To address that is not yours and not a no-reply system address.
    static func hasRealRecipient(_ email: Email, context: TriageContext) -> Bool {
        email.to.contains { raw in
            let address = EmailPresentation.address(in: raw)
            guard !address.isEmpty else { return false }
            let canonical = TriageContext.canonical(address)
            if context.myAddresses.contains(canonical) || context.otherAddresses.contains(canonical) { return false }
            return !SenderSignals.looksAutomated(address: address)
        }
    }

    /// "Dana" or "Dana and 2 others".
    static func recipientLine(_ email: Email, nameFor: (String) -> String?) -> String {
        let addresses = email.to.map(EmailPresentation.address(in:))
        guard let first = addresses.first else { return "" }
        let name = nameFor(first) ?? first
        return addresses.count > 1 ? "\(name) and \(addresses.count - 1) other\(addresses.count == 2 ? "" : "s")" : name
    }
}
