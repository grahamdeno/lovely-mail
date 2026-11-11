import XCTest
@testable import Reelmail

final class AskLovelyTests: XCTestCase {
    func testTrialAsksAfterTwoWeeksOnce() {
        let d = UserDefaults(suiteName: "ask-\(UUID().uuidString)")!
        let u = AskLovelyUsage(defaults: d)
        XCTAssertFalse(u.trialOver(), "No trial before Home shows the field")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        u.start(now: start)
        u.recordAsk(); u.recordAsk()
        XCTAssertEqual(u.count, 2)
        XCTAssertFalse(u.trialOver(now: start.addingTimeInterval(13 * 86_400)))
        XCTAssertTrue(u.trialOver(now: start.addingTimeInterval(14 * 86_400)))
        d.set(true, forKey: AskLovelyUsage.decidedKey)
        XCTAssertFalse(u.trialOver(now: start.addingTimeInterval(30 * 86_400)))
    }

    func testQuestionPromptAsksForOneSearch() {
        let p = AskPrompt.mailQuery(today: "2026-11-09")
        XCTAssertTrue(p.contains("one Gmail search query"))
        XCTAssertTrue(p.contains("2026-11-09"))
    }
}
