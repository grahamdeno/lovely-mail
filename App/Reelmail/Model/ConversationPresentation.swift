import Foundation

struct ConversationPreview: Equatable {
    let text: String
    let label: String?
    let concealed: Bool
}

enum ConversationPresentation {
    /// Hides a preview only for real secrets (codes, passwords, keys, account numbers). Apple Intelligence's own
    /// "sensitive" guess hid ordinary school mail, so it no longer decides this.
    static func isSensitive(_ email: Email, summary: EmailSummary?) -> Bool {
        FallbackSummarizer.isSensitive((email.subject + "\n" + email.body).lowercased())
    }

    /// One line for a list row. A forward reads "You forwarded: Costco order confirmed", not its raw header block.
    static func rowText(_ email: Email, summary: EmailSummary?) -> String {
        let subject = FallbackSummarizer.cleanSubject(email.subject, fallbackBody: "")
        let own = ReplySignals.authoredText(email.body).trimmingCharacters(in: .whitespacesAndNewlines)
        let forwarded = email.subject.lowercased().hasPrefix("fwd:") || email.subject.lowercased().hasPrefix("fw:")
            || email.body.contains("Forwarded message") || email.body.contains("Begin forwarded message")
        if forwarded, own.count < 3 || own.lowercased().hasPrefix("sent from my") {
            return (email.isFromMe ? "You forwarded: " : "Forwarded: ") + subject
        }
        let p = preview(email, summary: summary)
        return (email.isFromMe ? "You: " : "") + FallbackSummarizer.firstSentence(of: p.text)
    }
    static func preview(_ email: Email, summary: EmailSummary?) -> ConversationPreview {
        if isSensitive(email, summary: summary) {
            return ConversationPreview(text: "Private details hidden. Open the source to read.", label: nil, concealed: true)
        }
        let body = email.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return ConversationPreview(text: "No readable text was imported.", label: nil, concealed: false)
        }
        let originalLimit = email.isFromMe ? 320 : 160
        if body.count <= originalLimit {
            return ConversationPreview(text: body, label: nil, concealed: false)
        }
        if let summary, !summary.blurb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ConversationPreview(text: summary.blurb,
                label: summary.engine == .appleIntelligence ? "Generated summary" : "Excerpt", concealed: false)
        }
        return ConversationPreview(text: String(body.prefix(320)) + (body.count > 320 ? "…" : ""), label: "Excerpt", concealed: false)
    }
    static func groups(_ email: Email, after previous: Email?, calendar: Calendar = .current) -> Bool {
        guard let previous else { return false }
        let gap = email.date.timeIntervalSince(previous.date)
        return email.threadId == previous.threadId
            && email.from.id == previous.from.id
            && email.isFromMe == previous.isFromMe
            && calendar.isDate(email.date, inSameDayAs: previous.date)
            && gap >= 0 && gap <= 300
    }
}
