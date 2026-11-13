import XCTest
@testable import Reelmail

/// One workflow (owner, Nov 12, 2026): every email is a card, in group order, with no batch screens. Fictional mail.
@MainActor
final class SessionOneWorkflowTests: XCTestCase {
    private func item(_ id: String, _ group: SessionGroup) -> SessionItem {
        let m = SessionMessage(id: id, threadId: "t-" + id, fromName: "Sender " + id, fromAddress: id + "@example.test",
                               subject: "Subject " + id, date: Date(timeIntervalSince1970: 1_794_312_000), text: "",
                               section: group == .reading ? .reading : .updates, category: .updates, isPerson: false, ask: nil,
                               isHealth: false, isFirstTimeSender: false, asksForAction: false, hasDates: false)
        return SessionItem(message: m, group: group, suggestion: .archive, drawer: nil)
    }

    func testEveryGroupBecomesCardsInOrder() {
        let model = SessionModel(plan: SessionPlan(items: [item("r", .reading), item("q", .quick), item("d", .oneAtATime)], carried: []))
        model.start()
        XCTAssertEqual(model.phase, .item("d"), "decisions first")
        model.record("d", .archived); model.advance()
        XCTAssertEqual(model.phase, .item("q"), "quick ones are cards, not a batch screen")
        model.record("q", .archived); model.advance()
        XCTAssertEqual(model.phase, .item("r"), "newsletters are cards, not a reading screen")
        model.record("r", .archived); model.advance()
        XCTAssertEqual(model.phase, .wrap)
    }

    func testStartingWithAGroupOpensItsFirstCard() {
        let model = SessionModel(plan: SessionPlan(items: [item("d", .oneAtATime), item("r", .reading)], carried: []))
        model.start(with: .reading)
        XCTAssertEqual(model.phase, .item("r"))
    }

    func testSkippedQuickOneComesBackBeforeWrap() {
        let model = SessionModel(plan: SessionPlan(items: [item("q1", .quick), item("q2", .quick)], carried: []))
        model.start()
        XCTAssertEqual(model.phase, .item("q1"))
        model.skip("q1")
        XCTAssertEqual(model.phase, .item("q2"))
        model.record("q2", .archived); model.advance()
        XCTAssertEqual(model.phase, .item("q1"), "the skipped one returns once")
    }
}
