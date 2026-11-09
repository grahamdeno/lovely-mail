import Foundation

/// Home as a short checklist Lovely builds each day: at most three steps, in order. Only the first open step is active;
/// a step checks off by itself when its reason is gone (the person was answered, the inbox gone through, the bill paid).
/// The day's steps are remembered so finished ones stay checked; new urgent ones join while there is room. Pure, tested.
struct TodayStep: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case answer, session, bill, date }
    var id: String
    var kind: Kind
    var title: String
    var detail: String
    /// Mail to open for answer (one person) and date steps.
    var postID: String?
    var done = false
}

struct TodayPlanStore {
    var account: String
    var defaults: UserDefaults = .standard
    private var key: String { "lovely.today.plan." + account.lowercased() }

    func load(day: String) -> [TodayStep]? {
        guard let saved = defaults.dictionary(forKey: key), saved["day"] as? String == day,
              let data = saved["steps"] as? Data else { return nil }
        return try? JSONDecoder().decode([TodayStep].self, from: data)
    }

    func save(_ steps: [TodayStep], day: String) {
        defaults.set(["day": day, "steps": (try? JSONEncoder().encode(steps)) ?? Data()], forKey: key)
    }
}

enum TodayPlan {
    static let maxSteps = 3

    struct Inputs {
        var waiting: [(postID: String, name: String, about: String)] = []
        var toGoThrough = 0
        /// Bills not paid, with a due date.
        var bills: [(payee: String, due: Date, postID: String?)] = []
        /// Dates in mail that fall today.
        var today: [(postID: String, label: String, title: String)] = []
    }

    /// What deserves a step right now, most important first.
    static func candidates(_ i: Inputs, now: Date, calendar: Calendar = .current) -> [TodayStep] {
        var out: [TodayStep] = []
        if i.waiting.count == 1, let w = i.waiting.first {
            out.append(TodayStep(id: "answer", kind: .answer, title: "Answer \(w.name)", detail: w.about, postID: w.postID))
        } else if i.waiting.count > 1 {
            out.append(TodayStep(id: "answer", kind: .answer, title: "Answer \(i.waiting.count) people",
                                 detail: i.waiting.prefix(3).map(\.name).joined(separator: ", ")))
        }
        if i.toGoThrough > 0 {
            let minutes = max(1, Int((Double(i.toGoThrough) * 0.6).rounded()))
            out.append(TodayStep(id: "session", kind: .session, title: "Go through \(i.toGoThrough) email\(i.toGoThrough == 1 ? "" : "s")",
                                 detail: "About \(minutes) minute\(minutes == 1 ? "" : "s"), one decision at a time"))
        }
        for d in i.today.prefix(1) {
            out.append(TodayStep(id: "date-" + d.postID, kind: .date, title: d.label + ": " + d.title, detail: "Today", postID: d.postID))
        }
        // Due in the next 4 days or the last 3. Older ones are almost always paid already (a bill from October showed as "Due Sun").
        let soon = i.bills.filter { (-3 * 86_400 ..< 4 * 86_400).contains($0.due.timeIntervalSince(now)) }.sorted { $0.due < $1.due }
        if let bill = soon.first {
            let past = bill.due < calendar.startOfDay(for: now)
            out.append(TodayStep(id: "bill-" + bill.payee.lowercased(), kind: .bill, title: "Pay \(bill.payee)",
                                 detail: (past ? "Was due " : "Due ") + HomeGlance.dayLabel(bill.due, hasTime: false, now: now, calendar: calendar),
                                 postID: bill.postID))
        }
        return out
    }

    /// Today's steps: the saved ones (checked when their reason is gone, refreshed when not), then new candidates while
    /// there is room. Returns the steps to show and to save.
    static func merge(saved: [TodayStep]?, candidates: [TodayStep]) -> [TodayStep] {
        let live = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var steps: [TodayStep] = (saved ?? []).map { old in
            if let now = live[old.id] { return now }
            var finished = old; finished.done = true; return finished
        }
        for c in candidates where steps.filter({ !$0.done }).count < maxSteps && !steps.contains(where: { $0.id == c.id }) { steps.append(c) }
        return steps
    }
}
