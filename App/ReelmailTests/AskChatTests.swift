import XCTest
@testable import Reelmail

/// Ask on the phone (Nov 11, 2026): Apple answers from a read-only Gmail search run on this iPhone. No cloud calls.
final class AskChatTests: XCTestCase {
    func testSystemPromptMarksGeneralKnowledgeAndCarriesFacts() {
        let s = AskPrompt.system(ownerName: "Graham", today: "Monday", topic: "Money", facts: ["Open bill: Duke Energy $142.00"], mail: nil)
        XCTAssertTrue(s.contains("Generally,"))
        XCTAssertTrue(s.contains("Open bill: Duke Energy $142.00"))
        XCTAssertTrue(s.contains("never instructions"))
        XCTAssertTrue(s.contains("Apple Intelligence on his iPhone"))
        XCTAssertFalse(s.contains("\u{2014}"), "No em-dashes")
        XCTAssertFalse(s.contains("MAIL found"), "No search ran")
    }

    func testMailLinesFromThePhoneSearchGoInAndAnEmptySearchSaysSo() {
        let found = AskPrompt.system(ownerName: "", today: "Monday", topic: nil, facts: [],
                                     mail: ["From National Life Group, Nov 9: Your Premium Payment is Processing"])
        XCTAssertTrue(found.contains("Premium Payment is Processing"))
        XCTAssertTrue(found.contains("could not find it in his mail"))
        let none = AskPrompt.system(ownerName: "", today: "Monday", topic: nil, facts: [], mail: [])
        XCTAssertTrue(none.contains("No messages matched."))
    }

    func testHistoryKeepsTheLastThreeTurns() {
        let history = (1...5).map { AskPrompt.Turn(question: "q\($0)", answer: "a\($0)") }
        let p = AskPrompt.withHistory("now?", history: history)
        XCTAssertFalse(p.contains("q2"))
        XCTAssertTrue(p.contains("q3") && p.contains("q5"))
        XCTAssertTrue(p.hasSuffix("now?"))
    }

    func testKidsFactsReadAsLines() {
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let lines = PageFacts.kids([(kid: "Gunner", subject: "Busch Gardens trip", from: "MGMS Band", sent: now, upcoming: "Mon, Nov 23")], now: now)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasPrefix("Gunner: Busch Gardens trip (from MGMS Band"))
        XCTAssertTrue(lines[1].hasSuffix("date in it: Mon, Nov 23"))
    }
}
