import XCTest
@testable import Reelmail

final class HomeGlanceTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    private func date(_ d: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

    func testCardsAreOrderedByUrgencyAndEmptyOnesLeftOut() {
        let now = date(9, 11)
        let cards = HomeGlance.cards(next: .init(date: date(12, 18), hasTime: true, title: "Holly Shelter info night"), thisWeek: 2,
                                     openBills: [.init(payee: "Power", amount: 142, dueOn: date(10)), .init(payee: "Water", amount: nil, dueOn: nil)],
                                     paymentProblem: nil, kidsCount: 18, latestKid: ("Gunner", "XC meet Saturday"),
                                     energyPerDay: 4.29, energyChange: -0.31, earlier: 111, organizations: [], now: now, calendar: cal)
        XCTAssertEqual(cards.map(\.kind), [.money, .kids, .comingUp, .energy, .earlier], "Bill due tomorrow first; no organizations card")
        XCTAssertEqual(cards[0].headline, "2 due")
        XCTAssertEqual(cards[0].detail, "Next: Power, Tomorrow")
        XCTAssertEqual(cards[2].headline, "Thu 6 PM")
        XCTAssertEqual(cards[2].label, "Next of 2 this week")
        XCTAssertEqual(cards[3].headline, "$4.29/day")
        XCTAssertEqual(cards[3].detail, "Down $0.31 a day vs the month before")
    }

    func testPaymentProblemIsAWarningAndComesFirst() {
        let cards = HomeGlance.cards(next: nil, thisWeek: 0, openBills: [], paymentProblem: "Duke Energy", kidsCount: 0, latestKid: nil,
                                     energyPerDay: nil, energyChange: nil, earlier: 0, organizations: [("Apple", 2)], now: date(9), calendar: cal)
        XCTAssertEqual(cards.first?.kind, .money)
        XCTAssertTrue(cards.first?.warning ?? false)
        XCTAssertEqual(cards.last?.headline, "2")
    }

    func testDayLabels() {
        let now = date(9, 11)
        XCTAssertEqual(HomeGlance.dayLabel(date(9, 18), hasTime: true, now: now, calendar: cal), "Today 6 PM")
        XCTAssertEqual(HomeGlance.dayLabel(date(10), hasTime: false, now: now, calendar: cal), "Tomorrow")
        XCTAssertEqual(HomeGlance.dayLabel(date(20), hasTime: false, now: now, calendar: cal), "Nov 20")
    }
}
