import Foundation

/// Home round 5 (owner, Nov 9): things to do are Today steps; things to know are this short paragraph, written
/// fresh each time. Each sentence names one area, and the named words open its page. At most five sentences,
/// most useful first. Pure, so it is tested.
enum HomeAlso {
    /// A piece of a sentence; `link` is a HomeAlso.Link key when the words open a page.
    struct Part: Equatable {
        var text: String
        var link: Link? = nil
    }

    enum Link: String, CaseIterable {
        case kids, money, energy, later, todo, notes, promises, waitingOnThem, comingUp
    }

    struct Inputs {
        var kidNext: KidNext?
        var hasKids = false
        /// Dollars a day last month, and the change against the month before.
        var energy: (perDay: Double, change: Double?)?
        /// Open bills with a due date, not already a Today step.
        var otherBills: [(payee: String, due: Date)] = []
        var tracksBills = false
        var billProblem: String?
        var datesThisWeek = 0
        var todo = 0
        var notes = 0
        var promises = 0
        var waitingOnThem = 0
        var later = 0
    }

    static let maxSentences = 5

    static func sentences(_ i: Inputs, now: Date, calendar: Calendar = .current) -> [[Part]] {
        var out: [[Part]] = []
        if let p = i.billProblem {
            out.append([Part(text: "Bills", link: .money), Part(text: ": \(p) reports a payment problem.")])
        }
        if let n = i.kidNext {
            out.append([Part(text: "Next for \(n.kid): "), Part(text: n.what, link: .kids), Part(text: ", \(n.when).")])
        } else if i.datesThisWeek > 0 {
            out.append([Part(text: "\(i.datesThisWeek) date\(i.datesThisWeek == 1 ? "" : "s") this week", link: .comingUp), Part(text: " in your mail.")])
        }
        if i.billProblem == nil, i.tracksBills {
            let month = i.otherBills.filter { $0.due >= calendar.startOfDay(for: now) && $0.due.timeIntervalSince(now) < 31 * 86_400 }
                .sorted { $0.due < $1.due }
            if let next = month.first {
                let more = month.count == 1 ? "1 more bill" : "\(month.count) more bills"
                out.append([Part(text: "Bills", link: .money),
                            Part(text: ": \(more) this month, next \(next.payee) \(HomeGlance.dayLabel(next.due, hasTime: false, now: now, calendar: calendar)).")])
            } else {
                out.append([Part(text: "Bills", link: .money), Part(text: ": nothing else due this month.")])
            }
        }
        if let e = i.energy {
            var s = String(format: " is $%.2f a day", e.perDay)
            if let c = e.change, abs(c) >= 0.05 { s += String(format: ", %@ $%.2f from the month before", c < 0 ? "down" : "up", abs(c)) }
            out.append([Part(text: "Energy", link: .energy), Part(text: s + ".")])
        }
        if i.waitingOnThem > 0 || i.promises > 0 {
            var parts: [Part] = []
            if i.waitingOnThem > 0 {
                parts += [Part(text: "You're waiting on "), Part(text: count(i.waitingOnThem, "reply", "replies"), link: .waitingOnThem)]
            }
            if i.promises > 0 {
                parts += [Part(text: parts.isEmpty ? "You said you'd do " : ", and you said you'd do "),
                          Part(text: count(i.promises, "thing", "things"), link: .promises)]
            }
            parts.append(Part(text: "."))
            out.append(parts)
        }
        if i.todo > 0 || i.later > 0 || i.notes > 0 {
            var bits: [[Part]] = []
            if i.todo > 0 { bits.append([Part(text: count(i.todo, "email", "emails") + " to do", link: .todo)]) }
            if i.later > 0 { bits.append([Part(text: "\(i.later) in Later", link: .later)]) }
            if i.notes > 0 { bits.append([Part(text: count(i.notes, "note", "notes") + " to yourself", link: .notes)]) }
            var parts: [Part] = []
            for (n, b) in bits.enumerated() {
                if n > 0 { parts.append(Part(text: n == bits.count - 1 ? (bits.count > 2 ? ", and " : " and ") : ", ")) }
                parts += b
            }
            if let first = parts.first { parts[0].text = first.text.prefix(1).uppercased() + first.text.dropFirst() }
            parts.append(Part(text: "."))
            out.append(parts)
        }
        return Array(out.prefix(maxSentences))
    }

    static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    /// The paragraph as plain text, for tests and VoiceOver.
    static func plain(_ sentences: [[Part]]) -> String { sentences.map { $0.map(\.text).joined() }.joined(separator: " ") }
}
