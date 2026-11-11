import XCTest
@testable import Reelmail

/// Block from the quick-ones and newsletter screens (owner, Nov 10, 2026). All mail is fictional.
@MainActor
final class SessionBlockTests: XCTestCase {
    private func item(_ id: String, from address: String) -> SessionItem {
        let m = SessionMessage(id: id, threadId: "t-" + id, fromName: "Streamer", fromAddress: address, subject: "New this week",
                               date: Date(timeIntervalSince1970: 1_794_312_000), text: "", section: .reading, category: .updates,
                               isPerson: false, ask: nil, isHealth: false, isFirstTimeSender: false, asksForAction: false, hasDates: false)
        return SessionItem(message: m, group: .reading, suggestion: .archive, drawer: nil)
    }

    func testBlockIsItsOwnFateAndNeverAMove() {
        let a = item("a", from: "news@streamer.example"), b = item("b", from: "hello@shop.example")
        let model = SessionModel(plan: SessionPlan(items: [a, b], carried: []))
        model.setBatchFate(.block, for: a)
        XCTAssertEqual(model.batchFate(a, reading: true), .block)
        XCTAssertEqual(model.ids([a, b], .block, reading: true), ["a"])
        XCTAssertEqual(model.moves([a, b], reading: true).map(\.messageID), ["b"], "a blocked row is not archived as a move")
    }

    func testBlockIsNotRememberedAsAHabit() {
        let a = item("a", from: "news@streamer.example")
        let model = SessionModel(plan: SessionPlan(items: [a], carried: []))
        model.setBatchFate(.block, for: a)
        XCTAssertTrue(model.fatesToRemember([a], reading: true).isEmpty)
        model.rememberedFates = ["news@streamer.example": .block]
        model.setBatchFate(.archive, for: a); model.batchFates[a.id] = nil
        XCTAssertEqual(model.batchFate(a, reading: true), .archive, "a remembered block never pre-selects")
    }

    func testFinishCountsBlockedAsHandled() {
        let a = item("a", from: "news@streamer.example"), b = item("b", from: "hello@shop.example")
        let model = SessionModel(plan: SessionPlan(items: [a, b], carried: []))
        model.finishReading([], blocked: ["a"])
        XCTAssertEqual(model.archived, 1)
        XCTAssertEqual(model.leftUnread.map(\.id), ["b"])
    }

    func testButtonTitleNamesTheBlocks() {
        XCTAssertEqual(SessionFateStrip.title("Archive all 0", acting: 0, blocked: 1), "Block 1 sender")
        XCTAssertEqual(SessionFateStrip.title("Archive all 2", acting: 2, blocked: 2), "Archive all 2 + block 2")
        XCTAssertEqual(SessionFateStrip.title("Do all 3", acting: 3, blocked: 0), "Do all 3")
    }
}
