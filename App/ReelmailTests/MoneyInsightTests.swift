import XCTest
@testable import Reelmail

final class MoneyInsightTests: XCTestCase {
    private let today = InsightDates.parse("11/04/2026")!

    private func bill(_ id: String, _ kind: Bill.Kind, domain: String = "examplepower.com", posted: String, due: String? = nil,
                      amount: Double? = 50, problem: Bool = false) -> Bill {
        Bill(id: id, kind: kind, payee: "Example Power", domain: domain, amount: amount, dueOn: due.flatMap(InsightDates.parse),
             postedOn: InsightDates.parse(posted)!, problem: problem, lines: [])
    }

    func testPaymentClosesEarlierStatement() {
        var store = InsightStore()
        store.add(.bill(bill("s1", .statement, posted: "10/10/2026", due: "11/01/2026")))
        XCTAssertEqual(MoneyInsights.summary(store, households: [], today: today).households[0].open.count, 1)
        store.add(.bill(bill("p1", .payment, posted: "10/28/2026")))
        let s = MoneyInsights.summary(store, households: [], today: today)
        XCTAssertEqual(s.households[0].open.count, 0)
        XCTAssertEqual(s.households[0].recentPayments.count, 1)
    }

    func testAlarmNeedsRecentProblemWithoutLaterPayment() {
        var store = InsightStore()
        store.add(.bill(bill("a1", .statement, posted: "10/30/2026", problem: true)))
        XCTAssertEqual(MoneyInsights.alarms(store, today: today).map(\.id), ["a1"])
        store.add(.bill(bill("p2", .payment, posted: "11/02/2026")))
        XCTAssertTrue(MoneyInsights.alarms(store, today: today).isEmpty)
        var old = InsightStore()
        old.add(.bill(bill("a0", .statement, posted: "09/01/2026", problem: true)))
        XCTAssertTrue(MoneyInsights.alarms(old, today: today).isEmpty)
    }

    func testHouseholdsSplitByPayeeDomainAndEndDate() {
        let apartment = Household(id: "apt", name: "Apartment", endsOn: InsightDates.parse("03/31/2027"), payeeDomains: ["billing.example"])
        let home = Household(id: "home", name: "Home")
        var store = InsightStore()
        store.add(.bill(bill("b1", .statement, domain: "billing.example", posted: "10/20/2026", due: "11/10/2026")))
        store.add(.bill(bill("b2", .statement, posted: "10/21/2026", due: "11/12/2026")))
        let s = MoneyInsights.summary(store, households: [home, apartment], today: today)
        XCTAssertEqual(s.households.first { $0.household.id == "apt" }?.open.map(\.id), ["b1"])
        XCTAssertEqual(s.households.first { $0.household.id == "home" }?.open.map(\.id), ["b2"])
        XCTAssertFalse(s.households[1].ended)
        let later = MoneyInsights.summary(store, households: [home, apartment], today: InsightDates.parse("04/02/2027")!)
        XCTAssertTrue(later.households.first { $0.household.id == "apt" }!.ended)
    }

    func testAlarmAnnouncedOnce() {
        let defaults = UserDefaults(suiteName: "alarm-test-\(UUID().uuidString)")!
        let b = bill("a1", .statement, posted: "10/30/2026", problem: true)
        XCTAssertEqual(PaymentAlarm.unannounced([b], defaults: defaults).count, 1)
        PaymentAlarm.markAnnounced([b], defaults: defaults)
        XCTAssertTrue(PaymentAlarm.unannounced([b], defaults: defaults).isEmpty)
        XCTAssertFalse(PaymentAlarm.notice(for: b, showNames: true).body.contains("$"))
        XCTAssertTrue(PaymentAlarm.notice(for: b, showNames: true).body.contains("Example Power"))
        XCTAssertFalse(PaymentAlarm.notice(for: b, showNames: false).body.contains("Example Power"), "no names on the lock screen unless allowed")
    }

    func testRemindersFromOneSenderMakeOneNotice() {
        let defaults = UserDefaults(suiteName: "alarm-test-\(UUID().uuidString)")!
        let first = bill("a1", .statement, posted: "10/30/2026", problem: true)
        let reminder = bill("a2", .statement, posted: "11/01/2026", problem: true)
        XCTAssertEqual(PaymentAlarm.unannounced([reminder, first], defaults: defaults, now: today).count, 1)
        PaymentAlarm.markAnnounced([first], defaults: defaults, now: today)
        XCTAssertTrue(PaymentAlarm.unannounced([reminder], defaults: defaults, now: today).isEmpty, "same sender within 14 days")
        let other = bill("b1", .statement, domain: "examplewater.org", posted: "11/01/2026", problem: true)
        XCTAssertEqual(PaymentAlarm.unannounced([other], defaults: defaults, now: today).count, 1)
    }
}
