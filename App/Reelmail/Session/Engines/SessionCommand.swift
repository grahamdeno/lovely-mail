import Foundation

// The one action schema every engine answers in (Apple, Claude, Grok). Lovely validates each answer against it and
// refuses anything outside it, so no engine can make Lovely do something the owner did not see. Pure, so it is tested.
// See docs/sprint7-design.md section 10.

/// What an engine sends back, exactly as the playbook's schema describes it.
struct SessionCommand: Codable, Equatable, Sendable {
    /// reply, put_away, add_date, later, leave_unread, archive, trash, skip, handoff, search, unclear
    var action: String
    /// For put_away, add_date and reply: one of the category names in the playbook ("Finance", "Family/Avery").
    var drawer: String?
    /// For reply: the full reply text, in the owner's voice.
    var reply: String?
    /// For later: "this evening", "tomorrow", "this weekend" or "next week".
    var later: String?
    /// For handoff: the task for an outside agent, in one or two sentences.
    var task: String?
    /// One short sentence to show the owner: what will happen, or what is unclear.
    var say: String?
    /// For search: a Gmail search ("to:support@example.com newer_than:30d"). Lovely runs it read-only on the phone.
    var query: String?

    init(action: String, drawer: String? = nil, reply: String? = nil, later: String? = nil, task: String? = nil, say: String? = nil,
         query: String? = nil) {
        self.action = action; self.drawer = drawer; self.reply = reply; self.later = later; self.task = task; self.say = say
        self.query = query
    }

    static let actions = ["reply", "put_away", "add_date", "later", "leave_unread", "archive", "trash", "skip", "handoff", "search", "unclear"]
    static let laterChoices = ["this evening", "tomorrow", "this weekend", "next week"]
}

/// A command Lovely accepted, with real types.
enum SessionAction: Equatable, Sendable {
    case reply(text: String, drawer: DrawerChoice)
    case putAway(DrawerChoice)
    case addDateThenPutAway(DrawerChoice)
    case later(String)
    case leaveUnread
    case archive
    /// Gmail's Trash, which keeps it 30 days. Never a permanent delete.
    case trash
    case skip
    case handoff(task: String)
    /// Look something up in his Gmail (read-only, on the phone; results never go to an engine).
    case search(query: String)
    case unclear(String)

    /// The one-line description on the confirm card.
    var title: String {
        switch self {
        case .reply(_, let d): return "Send and put away in \(d.title)"
        case .putAway(let d): return "Put away in \(d.title)"
        case .addDateThenPutAway(let d): return "Add the date, then put away in \(d.title)"
        case .later(let when): return "Later: \(when)"
        case .leaveUnread: return "Leave it unread"
        case .archive: return "Archive, no drawer"
        case .trash: return "Move to Trash"
        case .skip: return "Skip for now"
        case .handoff: return "Hand this to an agent"
        case .search(let q): return "Searched Gmail: \(q)"
        case .unclear(let why): return why
        }
    }
}

enum SessionCommandValidator {
    static let maxReplyCharacters = 4_000

    /// Everyday words for the categories, and the names from the first fixed set (Money, Kids, Orders, Personal).
    static let aliases: [String: Drawer] = [
        "house": .home, "utilities": .home, "phone": .home, "internet": .home, "mortgage": .home,
        "car": .auto, "cars": .auto, "vehicle": .auto, "truck": .auto,
        "money": .finance, "bills": .finance, "bank": .finance, "banking": .finance,
        "kids": .family, "school": .family, "wife": .family,
        "life insurance": .lifeLegal, "legal": .lifeLegal, "life": .lifeLegal, "estate": .lifeLegal,
        "va": .government, "military": .government, "irs": .government,
        "medical": .health, "doctor": .health,
        "job": .work, "career": .work, "business": .projects, "apps": .projects,
        "orders": .shopping, "order": .shopping, "amazon": .shopping,
        "personal": .community, "people": .community, "friends": .community, "reference": .community, "hockey": .community,
        "trips": .travel, "trip": .travel, "pet": .pets, "vet": .pets,
        "security": .accounts, "logins": .accounts, "login": .accounts,
    ]

    /// The category a name refers to, from the visible set only. "family/avery", "Kids · Avery" and "Money" all work.
    static func drawer(named raw: String?, kids: [KidProfile]) -> DrawerChoice? {
        guard let raw else { return nil }
        let cleaned = raw.replacingOccurrences(of: "Lovely/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "·", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let first = parts.first,
              let d = Drawer.allCases.first(where: { $0.title.lowercased() == first || $0.rawValue == first })
                ?? aliases[first].flatMap({ $0.isHidden ? nil : $0 }) else { return nil }
        if d == .family, parts.count > 1 {
            guard let kid = kids.first(where: { $0.name.lowercased() == parts[1] }) else { return DrawerChoice(.family) }
            return DrawerChoice(.family, child: kid.name)
        }
        return DrawerChoice(d)
    }

    /// Turns an engine's answer into an action, or `unclear` with the reason. Never throws, never guesses a drawer:
    /// a missing drawer falls back to the item's own suggestion, and an unknown one is refused.
    static func validate(_ c: SessionCommand, item: SessionItem, kids: [KidProfile]) -> SessionAction {
        let fallbackDrawer = item.drawer?.choice
        func drawerOrFallback() -> DrawerChoice? {
            if let named = c.drawer, !named.trimmingCharacters(in: .whitespaces).isEmpty { return drawer(named: named, kids: kids) }
            return fallbackDrawer
        }
        switch c.action.lowercased() {
        case "reply":
            let text = (c.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .unclear("I could not write that reply. Try saying what to tell them.") }
            guard text.count <= maxReplyCharacters else { return .unclear("That reply is too long to send from here. Finish it in Gmail.") }
            return .reply(text: text, drawer: drawerOrFallback() ?? DrawerChoice(.personal))
        case "put_away":
            guard let d = drawerOrFallback() else { return .unclear(c.drawer.map { "There is no \($0) drawer." } ?? "Which drawer?") }
            return .putAway(d)
        case "add_date":
            guard let d = drawerOrFallback() else { return .unclear("Which drawer should it go in after the date?") }
            return .addDateThenPutAway(d)
        case "later":
            let when = (c.later ?? "tomorrow").lowercased()
            return .later(SessionCommand.laterChoices.contains(when) ? when : "tomorrow")
        case "leave_unread": return .leaveUnread
        case "archive": return .archive
        case "trash", "delete": return .trash
        case "skip": return .skip
        case "handoff":
            let task = (c.task ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return task.isEmpty ? .unclear("What should the agent do?") : .handoff(task: String(task.prefix(600)))
        case "search":
            let q = (c.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return .unclear("What should I look for in your Gmail?") }
            return .search(query: String(q.prefix(200)))
        default:
            return .unclear(c.say?.isEmpty == false ? c.say! : "I did not follow that. Try one of the buttons.")
        }
    }
}

/// Short commands understood without any model, on every phone, instantly and for free.
/// Anything longer or unusual goes to the engine.
enum SessionQuickCommands {
    /// `fromPerson`: someone wrote it, so "yes" or "ok" is an answer to them, not filing; the engine handles it.
    static func parse(_ sentence: String, kids: [KidProfile], fromPerson: Bool = false) -> SessionCommand? {
        var s = sentence.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, ".!".contains(last) { s.removeLast() }
        s = s.replacingOccurrences(of: "please ", with: "")
        guard !s.isEmpty, s.split(separator: " ").count <= 8 else { return nil }

        let exact: [String: SessionCommand] = [
            "skip": SessionCommand(action: "skip"), "next": SessionCommand(action: "skip"), "not now": SessionCommand(action: "skip"),
            "leave it": SessionCommand(action: "leave_unread"), "leave it unread": SessionCommand(action: "leave_unread"),
            "keep it unread": SessionCommand(action: "leave_unread"), "leave unread": SessionCommand(action: "leave_unread"),
            "archive": SessionCommand(action: "archive"), "archive it": SessionCommand(action: "archive"),
            "file it": SessionCommand(action: "put_away"), "put it away": SessionCommand(action: "put_away"),
            "file it away": SessionCommand(action: "put_away"), "file this away": SessionCommand(action: "put_away"),
            "done": SessionCommand(action: "put_away"), "yes": SessionCommand(action: "put_away"), "ok": SessionCommand(action: "put_away"),
            "later": SessionCommand(action: "later", later: "tomorrow"),
            "delete": SessionCommand(action: "trash"), "delete it": SessionCommand(action: "trash"), "delete this": SessionCommand(action: "trash"),
            "trash": SessionCommand(action: "trash"), "trash it": SessionCommand(action: "trash"), "move to trash": SessionCommand(action: "trash"),
            "junk": SessionCommand(action: "trash"), "get rid of it": SessionCommand(action: "trash"), "toss it": SessionCommand(action: "trash"),
        ]
        if fromPerson, ["yes", "ok", "done"].contains(s) { return nil }
        if let c = exact[s] { return c }

        for when in SessionCommand.laterChoices where s == "later \(when)" || s == when || s == "remind me \(when)" {
            return SessionCommand(action: "later", later: when)
        }

        // "file it in money", "put it in kids", "money", "kids avery", "move to house"
        let fileWords = ["file it in ", "file in ", "put it in ", "put in ", "move it to ", "move to ", "goes in ", "in "]
        var rest = s
        for w in fileWords where rest.hasPrefix(w) { rest = String(rest.dropFirst(w.count)); break }
        rest = rest.replacingOccurrences(of: "the ", with: "").replacingOccurrences(of: " drawer", with: "")
        let candidate = rest.replacingOccurrences(of: " ", with: "/")
        if let d = SessionCommandValidator.drawer(named: candidate, kids: kids) ?? SessionCommandValidator.drawer(named: rest, kids: kids) {
            return SessionCommand(action: "put_away", drawer: d.engineName)
        }
        return nil
    }
}
