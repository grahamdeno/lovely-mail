import XCTest
@testable import Reelmail

/// Skipped three times (owner, Nov 16, 2026). All mail is fictional.
final class SkipNudgeTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// Monday, Nov 16, 2026, 9 AM New York.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))! }

    private func day(_ m: Int, _ d: Int, _ h: Int = 8) -> Date { calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))! }

    private func msg(person: Bool = false, ask: String? = nil, text: String = "", subject: String = "Hello",
                     health: Bool = false, section: FeedSection = .updates) -> SessionMessage {
        SessionMessage(id: "m", threadId: "t", fromName: "Dana Whitfield", fromAddress: "dana@harborpta.example",
                       subject: subject, date: now, text: text, section: section, category: .updates, isPerson: person,
                       ask: ask, isHealth: health, isFirstTimeSender: false, asksForAction: false, hasDates: false)
    }

    private let hero = SessionHero(label: "From", value: "Dana")

    // MARK: Counting

    func testCountsOncePerSessionAndAsksAtThree() {
        var m = SkipMemory()
        m.recordSkip("a", sender: "Dana@HarborPTA.example", session: "s1", now: now)
        m.recordSkip("a", sender: "dana@harborpta.example", session: "s1", now: now)
        XCTAssertEqual(m.count("a"), 1, "round the skipped ones again in one session counts once")
        m.recordSkip("a", sender: "dana@harborpta.example", session: "s2", now: now)
        XCTAssertFalse(m.shouldAsk("a"))
        m.recordSkip("a", sender: "dana@harborpta.example", session: "s3", now: now)
        XCTAssertTrue(m.shouldAsk("a"))
        XCTAssertEqual(m.senders["dana@harborpta.example"], 3)
    }

    func testKeepShowingWaitsThreeMoreAndUndoTakesOneBack() {
        var m = SkipMemory()
        for s in ["s1", "s2", "s3"] { m.recordSkip("a", sender: "x@y.example", session: s, now: now) }
        m.keepShowing("a")
        XCTAssertFalse(m.shouldAsk("a"))
        for s in ["s4", "s5"] { m.recordSkip("a", sender: "x@y.example", session: s, now: now) }
        XCTAssertFalse(m.shouldAsk("a"))
        m.recordSkip("a", sender: "x@y.example", session: "s6", now: now)
        XCTAssertTrue(m.shouldAsk("a"))
        m.undoSkip("a", sender: "x@y.example", session: "s6")
        XCTAssertEqual(m.count("a"), 5)
        XCTAssertFalse(m.shouldAsk("a"))
    }

    func testPruneAndForget() {
        var m = SkipMemory()
        m.recordSkip("a", sender: "x@y.example", session: "s1", now: now)
        m.recordSkip("b", sender: "x@y.example", session: "s1", now: now)
        m.prune(keeping: ["a"])
        XCTAssertEqual(m.count("b"), 0)
        m.forget("a")
        XCTAssertEqual(m.count("a"), 0)
        XCTAssertEqual(m.senders["x@y.example"], 2, "sender history stays")
    }

    func testSavesPerAccount() {
        let defaults = UserDefaults(suiteName: "SkipNudgeTests")!
        defaults.removePersistentDomain(forName: "SkipNudgeTests")
        var m = SkipMemory()
        m.recordSkip("a", sender: "x@y.example", session: "s1", now: now)
        m.save(account: "Owner@Example.com", defaults: defaults)
        XCTAssertEqual(SkipMemory.load(account: "owner@example.com", defaults: defaults), m)
        XCTAssertEqual(SkipMemory.load(account: "other@example.com", defaults: defaults), SkipMemory())
    }

    // MARK: What it says, by kind

    func testPersonAskingGetsHelpReplying() {
        let n = SkipNudge.make(msg(person: true, ask: "Can you take a shift?"), count: 3, newsletter: false, hero: hero, dates: [], now: now, calendar: calendar)
        XCTAssertEqual(n.kind, .person)
        XCTAssertEqual(n.title, "Skipped 3 times")
        XCTAssertTrue(n.line.hasPrefix("Dana is waiting"))
        XCTAssertEqual(n.placeholder, "Help me reply\u{2026}")
    }

    func testBillAndNewsletterAndHealth() {
        let bill = SkipNudge.make(msg(text: "Your balance due is $142.18."), count: 3, newsletter: false, hero: hero, dates: [], now: now, calendar: calendar)
        XCTAssertEqual(bill.kind, .bill)
        let news = SkipNudge.make(msg(section: .reading), count: 4, newsletter: true, hero: hero, dates: [], now: now, calendar: calendar)
        XCTAssertEqual(news.kind, .newsletter)
        XCTAssertTrue(news.offersRule)
        XCTAssertEqual(news.title, "Skipped 4 times")
        let health = SkipNudge.make(msg(text: "Your balance due is $40.", health: true), count: 3, newsletter: false, hero: hero, dates: [], now: now, calendar: calendar)
        XCTAssertEqual(health.kind, .health)
        XCTAssertNil(health.placeholder, "no field: Lovely doesn't read health mail to help with it")
    }

    // MARK: Dates offered

    func testOptionsIncludeTheDayBeforeAFarDate() {
        let opts = SkipNudge.options(now: now, deadline: day(11, 25, 12), bill: false, calendar: calendar)
        XCTAssertEqual(opts.map(\.title).first, "Tomorrow")
        XCTAssertEqual(opts[0].date, day(11, 17))
        XCTAssertEqual(opts[1].title, "Saturday")
        XCTAssertEqual(opts[1].date, day(11, 21, 9))
        XCTAssertEqual(opts.last?.date, day(11, 24))
        XCTAssertEqual(opts.last?.title, "Tue, Nov 24 \u{00B7} the day before")
        XCTAssertTrue(opts.last?.fromEmail ?? false)
    }

    func testNoDayBeforeWhenTheDateIsClose() {
        let opts = SkipNudge.options(now: now, deadline: day(11, 18, 12), bill: true, calendar: calendar)
        XCTAssertFalse(opts.contains { $0.fromEmail })
    }

    // MARK: Reading what he said

    func testHolidaysAndPhrases() {
        XCTAssertEqual(SkipDateParser.parse("Remind me after Thanksgiving", now: now, calendar: calendar), day(11, 30))
        XCTAssertEqual(SkipDateParser.parse("before thanksgiving", now: now, calendar: calendar), day(11, 24))
        XCTAssertEqual(SkipDateParser.parse("tomorrow", now: now, calendar: calendar), day(11, 17))
        XCTAssertEqual(SkipDateParser.parse("next week", now: now, calendar: calendar), day(11, 23))
        XCTAssertEqual(SkipDateParser.parse("this weekend", now: now, calendar: calendar), day(11, 21, 9))
        XCTAssertEqual(SkipDateParser.parse("in two weeks", now: now, calendar: calendar), day(11, 30))
        XCTAssertEqual(SkipDateParser.parse("hide it till Friday", now: now, calendar: calendar), day(11, 20))
        XCTAssertEqual(SkipDateParser.parse("after Christmas", now: now, calendar: calendar), day(12, 26))
        XCTAssertEqual(SkipDateParser.parse("next month", now: now, calendar: calendar), day(12, 1))
    }

    func testRepliesAreNotDates() {
        XCTAssertNil(SkipDateParser.parse("Tell her I'll take setup on Friday", now: now, calendar: calendar))
        XCTAssertNil(SkipDateParser.parse("Help me reply", now: now, calendar: calendar))
        XCTAssertNil(SkipDateParser.parse("What does she need from me?", now: now, calendar: calendar))
    }

    func testThanksgivingIsTheFourthThursday() {
        let t = SkipDateParser.thanksgiving(after: now, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: t), 26)
        XCTAssertEqual(calendar.component(.weekday, from: t), 5)
    }
}
