import Foundation

/// A sorting rule Lovely made from something the owner said. Local only; removable in one tap.
struct LearnedRule: Codable, Equatable, Identifiable {
    enum Source: String, Codable { case card, chat }
    var id: String
    /// Sender addresses the rule covers.
    var matches: [String]
    var exceptions: [String] = []
    var action: LocalMailDestination
    var source: Source
    var created: Date
    /// The owner's words, kept so the rule can be understood later.
    var note: String
}

/// What a chat sentence asks for. Read by fixed patterns, not by a model, so it can be tested and cannot be talked into more.
struct ChatIntent: Equatable {
    var action: LocalMailDestination
    var term: String
}

enum ChatInterpreter {
    private static let patterns: [(String, LocalMailDestination)] = [
        (#"^(?:please\s+)?(?:stop showing|hide|filter|mute|block)(?: me)?(?: mail| emails?)?(?: from)?\s+(.{2,60}?)[.!]?$"#, .filtered),
        (#"^(?:please\s+)?(?:move|put|send)\s+(.{2,60}?)\s+(?:to|into|in)\s+reading[.!]?$"#, .reading),
        (#"^(?:please\s+)?(?:show|keep)(?: me)?(?: mail| emails?)?(?: from)?\s+(.{2,60}?)\s+in (?:my )?(?:inbox|home)[.!]?$"#, .inbox)
    ]

    static func intent(_ sentence: String) -> ChatIntent? {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        for (pattern, action) in patterns {
            if let g = Rx.groups(pattern, in: text), g.count > 1 {
                let term = g[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'."))
                if !term.isEmpty { return ChatIntent(action: action, term: term) }
            }
        }
        return nil
    }

    /// Sender addresses whose name or address contains the term.
    static func senders(matching term: String, in posts: [Post]) -> [String] {
        let t = term.lowercased()
        var seen = Set<String>()
        return posts.compactMap { p -> String? in
            let a = p.email.from.email.lowercased()
            guard a.contains(t) || p.email.from.name.lowercased().contains(t), seen.insert(a).inserted else { return nil }
            return a
        }
    }
}

struct LearnedRuleStore {
    static let key = "lovely.learned.rules"
    static let chatSwitchKey = "lovely.chat.enabled"
    var defaults: UserDefaults = .standard

    var chatEnabled: Bool { defaults.bool(forKey: Self.chatSwitchKey) }

    var rules: [LearnedRule] {
        guard let data = defaults.data(forKey: Self.key), let r = try? JSONDecoder().decode([LearnedRule].self, from: data) else { return [] }
        return r
    }

    func add(_ rule: LearnedRule) { save(rules + [rule]) }
    func remove(_ ids: Set<String>) { save(rules.filter { !ids.contains($0.id) }) }
    var chatRules: [LearnedRule] { rules.filter { $0.source == .chat } }

    private func save(_ r: [LearnedRule]) {
        if let data = try? JSONEncoder().encode(r) { defaults.set(data, forKey: Self.key) }
    }
}
