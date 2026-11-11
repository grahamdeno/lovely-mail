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

    /// The one safety line, first and exactly so (owner, Nov 11, 2026).
    static let stopLine = "STOP AND ASK ME FIRST before you submit, pay, sign, send, delete anything, or upload an ID or personal document."

    /// The report's subject, exactly: "Grok report: <short title>".
    static func reportSubject(_ task: String) -> String { "\(reportTag): \(shortTitle(task))" }

    /// The message Grok gets, kept short: the stop line, the task, at most three facts Lovely already knows (never from
    /// health mail), and where to send the report.
    static func prompt(task: String, facts: [GrokFact], reportTo: String) -> String {
        let t = task.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = stopLine + "\n\nTask: " + t
        let kept = facts.filter { !$0.isHealth }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(3)
        if !kept.isEmpty { out += "\n\nFrom my mail:\n" + kept.map { "- " + String($0.prefix(200)) }.joined(separator: "\n") }
        out += "\n\nWhen you are done or stuck, reply by email to \(reportTo) with the subject exactly: \(reportSubject(t))"
        return out
    }

    /// The webhook body Grok Bot's routine receives.
    static func payload(task: String, prompt: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["source": "lovely", "task": task, "prompt": prompt], options: [.sortedKeys])) ?? Data()
    }

    /// Only HTTP 200 means Grok Bot took it. Anything else is not sent, and only then may the share sheet open.
    static func outcome(configured: Bool, status: Int?, transportFailed: Bool) -> GrokSendResult {
        guard configured else { return .notSent(.noWebhook) }
        if transportFailed || status == nil { return .notSent(.unreachable) }
        return status == 200 ? .accepted : .notSent(.rejected(status ?? 0))
    }

    /// A report email belongs to a hand-off when its subject is "Grok report: <that hand-off's title>".
    static func isReport(subject: String, title: String) -> Bool {
        let s = subject.lowercased(), t = title.lowercased()
        return !t.isEmpty && s.contains(reportTag.lowercased()) && s.contains(t)
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

/// Something Lovely knows that may help Grok. Health mail is never passed on.
struct GrokFact: Equatable {
    var text: String
    var isHealth = false
}

enum GrokSendResult: Equatable {
    enum NotSent: Equatable { case noWebhook, rejected(Int), unreachable }
    case accepted
    case notSent(NotSent)

    var accepted: Bool { self == .accepted }
    /// The share sheet is the fallback for every not-sent case, never after a 200.
    var opensShareSheet: Bool { !accepted }

    /// The line on the card.
    var note: String {
        switch self {
        case .accepted: return "Grok Bot has it. The report will show up here. Lovely can't see the work until then."
        case .notSent(.noWebhook): return "No Grok Bot webhook saved (Settings > AI). Share sheet is open."
        case .notSent: return "Couldn't reach Grok. Share sheet is open."
        }
    }
}

/// The Grok Bot routine's webhook, copied once from the bot. Keychain, this device only.
enum GrokWebhook {
    static let urlStore = KeychainStore(service: "com.grahamdeno.reelmail.grokbot", account: "webhook-url")
    static let authStore = KeychainStore(service: "com.grahamdeno.reelmail.grokbot", account: "webhook-auth")

    static var url: URL? {
        guard let d = urlStore.load(), let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let u = URL(string: s), u.scheme == "https" else { return nil }
        return u
    }
    static var authorization: String? {
        guard let d = authStore.load(), let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
    static var isSaved: Bool { url != nil }
    static func save(url: String, authorization: String) {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines), a = authorization.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { urlStore.delete() } else { urlStore.save(Data(u.utf8)) }
        if a.isEmpty { authStore.delete() } else { authStore.save(Data(a.utf8)) }
    }

    /// POSTs the task. Only a 200 is accepted.
    static func send(task: String, prompt: String) async -> GrokSendResult {
        guard let url else { return GrokHandoff.outcome(configured: false, status: nil, transportFailed: false) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let a = authorization { req.setValue(a, forHTTPHeaderField: "Authorization") }
        req.httpBody = GrokHandoff.payload(task: task, prompt: prompt)
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return GrokHandoff.outcome(configured: true, status: (response as? HTTPURLResponse)?.statusCode, transportFailed: false)
        } catch {
            return GrokHandoff.outcome(configured: true, status: nil, transportFailed: true)
        }
    }
}

/// Hand-offs Grok Bot accepted, kept so the report finds its question again after Home closes.
struct GrokHandoffLog {
    struct Item: Codable, Equatable, Identifiable {
        var id: UUID
        var question: String
        var task: String
        var title: String
        var sentAt: Date
        var report: String?
    }
    static let key = "lovely.grok.handoffs"
    var defaults: UserDefaults = .standard

    var items: [Item] {
        guard let d = defaults.data(forKey: Self.key), let i = try? JSONDecoder().decode([Item].self, from: d) else { return [] }
        return i
    }
    func save(_ items: [Item]) {
        // Two weeks is plenty; the label keeps the reports.
        let recent = items.filter { $0.sentAt > Date().addingTimeInterval(-14 * 86_400) }.suffix(30)
        if let d = try? JSONEncoder().encode(Array(recent)) { defaults.set(d, forKey: Self.key) }
    }
    func add(_ item: Item) { save(items.filter { $0.id != item.id } + [item]) }
    func setReport(_ id: UUID, _ text: String) { save(items.map { var i = $0; if i.id == id { i.report = text }; return i }) }
    var waiting: [Item] { items.filter { $0.report == nil } }
}
