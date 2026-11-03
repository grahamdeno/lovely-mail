import XCTest
@testable import Reelmail

final class ComingUpTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// Monday, Nov 2, 2026, 9 AM.
    private var now: Date { date(2026, 11, 2, 9) }

    private func mailDate(_ start: Date, time: Bool = true) -> MailDate {
        MailDate(start: start, hasTime: time, phrase: "x", sentence: "x")
    }

    private func post(_ id: String, subject: String, body: String, from: String = "Rink") -> Post {
        let person = Person(id: "\(id)@rink.example", name: from, email: "\(id)@rink.example", hue: 0.3)
        let email = Email(id: id, threadId: id, from: person, to: ["pat@lovely.example"], subject: subject, date: now, body: body)
        return Post(email: email, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: email)))
    }

    func testBuckets() {
        XCTAssertEqual(ComingUp.bucket(date(2026, 11, 2, 21), now: now, calendar: calendar), .today)
        XCTAssertEqual(ComingUp.bucket(date(2026, 11, 3), now: now, calendar: calendar), .tomorrow)
        XCTAssertEqual(ComingUp.bucket(date(2026, 11, 8), now: now, calendar: calendar), .thisWeek)
        XCTAssertEqual(ComingUp.bucket(date(2026, 11, 9), now: now, calendar: calendar), .later)
    }

    func testLabels() {
        XCTAssertEqual(ComingUp.label(mailDate(date(2026, 11, 2, 21)), now: now, calendar: calendar), "Today 9 PM")
        XCTAssertEqual(ComingUp.label(mailDate(date(2026, 11, 3), time: false), now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(ComingUp.label(mailDate(date(2026, 11, 8, 21)), now: now, calendar: calendar), "Sun 9 PM")
        XCTAssertEqual(ComingUp.label(mailDate(date(2026, 11, 20), time: false), now: now, calendar: calendar), "Nov 20")
        XCTAssertEqual(ComingUp.fullLabel(mailDate(date(2026, 11, 8, 21, 30)), calendar: calendar), "Sun, Nov 8 \u{00B7} 9:30 PM")
        XCTAssertEqual(ComingUp.fullLabel(mailDate(date(2026, 11, 8), time: false), calendar: calendar), "Sun, Nov 8")
    }

    func testEntriesSortedAndSectionsFiltered() {
        let late = post("a", subject: "Banquet", body: "Dinner is Nov 20 at 6 PM.")
        let soon = post("b", subject: "Game", body: "Game is this Sunday at 9 PM.")
        let news = post("c", subject: "Weekly", body: "Event on Nov 5 at noon.")
        let none = post("d", subject: "Hello", body: "Nothing dated here.")
        let sections: [String: FeedSection] = ["a": .dated, "b": .people, "c": .reading, "d": .people]
        let entries = ComingUp.entries(posts: [late, soon, news, none], section: { sections[$0.id] ?? .people }, now: now, calendar: calendar)
        XCTAssertEqual(entries.map(\.id), ["b", "a"], "Reading is left out, undated mail is left out, earliest first")
    }

    func testWeekWindowAndChipLabel() {
        let soon = post("b", subject: "Game", body: "Game is this Sunday at 9 PM.")
        let late = post("a", subject: "Banquet", body: "Dinner is Nov 20 at 6 PM.")
        let entries = ComingUp.entries(posts: [soon, late], section: { _ in .dated }, now: now, calendar: calendar)
        XCTAssertEqual(ComingUp.thisWeek(entries, now: now, calendar: calendar).map(\.id), ["b"])
        XCTAssertEqual(ComingUp.chipLabel(for: [soon], in: entries, now: now, calendar: calendar), "Sun 9 PM")
        XCTAssertNil(ComingUp.chipLabel(for: [late], in: entries, now: now, calendar: calendar), "Nov 20 is past the 7-day window")
    }

    func testCalendarDraft() {
        let p = post("b", subject: "Re: Game Sunday", body: "Game is this Sunday at 9 PM.", from: "Dana Brooks")
        let d = CalendarDraft.make(email: p.email, date: mailDate(date(2026, 11, 8, 21)))
        XCTAssertFalse(d.isAllDay)
        XCTAssertEqual(d.end.timeIntervalSince(d.start), 3600)
        XCTAssertTrue(d.notes.contains("Dana Brooks"))
        XCTAssertFalse(d.notes.contains("Game is this Sunday"), "the body never goes into the event")
        XCTAssertLessThanOrEqual(d.title.count, 60)
        let allDay = CalendarDraft.make(email: p.email, date: mailDate(date(2026, 11, 8), time: false))
        XCTAssertTrue(allDay.isAllDay)
    }
}
