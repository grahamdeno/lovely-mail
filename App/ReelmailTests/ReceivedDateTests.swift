import XCTest
@testable import Reelmail

final class ReceivedDateTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private let us = Locale(identifier: "en_US")

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testTodayShowsTheTime() {
        let s = ReceivedDate.label(date(2026, 11, 12, 8, 2), now: date(2026, 11, 12, 9), calendar: cal, locale: us)
        XCTAssertTrue(s.hasPrefix("8:02"), s)
        XCTAssertTrue(s.hasSuffix("AM"), s)
    }

    func testYesterdayAndThisWeek() {
        let now = date(2026, 11, 12, 9)
        XCTAssertEqual(ReceivedDate.label(date(2026, 11, 11, 23, 50), now: now, calendar: cal, locale: us), "Yesterday")
        XCTAssertEqual(ReceivedDate.label(date(2026, 11, 9), now: now, calendar: cal, locale: us), "Monday")
    }

    func testOlderThisYearAndLastYear() {
        let now = date(2026, 11, 12, 9)
        XCTAssertEqual(ReceivedDate.label(date(2026, 11, 3), now: now, calendar: cal, locale: us), "Nov 3")
        XCTAssertEqual(ReceivedDate.label(date(2025, 12, 30), now: now, calendar: cal, locale: us), "Dec 30, 2025")
    }

    func testFullStampHasDayDateAndTime() {
        let s = ReceivedDate.full(date(2026, 11, 12, 8, 2), calendar: cal, locale: us)
        XCTAssertTrue(s.contains("Thursday"))
        XCTAssertTrue(s.contains("Nov 12, 2026"))
        XCTAssertTrue(s.contains("8:02"))
    }
}
