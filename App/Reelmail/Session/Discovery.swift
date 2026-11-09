import Foundation

/// Proposes the owner's children and properties from their own mail, with evidence, for them to confirm in Settings.
/// Nothing is assumed: a name or address is only offered, never added on its own. Runs on the phone. Pure, so it is tested.
enum Discovery {
    struct Mail: Sendable {
        var subject: String
        var text: String
        var fromAddress: String
        var date: Date
    }

    struct Candidate: Identifiable, Equatable, Sendable {
        var name: String
        /// How many emails mention it.
        var count: Int
        /// The newest mention, so a sold home can be offered as past.
        var lastSeen: Date
        /// Closing or sale wording appeared with it.
        var looksPast: Bool = false
        var id: String { name }
    }

    static let minimumEmails = 2

    /// Words that look like names at the start of a sentence or in a greeting, never children.
    static let notNames: Set<String> = ["Dear", "Hello", "Hi", "Good", "Team", "Your", "The", "This", "That", "Our", "Mr", "Mrs", "Ms",
                                        "Dr", "Parent", "Parents", "Student", "Students", "Family", "Families", "Please", "Thank", "Thanks",
                                        "Welcome", "Reminder", "Important", "New", "School", "Class", "Grade", "Room", "Monday", "Tuesday",
                                        "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "January", "February", "March", "April",
                                        "May", "June", "July", "August", "September", "October", "November", "December", "Today", "Tomorrow",
                                        "Portal", "Council", "Body", "Success", "Services", "Center", "Account", "Information", "Pickup",
                                        "Name", "Number", "Care", "Records", "Life", "Support", "Login", "Handbook", "Directory"]

    static let kidContext = ["school", "student", "teacher", "class", "grade", "report card", "attendance", "field trip", "permission",
                             "preschool", "daycare", "childcare", "practice", "team", "coach", "band", "child", "your child", "patient portal",
                             "pediatric", "academy", "tuition", "camp"]
    static let homeContext = ["mortgage", "escrow", "utility", "electric", "water", "lease", "rent", "homeowners", "renters insurance",
                              "property", "closing", "title", "hoa", "service address", "inspection"]
    static let pastWords = ["sale of", "sold", "closing", "final docs", "cancel our policy", "no longer own"]

    /// Children: names right after "parent of", "student:", or before "'s report card"-style phrases, or a first name
    /// paired with the owner's last name, in school, childcare, activity or care mail.
    static func kids(in mails: [Mail], ownerName: String, known: [String]) -> [Candidate] {
        let parts = ownerName.split(separator: " ").map(String.init)
        let ownerFirst = parts.first ?? ""
        let last = parts.count > 1 ? parts.last! : ""
        let knownSet = Set(known.map { $0.lowercased() })
        var counts: [String: (Int, Date)] = [:]
        for m in mails {
            let text = m.subject + "\n" + String(m.text.prefix(4_000))
            guard DrawerGuesser.hasAny(text.lowercased(), kidContext) else { continue }
            var names = Set<String>()
            let patterns = [#"(?i:parents? (?:of|for)|student:?|child:?|for your child,?) ([A-Z][a-z]{2,})"#,
                            #"\b([A-Z][a-z]{2,})(?:'s|’s) (?:report card|progress|attendance|class|teacher|field trip|permission|grades|session|appointment|account|care|schedule)"#]
            for p in patterns { names.formUnion(captures(p, in: text)) }
            if !last.isEmpty {
                names.formUnion(captures(#"\b([A-Z][a-z]{2,}) (?i:"# + NSRegularExpression.escapedPattern(for: last) + #")\b"#, in: text))
            }
            for n in names where !notNames.contains(n) && n.lowercased() != ownerFirst.lowercased() && !knownSet.contains(n.lowercased()) {
                let prev = counts[n] ?? (0, .distantPast)
                counts[n] = (prev.0 + 1, max(prev.1, m.date))
            }
        }
        return counts.filter { $0.value.0 >= minimumEmails }
            .map { Candidate(name: $0.key, count: $0.value.0, lastSeen: $0.value.1) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    /// Properties: street addresses in mortgage, utility, lease, insurance and closing mail (never shipping receipts).
    /// "5206 Lone Eagle Ct" becomes "5206 Lone Eagle". Sale or closing wording marks one as likely past.
    static func properties(in mails: [Mail], known: [String], now: Date) -> [Candidate] {
        let knownSet = Set(known.map { $0.lowercased() })
        let suffix = #"(?:Drive|Dr|Court|Ct|Street|St|Avenue|Ave|Road|Rd|Lane|Ln|Way|Boulevard|Blvd|Circle|Cir|Place|Pl|Trail|Trl|Loop)"#
        let pattern = #"\b(\d{1,6} [A-Z][a-z]+(?: [A-Z][a-z]+){0,2}) "# + suffix + #"\b"#
        var found: [String: (Int, Date, Bool)] = [:]
        for m in mails {
            let text = m.subject + "\n" + String(m.text.prefix(4_000))
            let lower = text.lowercased()
            guard DrawerGuesser.hasAny(lower, homeContext), !DeliveryNotice.hasPhrase(lower) else { continue }
            let past = pastWords.contains { lower.contains($0) }
            for name in Set(captures(pattern, in: text)) where !knownSet.contains(name.lowercased()) {
                let prev = found[name] ?? (0, .distantPast, false)
                found[name] = (prev.0 + 1, max(prev.1, m.date), prev.2 || past)
            }
        }
        let sixMonths: TimeInterval = 182 * 86_400
        return found.filter { $0.value.0 >= minimumEmails }
            .map { Candidate(name: $0.key, count: $0.value.0, lastSeen: $0.value.1,
                             looksPast: $0.value.2 && now.timeIntervalSince($0.value.1) > sixMonths) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    static func captures(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : nil
        }
    }
}
