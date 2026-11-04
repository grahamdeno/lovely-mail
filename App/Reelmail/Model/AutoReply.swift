import Foundation

/// Automatic replies ("Out of office") and delivery notices. Pure, so they are tested without a phone.
/// See docs/sprint5-design.md.
enum AutoReply {
    /// Subject starts, after Re: and Fwd: are removed. Lowercase.
    static let subjectPrefixes = ["automatic reply", "auto:", "autoreply", "auto-reply", "auto reply", "out of office",
                                  "out of the office", "ooo:", "away:"]
    /// Phrases in the author's own words. Two are needed, so one person's passing "I'll be out of the office Friday" is not an auto-reply.
    static let bodyPhrases = ["out of the office", "out of office", "limited access to email", "limited access to my email",
                              "i am currently away", "i'm currently away", "will respond when i return",
                              "respond to your email when i return", "return on", "back in the office"]

    /// From the mail's own headers. RFC 3834 `Auto-Submitted: auto-replied` is a vacation or similar reply;
    /// `auto-generated` is a system notice and is left to the other rules.
    static func isAutoReply(autoSubmitted: String?, xAutoreply: String?, xAutorespond: String?) -> Bool {
        if let value = autoSubmitted?.trimmingCharacters(in: .whitespaces).lowercased(), value.hasPrefix("auto-replied") { return true }
        return xAutoreply != nil || xAutorespond != nil
    }

    static func subjectIsAutoReply(_ subject: String) -> Bool {
        var s = subject.trimmingCharacters(in: .whitespaces).lowercased()
        var changed = true
        while changed {
            changed = false
            for prefix in ["re:", "fwd:", "fw:"] where s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces); changed = true
            }
        }
        return subjectPrefixes.contains { s.hasPrefix($0) }
    }

    static func bodyIsAutoReply(_ body: String) -> Bool {
        let text = ReplySignals.authoredBody(body).replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
        return bodyPhrases.filter { text.contains($0) }.count >= 2
    }

    static func isAutoReply(_ email: Email) -> Bool {
        email.isMarkedAutoReply || subjectIsAutoReply(email.subject) || bodyIsAutoReply(email.body)
    }
}

/// Shipping and delivery notices: dates in them are not plans, and they are not for you to answer.
enum DeliveryNotice {
    static let phrases = ["out for delivery", "has shipped", "has been shipped", "was delivered", "has been delivered",
                          "delivery attempt", "arriving today", "arriving tomorrow", "tracking number",
                          "track your package", "track your order"]
    /// Words in the part of the address before the @ that mean a shipping system.
    static let senderWords: Set<String> = ["tracking", "shipment", "shipments", "shipping", "delivery", "deliveries", "orders", "order-update"]

    static func hasPhrase(_ text: String) -> Bool {
        let l = text.lowercased()
        return phrases.contains { l.contains($0) }
    }

    static func shippingSender(_ address: String) -> Bool {
        let local = address.split(separator: "@").first.map { String($0).lowercased() } ?? ""
        let words = local.split(whereSeparator: { $0 == "." || $0 == "_" }).map(String.init)
        return words.contains { senderWords.contains($0) } || senderWords.contains(local)
    }

    /// A delivery phrase, plus either an automated signal or a shipping sender. A person writing "the box was
    /// delivered, thanks" has neither, so it stays with People.
    static func isDeliveryNotice(_ email: Email) -> Bool {
        let text = email.subject + "\n" + ReplySignals.authoredBody(email.body)
        guard hasPhrase(text) else { return false }
        return email.isAutomated || shippingSender(email.from.email)
    }
}
