import XCTest
@testable import Reelmail

final class OutboxTests: XCTestCase {
    func testAddRemoveAndBatches() {
        let defaults = UserDefaults(suiteName: "OutboxTests")!
        defaults.removePersistentDomain(forName: "OutboxTests")
        let box = Outbox(account: "me@example.com", defaults: defaults)
        let a = OutboxOp(kind: .file, messageID: "m1", labels: ["Lovely/Money"], batch: "b1")
        let b = OutboxOp(kind: .archive, messageID: "m2", batch: "b1")
        let c = OutboxOp(kind: .trash, messageID: "m3", batch: "b2")
        box.add([a, b, c])
        XCTAssertEqual(box.ops.count, 3)
        box.remove(id: a.id)
        XCTAssertEqual(box.ops.map(\.messageID), ["m2", "m3"])
        box.remove(batch: "b1")
        XCTAssertEqual(box.ops.map(\.messageID), ["m3"])
        XCTAssertTrue(Outbox(account: "other@example.com", defaults: defaults).ops.isEmpty, "Per account")
    }

    func testWhatFinishesByItself() {
        XCTAssertTrue(OutboxOp(kind: .trash, messageID: "m", batch: "b").finishesByItself)
        XCTAssertTrue(OutboxOp(kind: .markRead, messageID: "m", batch: "b").finishesByItself)
        XCTAssertFalse(OutboxOp(kind: .file, messageID: "m", batch: "b").finishesByItself, "Filing needs a fresh tap")
        XCTAssertFalse(OutboxOp(kind: .archive, messageID: "m", batch: "b").finishesByItself)
    }

    func testPreviewSaysWhatWillHappen() {
        let p = Outbox.preview([OutboxOp(kind: .file, messageID: "1", labels: ["Lovely/Money"], batch: "b"),
                                OutboxOp(kind: .archive, messageID: "2", batch: "b")])
        XCTAssertEqual(p.kind, .label)
        XCTAssertEqual(p.title, "Finish 2 changes from earlier")
        XCTAssertTrue(p.lines.joined().contains("Nothing is deleted"))
    }
}
