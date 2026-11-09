import XCTest
@testable import Reelmail

final class TodayPlanTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    private func day(_ d: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

    func testStepsInOrderAtMostThree() {
        var i = TodayPlan.Inputs()
        i.waiting = [("p1", "Tamara", "Contact number")]
        i.toGoThrough = 8
        i.bills = [("NC Farm Bureau", day(15)), ("Power", day(12))]
        let steps = TodayPlan.merge(saved: nil, candidates: TodayPlan.candidates(i, now: day(9, 11), calendar: cal))
        XCTAssertEqual(steps.map(\.title), ["Answer Tamara", "Go through 8 emails", "Pay Power"])
        XCTAssertEqual(steps[2].detail, "Due Thu")
        XCTAssertEqual(steps[0].postID, "p1")
    }

    func testFinishedStepsStayCheckedAndNewOnesJoin() {
        var i = TodayPlan.Inputs()
        i.waiting = [("p1", "Tamara", "x")]; i.toGoThrough = 8
        let morning = TodayPlan.merge(saved: nil, candidates: TodayPlan.candidates(i, now: day(9), calendar: cal))
        i.waiting = []; i.toGoThrough = 3
        let later = TodayPlan.merge(saved: morning, candidates: TodayPlan.candidates(i, now: day(9, 14), calendar: cal))
        XCTAssertEqual(later.map(\.done), [true, false])
        XCTAssertEqual(later[1].title, "Go through 3 emails", "Live steps refresh their numbers")
        i.toGoThrough = 0
        i.today = [("p9", "6 PM", "Info night")]
        let evening = TodayPlan.merge(saved: later, candidates: TodayPlan.candidates(i, now: day(9, 16), calendar: cal))
        XCTAssertEqual(evening.map(\.done), [true, true, false])
        XCTAssertEqual(evening.last?.title, "6 PM: Info night")
    }

    func testManyWaitingIsOneStep() {
        var i = TodayPlan.Inputs()
        i.waiting = [("a", "Sam", ""), ("b", "Kim", ""), ("c", "Lee", "")]
        let s = TodayPlan.candidates(i, now: day(9), calendar: cal)
        XCTAssertEqual(s.first?.title, "Answer 3 people")
        XCTAssertNil(s.first?.postID)
    }

    func testVagueTodayIsNotAnEvent() {
        let vague = MailDate(start: day(9), hasTime: false, phrase: "today", sentence: "so I can post your kit today")
        let real = MailDate(start: day(9, 18), hasTime: true, phrase: "today at 6 PM", sentence: "Meet today at 6 PM")
        XCTAssertTrue(ComingUp.isVagueToday(vague))
        XCTAssertFalse(ComingUp.isVagueToday(real))
    }

    func testPlanStoreIsPerDay() {
        let defaults = UserDefaults(suiteName: "TodayPlanTests")!
        defaults.removePersistentDomain(forName: "TodayPlanTests")
        let store = TodayPlanStore(account: "me@example.com", defaults: defaults)
        store.save([TodayStep(id: "session", kind: .session, title: "t", detail: "d")], day: "2026-11-09")
        XCTAssertEqual(store.load(day: "2026-11-09")?.count, 1)
        XCTAssertNil(store.load(day: "2026-11-10"))
    }
}
