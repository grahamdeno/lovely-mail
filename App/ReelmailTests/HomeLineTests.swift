import XCTest
@testable import Reelmail

/// Home 2's greeting, sentence and suggestions. All names are fictional.
final class HomeLineTests: XCTestCase {
    private func step(_ kind: TodayStep.Kind, _ title: String, _ detail: String = "", done: Bool = false) -> TodayStep {
        TodayStep(id: kind.rawValue, kind: kind, title: title, detail: detail, postID: nil, done: done)
    }

    func testGreetingByHour() {
        XCTAssertEqual(HomeLine.greeting(firstName: "Alex", hour: 8), "Good morning, Alex.")
        XCTAssertEqual(HomeLine.greeting(firstName: "Alex", hour: 13), "Good afternoon, Alex.")
        XCTAssertEqual(HomeLine.greeting(firstName: "", hour: 21), "Good evening.")
        XCTAssertEqual(HomeLine.greeting(firstName: "Alex", hour: 2), "Good evening, Alex.")
    }

    func testOnePersonWaitingThenEverythingElseCanWait() {
        let line = HomeLine.make(steps: [step(.answer, "Answer Sarah", "Dinner Saturday?")], toGoThrough: 0, firstName: "Alex", hour: 20)
        XCTAssertEqual(line.plainSentence, "Sarah is waiting on you. Everything else can wait.")
        XCTAssertEqual(line.sentence.first, HomeLine.Segment(text: "Sarah", link: .answer))
        XCTAssertEqual(line.suggestions.first, "Answer Sarah")
        XCTAssertEqual(line.suggestions.count, 3)
    }

    func testAtMostTwoThingsAndTheyAreLinked() {
        let steps = [step(.answer, "Answer 3 people"), step(.bill, "Pay Cape Fear Power", "Due Fri")]
        let line = HomeLine.make(steps: steps, toGoThrough: 6, firstName: "Alex", hour: 9)
        XCTAssertEqual(line.plainSentence, "3 people are waiting on you. Cape Fear Power is due Fri.")
        XCTAssertEqual(line.sentence.compactMap(\.link), [.answer, .bill])
        XCTAssertEqual(line.suggestions, ["Who's waiting on me?", "What needs me today?", "When is Cape Fear Power due?"])
    }

    func testOnlyMailToGoThrough() {
        let line = HomeLine.make(steps: [], toGoThrough: 1, firstName: "Alex", hour: 9)
        XCTAssertEqual(line.plainSentence, "1 email to go through. Everything else can wait.")
        XCTAssertEqual(line.sentence.first?.link, .session)
    }

    func testCaughtUpAndDoneStepsIgnored() {
        let line = HomeLine.make(steps: [step(.answer, "Answer Sarah", done: true)], toGoThrough: 0, firstName: "Alex", hour: 9)
        XCTAssertEqual(line.plainSentence, "You're all caught up.")
        XCTAssertEqual(line.suggestions, ["What needs me today?", "What did school send this week?", "Who's waiting on me?"])
    }

    func testNeedsMeQuestions() {
        XCTAssertTrue(HomeLine.isNeedsMe("What needs me today?"))
        XCTAssertFalse(HomeLine.isNeedsMe("When is Cape Fear Power due?"))
    }
}
