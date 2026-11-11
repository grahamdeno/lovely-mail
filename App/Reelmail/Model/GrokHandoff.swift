import Foundation

/// Hand to Grok (owner, Nov 10, 2026): when Lovely's model can't do something (anything that needs the web: forms,
/// sign-ups, searching a site, filing and uploading), Lovely hands the task to his Grok Bot app with what it knows from
/// his mail. Grok does it, notifies him, and emails a report titled "Grok report: …", which a Gmail filter labels
/// Lovely/Grok reports and keeps out of the inbox. No xAI API key. Pure parts here, so they are tested.
enum GrokHandoff {
    static let reportTag = "Grok report"
    static let label = "Lovely/Grok reports"
    /// Gmail search for the label (slashes and spaces become hyphens).
    static let searchQuery = "label:lovely-grok-reports"
    static let shortcutKey = "lovely.grok.shortcut"
    static let filterKey = "lovely.grok.reportsFilter"

    /// Added to every question asked on Home, so the engine says when Grok should take it.
    static let engineRule = """
    If doing this needs the web or acting outside his mail and calendar (filling in a form, signing up, searching a \
    website, filing a claim, uploading something), start your reply with one line: HANDOFF: followed by the task in one \
    sentence for his Grok assistant. Then say briefly what you know from his mail that will help.
    """

    /// "HANDOFF: …" on the first line: the task for Grok, and the rest of the answer.
    static func parse(_ answer: String) -> (task: String?, rest: String) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        guard let first = lines.first, first.uppercased().hasPrefix("HANDOFF:") else { return (nil, trimmed) }
        let task = first.dropFirst("HANDOFF:".count).trimmingCharacters(in: .whitespaces)
        let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (task.isEmpty ? nil : task, rest)
    }

    /// "Ask Grok to …", "Have Grok …", "Grok, …": he asked for Grok by name, so no engine is needed.
    static func explicitTask(_ question: String) -> String? {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()
        for prefix in ["ask grok to ", "have grok ", "tell grok to ", "send to grok: ", "send to grok ", "hand to grok: ", "hand to grok ", "grok, ", "grok: "]
        where lower.hasPrefix(prefix) {
            let task = String(q.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return task.isEmpty ? nil : task.prefix(1).uppercased() + task.dropFirst()
        }
        return nil
    }

    /// "Tennessee unclaimed property search" from a longer sentence: the first eight words, no end punctuation.
    static func shortTitle(_ task: String) -> String {
        let words = task.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).prefix(8).joined(separator: " ")
        return words.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,;: "))
    }

    /// The message Grok gets. The stop rule comes first and stands out (owner: crucial, irreversible steps first).
    static func prompt(task: String, context: [String], reportTo: String) -> String {
        var out = """
        STOP AND ASK ME FIRST before you submit, pay, sign, send, delete anything, or upload an ID or personal document.

        Task from Lovely, my mail app: \(task.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        let facts = context.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !facts.isEmpty {
            out += "\n\nWhat Lovely knows from my mail:\n" + facts.map { "- " + String($0.prefix(600)) }.joined(separator: "\n")
        }
        out += """


        When you are done, or stuck, email \(reportTo) a short report with the subject "\(reportTag): \(shortTitle(task))": \
        what you did, what you found, and anything waiting on me. Notify me too.
        """
        return out
    }

    /// Runs his Shortcut (one step: Grok Bot's Send Message) with the text as input.
    static func shortcutURL(name: String, text: String) -> URL? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "shortcuts"
        c.host = "run-shortcut"
        c.queryItems = [URLQueryItem(name: "name", value: n), URLQueryItem(name: "input", value: "text"), URLQueryItem(name: "text", value: text)]
        return c.url
    }

    /// The one-time Gmail filter that labels and archives Grok's reports, as a preview.
    static func filterPreview(owner: String) -> ActionPreview {
        ActionPreview(kind: .filter, title: "File Grok's reports", lines: [
            "Creates a Gmail filter: mail from \(owner) with \"\(reportTag)\" in the subject goes to Grok reports and skips your inbox.",
            "Grok's own notification tells you when it's done; the report waits in Grok reports (⋯ on Home).",
            "Nothing is deleted. Remove it any time in Settings > Gmail filters.",
        ])
    }
}
