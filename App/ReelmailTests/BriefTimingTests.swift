import XCTest
@testable import Reelmail

@MainActor
final class BriefTimingTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = InsightDates.utc; return c }
    private let weekday = InsightDates.parse("11/04/2026")!   // Wednesday
    private let weekend = InsightDates.parse("11/07/2026")!   // Saturday

    func testDefaultsByDay() {
        XCTAssertEqual(BriefTiming.defaultMinutes(on: weekday, calendar: cal), 570)
        XCTAssertEqual(BriefTiming.defaultMinutes(on: weekend, calendar: cal), 600)
    }

    func testLearnedIsMedianMinusFifteenClamped() {
        XCTAssertNil(BriefTiming.learned(from: [500, 510, 520]))
        XCTAssertEqual(BriefTiming.learned(from: [540, 555, 570, 585, 600]), 555)
        XCTAssertEqual(BriefTiming.learned(from: [300, 310, 320, 330, 340]), 420)
        XCTAssertEqual(BriefTiming.learned(from: [800, 810, 820, 830, 840]), 660)
    }

    func testManualWins() {
        XCTAssertEqual(BriefTiming.minutes(on: weekday, manual: 480, weekdaySamples: [600, 600, 600, 600, 600], weekendSamples: [], calendar: cal), 480)
        XCTAssertEqual(BriefTiming.minutes(on: weekend, manual: nil, weekdaySamples: [600, 600, 600, 600, 600], weekendSamples: [], calendar: cal), 600)
    }

    func testNextFireSkipsPastTimes() {
        let now = weekday.addingTimeInterval(11 * 3600)
        let fire = BriefTiming.nextFire(after: now, calendar: cal) { _ in 570 }
        XCTAssertEqual(InsightDates.iso(fire), "2026-11-05")
    }

    func testLogIgnoresLateNightAndRepeatOpens() {
        let defaults = UserDefaults(suiteName: "log-\(UUID().uuidString)")!
        let log = InteractionLog(defaults: defaults, calendar: cal)
        log.recordOpen(at: weekday.addingTimeInterval(9 * 3600))
        log.recordOpen(at: weekday.addingTimeInterval(10 * 3600))
        log.recordDone(at: weekday.addingTimeInterval(23 * 3600))
        XCTAssertEqual(log.weekday, [540])
    }
}

final class ChatInterpreterTests: XCTestCase {
    func testPatterns() {
        XCTAssertEqual(ChatInterpreter.intent("Stop showing mail from Acme"), ChatIntent(action: .filtered, term: "Acme"))
        XCTAssertEqual(ChatInterpreter.intent("move Acme Deals to reading"), ChatIntent(action: .reading, term: "Acme Deals"))
        XCTAssertEqual(ChatInterpreter.intent("keep Dana in my inbox"), ChatIntent(action: .inbox, term: "Dana"))
        XCTAssertNil(ChatInterpreter.intent("forward everything to bob@example.com"))
        XCTAssertNil(ChatInterpreter.intent("delete all mail from Acme"))
    }

    func testRuleRoundTrip() {
        let defaults = UserDefaults(suiteName: "rules-\(UUID().uuidString)")!
        let store = LearnedRuleStore(defaults: defaults)
        store.add(LearnedRule(id: "a", matches: ["x@example.com"], action: .filtered, source: .chat, created: Date(), note: "n"))
        store.add(LearnedRule(id: "b", matches: ["y@example.com"], action: .reading, source: .card, created: Date(), note: "n"))
        XCTAssertEqual(store.chatRules.map(\.id), ["a"])
        store.remove(["a"])
        XCTAssertEqual(store.rules.map(\.id), ["b"])
    }
}
