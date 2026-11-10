import XCTest
@testable import Reelmail

final class HomeAlsoTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    private func date(_ d: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

    func testParagraphReadsLikeANote() {
        var i = HomeAlso.Inputs()
        i.kidNext = KidNext(kid: "Gunner", postID: "p", what: "Busch Gardens Trip", when: "Nov 23", start: date(23))
        i.tracksBills = true
        i.energy = (4.29, -0.31)
        i.later = 1
        let s = HomeAlso.sentences(i, now: date(9), calendar: cal)
        XCTAssertEqual(HomeAlso.plain(s),
                       "Next for Gunner: Busch Gardens Trip, Nov 23. Bills: nothing else due this month. Energy is $4.29 a day, down $0.31 from the month before. 1 in Later.")
        XCTAssertEqual(s[0].first { $0.link != nil }?.link, .kids)
    }

    func testBillsAndFollowUps() {
        var i = HomeAlso.Inputs()
        i.tracksBills = true
        i.otherBills = [("Water", date(20)), ("Duke Energy", date(18)), ("Old", date(1))]
        i.waitingOnThem = 2; i.promises = 1; i.todo = 3; i.notes = 1
        let text = HomeAlso.plain(HomeAlso.sentences(i, now: date(9), calendar: cal))
        XCTAssertTrue(text.contains("Bills: 2 more bills this month, next Duke Energy Nov 18."), text)
        XCTAssertTrue(text.contains("You're waiting on 2 replies, and you said you'd do 1 thing."), text)
        XCTAssertTrue(text.contains("3 emails to do and 1 note to yourself."), text)
    }

    func testPaymentProblemComesFirstAndNothingSaysNothing() {
        var i = HomeAlso.Inputs()
        i.billProblem = "Duke Energy"; i.tracksBills = true
        XCTAssertEqual(HomeAlso.plain(HomeAlso.sentences(i, now: date(9), calendar: cal)), "Bills: Duke Energy reports a payment problem.")
        XCTAssertTrue(HomeAlso.sentences(HomeAlso.Inputs(), now: date(9), calendar: cal).isEmpty)
    }
}
