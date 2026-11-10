import XCTest
@testable import Reelmail

final class HomeGlanceTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    private func date(_ d: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

    func testDayLabels() {
        let now = date(9, 11)
        XCTAssertEqual(HomeGlance.dayLabel(date(9, 18), hasTime: true, now: now, calendar: cal), "Today 6 PM")
        XCTAssertEqual(HomeGlance.dayLabel(date(10), hasTime: false, now: now, calendar: cal), "Tomorrow")
        XCTAssertEqual(HomeGlance.dayLabel(date(20), hasTime: false, now: now, calendar: cal), "Nov 20")
    }
}
