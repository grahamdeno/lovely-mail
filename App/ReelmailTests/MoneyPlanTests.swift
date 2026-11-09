import XCTest
@testable import Reelmail

/// Fictional bills only.
final class MoneyPlanTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    private func day(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))! }
    private func bill(_ id: String, _ payee: String, _ amount: Double, due: Date?, posted: Date, kind: Bill.Kind = .statement) -> Bill {
        Bill(id: id, kind: kind, payee: payee, domain: payee.lowercased() + ".example", amount: amount, dueOn: due, postedOn: posted, problem: false, lines: [])
    }
    private func summary(_ open: [Bill]) -> MoneySummary {
        MoneySummary(households: [HouseholdBills(household: Household(id: "h", name: "Home"), ended: false, open: open, recentPayments: [])],
                     accounts: [], renewals: [], alarms: [], actionNeeded: [])
    }

    func testNextIsEarliestUpcomingAndPastOnesAreAsked() {
        let s = summary([bill("a", "Water", 40, due: day(10, 14), posted: day(10, 1)),
                         bill("b", "Power", 90, due: day(11, 30), posted: day(11, 2)),
                         bill("c", "Phone", 60, due: day(11, 20), posted: day(11, 1))])
        XCTAssertEqual(MoneyPlan.next(s, today: day(11, 9), calendar: cal)?.id, "c")
        XCTAssertEqual(MoneyPlan.maybeUnpaid(s, today: day(11, 9), calendar: cal).map(\.id), ["a"])
    }

    func testMonthsAndTrend() {
        let bills = [bill("a", "Water", 40, due: day(10, 14), posted: day(10, 1)),
                     bill("b", "Water", 52, due: day(11, 14), posted: day(11, 1)),
                     bill("p", "Water", 40, due: nil, posted: day(10, 20), kind: .payment)]
        let months = MoneyPlan.months(bills, today: day(11, 9), calendar: cal)
        XCTAssertEqual(months.count, 6)
        XCTAssertEqual(months.suffix(2).map(\.total), [40, 52])
        XCTAssertEqual(MoneyPlan.trend(months), "Up $12 from the month before")
    }

    func testMarkedPaidBillsAreNotOpen() {
        var store = InsightStore()
        store.bills = [bill("x", "Insurer", 64, due: day(10, 11), posted: day(10, 1))]
        XCTAssertEqual(MoneyInsights.summary(store, households: [], today: day(10, 20), markedPaid: []).households[0].open.count, 1)
        XCTAssertEqual(MoneyInsights.summary(store, households: [], today: day(10, 20), markedPaid: ["x"]).households[0].open.count, 0)
    }
}
