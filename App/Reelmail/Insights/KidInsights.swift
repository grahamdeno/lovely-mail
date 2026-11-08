import Foundation

struct KidMail: Equatable, Identifiable {
    var id: String { post.id }
    var post: Post
    var reasons: [String]
    static func == (a: KidMail, b: KidMail) -> Bool { a.post.id == b.post.id && a.reasons == b.reasons }
}

/// Matches mail to a child by the names, school, teachers and activities the owner entered. Pure.
enum KidInsights {
    /// Words from the profile that point at this child. Short or common words are ignored.
    static func keywords(_ kid: KidProfile) -> [(term: String, label: String)] {
        var out: [(String, String)] = []
        func add(_ t: String, _ label: String) {
            let term = t.trimmingCharacters(in: .whitespaces).lowercased()
            if term.count >= 3 { out.append((term, label)) }
        }
        add(kid.name, "name")
        add(kid.school, "school")
        kid.teacherNames.forEach { add($0, "teacher") }
        kid.activities.forEach { add($0, "activity") }
        return out
    }

    static func matches(_ kid: KidProfile, sender: String, subject: String, body: String) -> [String] {
        let head = (sender + " " + subject).lowercased()
        let text = (head + " " + String(body.prefix(2_000))).lowercased()
        var reasons: [String] = []
        for (term, label) in keywords(kid) where text.contains(term) {
            let r = label == "name" ? "Names \(kid.name)" : "Mentions \(label): \(term)"
            if !reasons.contains(r) { reasons.append(r) }
        }
        return reasons
    }

    /// Mail for one child, newest first. A name match in the subject or sender counts alone; otherwise two different reasons are needed
    /// unless it is the school or a teacher.
    static func mail(for kid: KidProfile, in posts: [Post]) -> [KidMail] {
        posts.compactMap { post in
            let e = post.email
            guard !e.isFromMe, !HealthMail.isHealth(address: e.from.email, name: e.from.name, subject: e.subject) else { return nil }
            let reasons = matches(kid, sender: e.from.name + " " + e.from.email, subject: e.subject, body: e.body)
            guard !reasons.isEmpty else { return nil }
            let strong = reasons.contains { $0.hasPrefix("Names") || $0.contains("school") || $0.contains("teacher") }
            guard strong || reasons.count >= 2 else { return nil }
            return KidMail(post: post, reasons: reasons)
        }.sorted { $0.post.email.date > $1.post.email.date }
    }
}

/// Splits a long newsletter into pieces a small on-device model can read. Pure.
enum NewsletterChunker {
    static let maxCharacters = 2_500

    static func chunks(_ body: String, limit: Int = maxCharacters) -> [String] {
        let paragraphs = body.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var out: [String] = []
        var current = ""
        for p in paragraphs {
            let pieces = p.count > limit ? split(p, limit: limit) : [p]
            for piece in pieces {
                if current.isEmpty { current = piece }
                else if current.count + piece.count + 2 <= limit { current += "\n\n" + piece }
                else { out.append(current); current = piece }
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func split(_ text: String, limit: Int) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while rest.count > limit {
            let cut = rest.prefix(limit)
            let end = cut.lastIndex(of: " ") ?? cut.endIndex
            out.append(String(rest[rest.startIndex..<end]))
            rest = rest[end...].drop(while: { $0 == " " })
        }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }

    /// Items from every chunk merged, duplicates removed, at most five.
    static func merge(_ lists: [[String]], max: Int = 5) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in lists.flatMap({ $0 }) {
            let key = item.lowercased().filter { $0.isLetter || $0.isNumber }
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append(item)
            if out.count == max { break }
        }
        return out
    }
}

extension KidInsights {
    /// "Names Ava · Mentions school: oakridge elementary" reads as "Mentions Ava, Oakridge Elementary".
    static func plainReasons(_ reasons: [String]) -> String {
        var terms: [String] = []
        for r in reasons {
            let term: String
            if r.hasPrefix("Names ") { term = String(r.dropFirst("Names ".count)) }
            else if let colon = r.firstIndex(of: ":") { term = r[r.index(after: colon)...].trimmingCharacters(in: .whitespaces).capitalized }
            else { term = r }
            if !term.isEmpty, !terms.contains(term) { terms.append(term) }
        }
        return terms.isEmpty ? "" : "Mentions " + terms.joined(separator: ", ")
    }
}
