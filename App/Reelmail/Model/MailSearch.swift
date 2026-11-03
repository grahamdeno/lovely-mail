import Foundation

/// Search rules. Pure, so they can be tested without views. A query is split into words; every word must
/// match somewhere in the item (name, address, subject, summary or body), in any order.
enum MailSearch {
    static func tokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func matches(_ fields: [String], tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        let haystack = fields.map { $0.lowercased() }
        return tokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
    }

    static func matches(_ post: Post, tokens: [String]) -> Bool {
        matches([post.email.from.name, post.email.from.email, post.email.subject, post.summary.headline, post.email.body],
                tokens: tokens)
    }

    static func matches(_ person: Person, tokens: [String]) -> Bool {
        matches([person.name, person.email], tokens: tokens)
    }

    static func matches(_ group: HomeDigest.OrganizationGroup, tokens: [String]) -> Bool {
        matches([group.name, group.domain ?? ""] + group.senders.map(\.address), tokens: tokens)
    }
}
