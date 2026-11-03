import XCTest
@testable import Reelmail

final class MailDatesTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// Sent (and read) on Monday, Nov 2, 2026.
    private func found(_ text: String, sent: Date? = nil, now: Date? = nil) -> [MailDate] {
        let s = sent ?? date(2026, 11, 2, 9)
        return MailDates.extract(text: text, sent: s, now: now ?? s, calendar: calendar)
    }

    func testMonthAndDayForms() {
        XCTAssertEqual(found("Pickup is Nov 7.").map(\.start), [date(2026, 11, 7)])
        XCTAssertEqual(found("Pickup is November 7th.").map(\.start), [date(2026, 11, 7)])
        XCTAssertEqual(found("Pickup is Nov. 7 at 9 p.m.").map(\.start), [date(2026, 11, 7, 21)])
        XCTAssertEqual(found("Due Dec 1, 2026.").map(\.start), [date(2026, 12, 1)])
    }

    func testNumericForms() {
        XCTAssertEqual(found("Due 11/7.").map(\.start), [date(2026, 11, 7)])
        XCTAssertEqual(found("Due 11/7/26.").map(\.start), [date(2026, 11, 7)])
        XCTAssertEqual(found("Mix 1/2 cup of flour.").count, 0, "1/2 is Jan 2, which is long past and next year is out of range")
    }

    func testInvalidDaysAreSkipped() {
        XCTAssertTrue(found("Party on Feb 31.").isEmpty)
        XCTAssertTrue(found("Party on 13/40.").isEmpty)
    }

    func testWeekdaysAreRelativeToTheSentDay() {
        XCTAssertEqual(found("Game Sunday at 9:00 PM.").map(\.start), [date(2026, 11, 8, 21)])
        // Sent on Saturday, Nov 7: Sunday is the next day.
        let saturday = date(2026, 11, 7, 10)
        XCTAssertEqual(found("See you Sunday.", sent: saturday).map(\.start), [date(2026, 11, 8)])
        // Sent on a Sunday: "Sunday" is the following week.
        XCTAssertEqual(found("See you Sunday.", sent: date(2026, 11, 8, 10)).map(\.start), [date(2026, 11, 15)])
    }

    func testThisAndNext() {
        XCTAssertEqual(found("Meet this Tuesday.").map(\.start), [date(2026, 11, 3)])
        XCTAssertEqual(found("Meet next Tuesday.").map(\.start), [date(2026, 11, 10)])
        // "next" adds a week when the day is still ahead in the sent week (Saturday Nov 7 is this week).
        XCTAssertEqual(found("Meet next Saturday.").map(\.start), [date(2026, 11, 14)])
    }

    func testRelativeDays() {
        XCTAssertEqual(found("Tomorrow at 8am.").map(\.start), [date(2026, 11, 3, 8)])
        XCTAssertEqual(found("Tonight at 7pm.").map(\.start), [date(2026, 11, 2, 19)])
        XCTAssertEqual(found("Today at noon.").map(\.start), [date(2026, 11, 2, 12)])
    }

    func testYearRollover() {
        let sent = date(2026, 12, 28, 9)
        XCTAssertEqual(found("Back on Jan 3.", sent: sent).map(\.start), [date(2027, 1, 3)])
    }

    func testTimeAttachesOnlyInTheSameSentence() {
        let dates = found("Game Sunday. Doors open at 6 PM.")
        XCTAssertEqual(dates.map(\.start), [date(2026, 11, 8)])
        XCTAssertEqual(dates.map(\.hasTime), [false])
    }

    func testTimeForms() {
        XCTAssertEqual(found("Nov 7, 6-8 PM.").map(\.start), [date(2026, 11, 7, 18)])
        XCTAssertEqual(found("Nov 7 at 9pm.").map(\.start), [date(2026, 11, 7, 21)])
        XCTAssertEqual(found("Nov 7 at 9:30 AM.").map(\.start), [date(2026, 11, 7, 9, 30)])
        XCTAssertEqual(found("Nov 7 at noon.").map(\.start), [date(2026, 11, 7, 12)])
        XCTAssertEqual(found("Nov 7 at 14:30.").map(\.start), [date(2026, 11, 7, 14, 30)])
        XCTAssertEqual(found("Nov 7 is fine, I am free.").map(\.hasTime), [false], "\"I am\" is not a time")
    }

    func testWindow() {
        XCTAssertTrue(found("It was Oct 25.", sent: date(2026, 10, 20, 9), now: date(2026, 11, 2, 9)).isEmpty, "already past")
        XCTAssertEqual(found("Feb 20.").count, 1, "about 110 days ahead is kept")
        XCTAssertTrue(found("Mar 15.").isEmpty, "more than 120 days ahead")
        XCTAssertEqual(found("Today.", sent: date(2026, 11, 2, 9), now: date(2026, 11, 2, 20)).count, 1, "today counts from the start of the day")
    }

    func testSortedAndDeduplicated() {
        let dates = found("Nov 9 and Nov 7. Again Nov 7.")
        XCTAssertEqual(dates.map(\.start), [date(2026, 11, 7), date(2026, 11, 9)])
    }

    private func mail(subject: String = "Hi", body: String) -> Email {
        Email(id: "m", threadId: "t", from: Person(id: "a", name: "Dana", email: "dana@x.example", hue: 0.2), to: ["pat@lovely.example"],
              subject: subject, date: date(2026, 11, 2, 9), body: body)
    }

    func testReceiptsAreSkipped() {
        XCTAssertTrue(MailDates.extract(mail(subject: "Your receipt", body: "Paid on Wednesday (11/4)."), now: date(2026, 11, 2, 9), calendar: calendar).isEmpty)
    }

    func testQuotedRepliesAreSkippedButSubjectCounts() {
        let quoted = mail(body: "Sounds good.\n\nOn Mon, Nov 2, 2026 at 3:00 PM Dana <dana@x.example> wrote:\n> Game Nov 8")
        XCTAssertTrue(MailDates.extract(quoted, now: date(2026, 11, 2, 9), calendar: calendar).isEmpty)
        let subject = mail(subject: "Game Nov 8 at 9 PM", body: "See you there.")
        XCTAssertEqual(MailDates.extract(subject, now: date(2026, 11, 2, 9), calendar: calendar).map(\.start), [date(2026, 11, 8, 21)])
    }
}
