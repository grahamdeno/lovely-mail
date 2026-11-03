import Foundation

/// Who a reply goes to. Pure. Lovely only builds a Gmail compose link from this; the owner presses Send in Gmail.
enum ReplyRecipients {
    struct Plan: Equatable {
        var to: [String]
        var cc: [String]
        var toLine: String { to.joined(separator: ",") }
        var ccLine: String { cc.joined(separator: ",") }
    }

    private static func key(_ address: String) -> String { TriageContext.canonical(EmailPresentation.address(in: address)) }

    /// Reply: the sender only.
    static func reply(_ email: Email) -> Plan { Plan(to: [email.from.email], cc: []) }

    /// Reply all: sender first, then the original To, then the original Cc under Cc.
    /// Your own addresses never appear, and nobody appears twice (compared case-insensitively).
    static func replyAll(_ email: Email, mine: Set<String>) -> Plan {
        let me = Set(mine.map(TriageContext.canonical))
        var seen = Set<String>()
        func take(_ list: [String]) -> [String] {
            list.compactMap { raw in
                let address = EmailPresentation.address(in: raw)
                let k = key(raw)
                guard !address.isEmpty, !me.contains(k), seen.insert(k).inserted else { return nil }
                return address
            }
        }
        let to = take([email.from.email] + email.to)
        let cc = take(email.cc)
        return Plan(to: to, cc: cc)
    }

    /// People on the mail besides you and the sender, as display names, in order, without repeats.
    static func others(_ email: Email, mine: Set<String>) -> [String] {
        let me = Set(mine.map(TriageContext.canonical))
        var seen: Set<String> = [key(email.from.email)]
        return (email.to + email.cc).compactMap { raw in
            let k = key(raw)
            guard !me.contains(k), seen.insert(k).inserted else { return nil }
            let name = GmailMessageParser.person(fromHeader: raw).firstName
            return name.isEmpty ? EmailPresentation.address(in: raw) : name
        }
    }

    /// Reply all is offered when someone besides you and the sender is on the mail. Never for organization mail.
    static func offersReplyAll(_ email: Email, mine: Set<String>, organization: Bool) -> Bool {
        !organization && !others(email, mine: mine).isEmpty
    }

    /// "Sam", "Sam and Lee", "Sam, Lee and Ann", "Sam, Lee and 2 others".
    static func nameList(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        case 3: return "\(names[0]), \(names[1]) and \(names[2])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others"
        }
    }

    /// Under a group message in a conversation: "With Sam, Lee and 2 others". Nil for one-to-one mail.
    static func caption(_ email: Email, mine: Set<String>) -> String? {
        let names = others(email, mine: mine)
        return names.isEmpty ? nil : "With " + nameList(names)
    }

    /// A first name for an address: from the mail's own headers when they carry one, else the part before the @.
    static func firstName(for address: String, in email: Email) -> String {
        let k = key(address)
        if key(email.from.email) == k, !email.from.firstName.isEmpty { return email.from.firstName }
        for raw in email.to + email.cc where key(raw) == k {
            let name = GmailMessageParser.person(fromHeader: raw).firstName
            if !name.isEmpty, name != address { return name }
        }
        return address.split(separator: "@").first.map(String.init) ?? address
    }

    /// In the draft sheet: "To Dana" or "To Dana \u{00B7} Cc Sam, Lee and 2 others".
    static func summaryLine(_ plan: Plan, email: Email) -> String {
        let to = "To " + nameList(plan.to.map { firstName(for: $0, in: email) })
        guard !plan.cc.isEmpty else { return to }
        return to + " \u{00B7} Cc " + nameList(plan.cc.map { firstName(for: $0, in: email) })
    }
}
