import Foundation

/// Handoffs from a session to the Grok or Claude app, most seamless first: open the app with the prompt filled in,
/// then the website, then copy. These links are not officially documented and have broken before, so copy stays.
enum HandoffLink {
    /// Long prompts do not fit in a link; those are copied instead.
    static let maxPromptLength = 6_000

    static func encoded(_ prompt: String) -> String? {
        guard prompt.count <= maxPromptLength else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return prompt.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    /// The agent's own app. Claude documents a claude:// scheme; Grok's app is reached through its website link,
    /// which iOS hands to the app when it is installed.
    static func appURL(_ agent: HandoffAgent, prompt: String) -> URL? {
        guard let q = encoded(prompt) else { return nil }
        switch agent {
        case .claude: return URL(string: "claude://claude.ai/new?q=" + q)
        case .grok: return URL(string: "https://grok.com/?q=" + q)
        }
    }

    static func webURL(_ agent: HandoffAgent, prompt: String) -> URL? {
        guard let q = encoded(prompt) else { return nil }
        switch agent {
        case .claude: return URL(string: "https://claude.ai/new?q=" + q)
        case .grok: return URL(string: "https://grok.com/?q=" + q)
        }
    }
}

extension HandoffPrompt {
    /// "[Lovely] H-3F2A": the subject the agent's report must use, so Lovely can match it to the task.
    static func reportSubject(_ id: String) -> String { "[Lovely] " + id }

    static func newReportID() -> String { "H-" + String(UUID().uuidString.prefix(4)) }

    /// A session handoff: the Sprint 6 prompt (irreversible steps first), plus the report-back line.
    static func sessionPrompt(task: String, item: SessionItem, agent: HandoffAgent, reportTo: String?, reportID: String) -> String {
        let facts = [
            "From: \(item.message.fromName)",
            "Subject: \(item.message.subject)",
            String(item.message.text.prefix(1_200)),
        ]
        let irreversible = detectIrreversible(in: task + "\n" + item.message.text)
        let base = build(HandoffTask(goal: task, facts: facts, steps: [], irreversible: irreversible.isEmpty ? ["Submitting, paying, signing or enrolling"] : irreversible),
                         agent: agent, keepEmails: Set([reportTo?.lowercased()].compactMap { $0 }))
        guard let reportTo, !reportTo.isEmpty else { return base }
        return base + "\n\nThen email that report to \(reportTo) with the subject \"\(reportSubject(reportID))\" so Lovely can close the task."
    }

    static func isReport(subject: String) -> Bool { subject.trimmingCharacters(in: .whitespaces).hasPrefix("[Lovely] H-") }
}
