import Foundation

/// Bills he marked paid on the Money page (the mail never showed a payment). On this phone only.
struct MoneyPaidMarks {
    static let key = "lovely.money.markedPaid"
    var defaults: UserDefaults = .standard
    var ids: Set<String> { Set(defaults.stringArray(forKey: Self.key) ?? []) }
    func mark(_ id: String) { defaults.set(Array(ids.union([id])).sorted(), forKey: Self.key) }
    func unmark(_ id: String) { defaults.set(Array(ids.subtracting([id])).sorted(), forKey: Self.key) }
}

/// The Money page as answers, not storage: what is next, what may be unpaid, and how spending moves month to month.
/// Pure, so it is tested.
enum MoneyPlan {
    struct Month: Equatable, Identifiable {
        var start: Date
        var total: Double
        var id: Date { start }
    }

    /// The next bill still to pay: the earliest open bill due today or later.
    static func next(_ s: MoneySummary, today: Date, calendar: Calendar = .current) -> Bill? {
        let start = calendar.startOfDay(for: today)
        return s.households.filter { !$0.ended }.flatMap(\.open)
            .filter { ($0.dueOn ?? .distantFuture) >= start }
            .min { ($0.dueOn ?? .distantFuture) < ($1.dueOn ?? .distantFuture) }
    }

    /// Open bills whose due date passed with no payment in the mail: "Did you pay these?"
    static func maybeUnpaid(_ s: MoneySummary, today: Date, calendar: Calendar = .current) -> [Bill] {
        let start = calendar.startOfDay(for: today)
        return s.households.flatMap(\.open).filter { ($0.dueOn ?? .distantFuture) < start }
            .sorted { ($0.dueOn ?? .distantPast) < ($1.dueOn ?? .distantPast) }
    }

    /// Statement totals per month (by due date, else the date it arrived), the last `count` months, oldest first.
    static func months(_ bills: [Bill], today: Date, count: Int = 6, calendar: Calendar = .current) -> [Month] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: today)?.start else { return [] }
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        var totals: [Date: Double] = [:]
        for b in bills where b.kind == .statement {
            guard let amount = b.amount, let m = calendar.dateInterval(of: .month, for: b.dueOn ?? b.postedOn)?.start else { continue }
            totals[m, default: 0] += amount
        }
        return starts.map { Month(start: $0, total: totals[$0] ?? 0) }
    }

    /// "Up $12 from last month", comparing the last two full months that had bills.
    static func trend(_ months: [Month]) -> String? {
        let withBills = months.filter { $0.total > 0 }
        guard withBills.count >= 2 else { return nil }
        let last = withBills[withBills.count - 1].total, before = withBills[withBills.count - 2].total
        let diff = last - before
        if abs(diff) < 1 { return "About the same as the month before" }
        return String(format: "%@ $%.0f from the month before", diff > 0 ? "Up" : "Down", abs(diff))
    }
}
