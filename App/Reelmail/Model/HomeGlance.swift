import Foundation

/// The cards under To do on Home: one big fact each, a small label above and one line below, sorted by urgency.
/// A card with nothing to say is left out. Pure, so it is tested.
struct GlanceCard: Equatable, Identifiable {
    enum Kind: String { case comingUp, money, kids, energy, earlier, organizations }
    var kind: Kind
    var label: String
    var headline: String
    var detail: String
    /// A real problem (a failed payment): amber with a warning mark.
    var warning = false
    /// Lower comes first.
    var urgency: Int
    var id: String { kind.rawValue }
}

enum HomeGlance {
    struct Next: Equatable { var date: Date; var hasTime: Bool; var title: String }
    struct DueBill: Equatable { var payee: String; var amount: Double?; var dueOn: Date? }

    static func cards(next: Next?, thisWeek: Int,
                      openBills: [DueBill], paymentProblem: String?,
                      kidsCount: Int, latestKid: (name: String, subject: String)?,
                      energyPerDay: Double?, energyChange: Double?,
                      earlier: Int, organizations: [(name: String, count: Int)],
                      now: Date, calendar: Calendar = .current) -> [GlanceCard] {
        var out: [GlanceCard] = []
        if let next {
            let soon = next.date.timeIntervalSince(now) < 2 * 86_400
            out.append(GlanceCard(kind: .comingUp, label: thisWeek > 1 ? "Next of \(thisWeek) this week" : "Next date",
                                  headline: dayLabel(next.date, hasTime: next.hasTime, now: now, calendar: calendar),
                                  detail: next.title, urgency: soon ? 1 : 4))
        }
        if let paymentProblem {
            out.append(GlanceCard(kind: .money, label: "Money", headline: "Problem", detail: "Payment problem: \(paymentProblem)",
                                  warning: true, urgency: 0))
        } else if !openBills.isEmpty {
            let next = openBills.filter { $0.dueOn != nil }.min { $0.dueOn! < $1.dueOn! } ?? openBills[0]
            var detail = "Next: \(next.payee)"
            if let due = next.dueOn { detail += ", " + dayLabel(due, hasTime: false, now: now, calendar: calendar) }
            let dueSoon = next.dueOn.map { $0.timeIntervalSince(now) < 3 * 86_400 } ?? false
            out.append(GlanceCard(kind: .money, label: "Bills", headline: "\(openBills.count) due", detail: detail, urgency: dueSoon ? 2 : 5))
        }
        if kidsCount > 0 {
            out.append(GlanceCard(kind: .kids, label: "Kids · \(kidsCount) in mail", headline: latestKid?.name ?? "\(kidsCount)",
                                  detail: latestKid?.subject ?? "School and activities", urgency: 3))
        }
        if let perDay = energyPerDay {
            var detail = "Last month"
            if let change = energyChange, abs(change) >= 0.01 {
                detail = String(format: "%@ $%.2f a day vs the month before", change < 0 ? "Down" : "Up", abs(change))
            }
            out.append(GlanceCard(kind: .energy, label: "Energy", headline: String(format: "$%.2f/day", perDay), detail: detail, urgency: 6))
        }
        if earlier > 0 {
            out.append(GlanceCard(kind: .earlier, label: "Older mail", headline: "\(earlier)", detail: "Older than 2 weeks", urgency: 7))
        }
        if !organizations.isEmpty {
            let names = organizations.prefix(3).map(\.name).joined(separator: ", ")
            out.append(GlanceCard(kind: .organizations, label: "Organizations", headline: "\(organizations.reduce(0) { $0 + $1.count })",
                                  detail: names + (organizations.count > 3 ? "\u{2026}" : ""), urgency: 8))
        }
        return out.sorted { $0.urgency < $1.urgency }
    }

    /// "Today 6 PM", "Tomorrow", "Thu 6 PM", "Nov 20".
    static func dayLabel(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        var day: String
        if calendar.isDate(date, inSameDayAs: now) { day = "Today" }
        else if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: t) { day = "Tomorrow" }
        else if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { day = "Yesterday" }
        // A weekday name only for the days ahead; a past date reads as a date ("Oct 11"), never "Sun".
        else if date > now, date.timeIntervalSince(now) < 6 * 86_400 { f.dateFormat = "EEE"; day = f.string(from: date) }
        else { f.dateFormat = "MMM d"; day = f.string(from: date) }
        guard hasTime else { return day }
        f.dateFormat = calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        return day + " " + f.string(from: date)
    }
}
