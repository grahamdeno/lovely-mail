import Foundation

/// The text a summarizer sees. Built on device; nothing here leaves the phone.
struct SummaryInput: Sendable, Hashable {
    var sender: String
    var senderIsAutomated: Bool
    var subject: String
    var body: String

    init(sender: String, senderIsAutomated: Bool = false, subject: String, body: String) {
        self.sender = sender
        self.senderIsAutomated = senderIsAutomated
        self.subject = subject
        self.body = body
    }

    /// The body is the author's own words (quoted replies, signatures and forwards removed), or the whole
    /// body when they wrote almost nothing.
    init(email: Email) {
        self.init(sender: email.from.name, senderIsAutomated: email.from.isAutomated,
                  subject: email.subject, body: ReplySignals.summaryBody(email.body))
    }

    /// Parse "From: / Subject:" headers out of pasted text, if present.
    init(pasted text: String) {
        var sender = "Unknown sender"
        var subject = ""
        var bodyLines: [String] = []
        var inHeaders = true
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inHeaders, trimmed.lowercased().hasPrefix("from:") {
                sender = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if let lt = sender.firstIndex(of: "<") {
                    sender = String(sender[..<lt]).trimmingCharacters(in: .whitespaces)
                }
            } else if inHeaders, trimmed.lowercased().hasPrefix("subject:") {
                subject = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if inHeaders, trimmed.isEmpty, !(subject.isEmpty && sender == "Unknown sender") {
                inHeaders = false
            } else {
                inHeaders = false
                bodyLines.append(line)
            }
        }
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(sender: sender, senderIsAutomated: false, subject: subject, body: body)
    }
}

/// Turns one email into a feed post. Implementations must run on device only.
protocol EmailSummarizer: Sendable {
    var engine: SummaryEngine { get }
    func summarize(_ input: SummaryInput) async throws -> EmailSummary
}

enum SummarizerFactory {
    /// Apple Intelligence when the model is ready, otherwise the heuristic fallback.
    static func best() -> any EmailSummarizer {
        ModelStatus.current.isAvailable ? AppleIntelligenceSummarizer() : FallbackSummarizer()
    }
}

/// Word-count helpers shared by both summarizers.
enum TextClamp {
    static func words(_ text: String, max: Int) -> String {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        guard words.count > max else { return words.joined(separator: " ") }
        var clipped = words.prefix(max).joined(separator: " ")
        while let last = clipped.last, ",;:.-".contains(last) { clipped.removeLast() }
        return clipped + "…"
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
}
