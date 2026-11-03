import XCTest
@testable import Reelmail

final class MorningBriefTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    private func post(_ id: String, name: String, subject: String = "Hello") -> Post {
        let person = Person(id: "\(id)@x.example", name: name, email: "\(id)@x.example", hue: 0.3)
        let email = Email(id: id, threadId: id, from: person, to: ["pat@lovely.example"], subject: subject, date: date(2), body: "Body text.")
        return Post(email: email, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: email)))
    }
    private func entry(_ p: Post, at start: Date, time: Bool = true) -> ComingUp.Entry {
        ComingUp.Entry(post: p, date: MailDate(start: start, hasTime: time, phrase: "x", sentence: "x"))
    }
    private func make(waiting: [Post] = [], todo: Int = 0, promises: Int = 0, today: [ComingUp.Entry] = [], back: Int = 0, names: Bool = false) -> MorningBrief? {
        MorningBrief.make(waiting: waiting, todo: todo, promises: promises, today: today, backFromLater: back, showNames: names, calendar: calendar)
    }

    func testNilWhenEverythingIsZero() { XCTAssertNil(make()) }

    func testCountsOnlyByDefault() {
        let brief = make(waiting: [post("a", name: "Dana Brooks"), post("b", name: "Sam Lee")], todo: 5, today: [entry(post("c", name: "Rink"), at: date(3, 21))])
        XCTAssertEqual(brief?.title, "Good morning")
        XCTAssertEqual(brief?.body, "2 waiting on you \u{00B7} 5 to do \u{00B7} 1 today")
        XCTAssertFalse(brief?.body.contains("Dana") ?? true, "no names on the lock screen by default")
    }

    func testOrderAndThreePartCap() {
        let brief = make(waiting: [post("a", name: "Dana Brooks")], todo: 5, promises: 2, today: [entry(post("c", name: "Rink"), at: date(3, 21))], back: 1)
        XCTAssertEqual(brief?.body, "1 waiting on you \u{00B7} 2 things you said you would do \u{00B7} 5 to do")
    }

    func testBackFromLaterOnlyWhenThereIsRoom() {
        XCTAssertEqual(make(todo: 3, back: 1)?.body, "3 to do \u{00B7} 1 back from Later")
        XCTAssertEqual(make(back: 2)?.body, "2 back from Later")
    }

    func testSingularAndPlural() {
        XCTAssertEqual(make(promises: 1)?.body, "1 thing you said you would do")
        XCTAssertEqual(make(promises: 3)?.body, "3 things you said you would do")
    }

    func testNameVariants() {
        let one = make(waiting: [post("a", name: "Dana Brooks")], names: true)
        XCTAssertEqual(one?.body, "Dana is waiting on you")
        let two = make(waiting: [post("a", name: "Dana Brooks"), post("b", name: "Sam Lee")], names: true)
        XCTAssertEqual(two?.body, "Dana and Sam are waiting on you")
        let four = make(waiting: [post("a", name: "Dana Brooks"), post("b", name: "Sam Lee"), post("c", name: "Ann Fox"), post("d", name: "Bo Reed")], names: true)
        XCTAssertEqual(four?.body, "Dana, Sam and 2 others are waiting on you")
        let repeated = make(waiting: [post("a", name: "Dana Brooks"), post("a", name: "Dana Brooks")], names: true)
        XCTAssertEqual(repeated?.body, "Dana is waiting on you", "one person with two messages is one person")
    }

    func testTodayNameIsTrimmedToTwentyFourCharacters() {
        let long = post("c", name: "Rink", subject: "Spring league championship banquet and awards")
        let text = MorningBrief.todayNames([entry(long, at: date(3, 21))], calendar: calendar)
        XCTAssertTrue(text.hasPrefix("Today: "))
        XCTAssertTrue(text.hasSuffix(" 9 PM"))
        let subject = text.dropFirst("Today: ".count).dropLast(" 9 PM".count)
        XCTAssertLessThanOrEqual(subject.count, MorningBrief.subjectLimit)
        let short = MorningBrief.todayNames([entry(post("d", name: "Rink", subject: "Game"), at: date(3, 21)), entry(post("e", name: "Rink"), at: date(3, 22))], calendar: calendar)
        XCTAssertEqual(short, "Today: Game 9 PM and 1 more")
    }

    func testNoEmDashOrExclamationAnywhere() {
        let sample = [
            make(waiting: [post("a", name: "Dana Brooks")], todo: 5, promises: 1, today: [entry(post("c", name: "Rink", subject: "Game \u{2014} finals"), at: date(3, 21))], back: 1, names: true),
            make(waiting: [post("a", name: "Dana Brooks")], todo: 5, promises: 1, today: [entry(post("c", name: "Rink"), at: date(3, 21))], back: 1),
        ]
        for brief in sample.compactMap({ $0 }) {
            XCTAssertFalse((brief.title + brief.body).contains("\u{2014}"), brief.body)
            XCTAssertFalse((brief.title + brief.body).contains("!"), brief.body)
        }
    }

    func testNextFire() {
        XCTAssertEqual(MorningBrief.nextFire(minutes: 450, after: date(3, 6, 0), calendar: calendar), date(3, 7, 30), "still ahead today")
        XCTAssertEqual(MorningBrief.nextFire(minutes: 450, after: date(3, 8, 0), calendar: calendar), date(4, 7, 30), "already past, so tomorrow")
    }
}
