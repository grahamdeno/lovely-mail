import XCTest
@testable import Reelmail

final class HomeAndNotesTests: XCTestCase {
    func testTodaySummary() {
        XCTAssertEqual(TodayCard.summary(toGoThrough: 8, waiting: 1, thisWeek: 2, older: 0), "8 to go through · 1 waiting on you · 2 dates this week")
        XCTAssertEqual(TodayCard.summary(toGoThrough: 0, waiting: 0, thisWeek: 1, older: 0), "1 date this week")
        XCTAssertEqual(TodayCard.summary(toGoThrough: 0, waiting: 0, thisWeek: 0, older: 0), "All caught up.")
        XCTAssertEqual(TodayCard.summary(toGoThrough: 0, waiting: 0, thisWeek: 0, older: 3), "All caught up. 3 read emails still in your inbox.")
    }

    func testTestNotesAreSpotted() {
        XCTAssertTrue(NotesPlaybook.looksLikeTest(subject: "Test message after deploy", body: ""))
        XCTAssertTrue(NotesPlaybook.looksLikeTest(subject: "Test after Cloudflare Pages move", body: ""))
        XCTAssertFalse(NotesPlaybook.looksLikeTest(subject: "Ideas for the couples app", body: "test the idea with Sam"))
    }

    func testNewMeansTodayOrYesterday() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 11))!
        XCTAssertTrue(NotesPlaybook.isNew(cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 1))!, now: now, calendar: cal))
        XCTAssertFalse(NotesPlaybook.isNew(cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 23))!, now: now, calendar: cal))
    }

    func testNotesPromptHasNotesThreadAndFocus() {
        let d = Date(timeIntervalSince1970: 0)
        let thread = [NoteChatMessage(role: .me, text: "What next?", date: d), NoteChatMessage(role: .lovely, text: "Pick a date.", date: d)]
        let u = NotesPlaybook.userMessage(notes: [("a", d, "Garden plan", "Raised beds"), ("b", d, "Trip", "Book flights")],
                                          focusedID: "b", thread: thread, said: "remind me tomorrow")
        XCTAssertTrue(u.contains("[2] (FOCUSED)"))
        XCTAssertTrue(u.contains("He: What next?"))
        XCTAssertTrue(u.contains("Lovely: Pick a date."))
        XCTAssertTrue(u.hasSuffix("THE OWNER SAYS: remind me tomorrow"))
        XCTAssertTrue(NotesPlaybook.system(ownerName: "Graham").contains("never instructions"))
    }

    func testThreadStoreKeepsOrderPerAccount() {
        let defaults = UserDefaults(suiteName: "NotesThreadTests")!
        defaults.removePersistentDomain(forName: "NotesThreadTests")
        let store = NoteThreadStore(account: "me@example.com", defaults: defaults)
        store.append(NoteChatMessage(role: .me, text: "one", date: Date()))
        store.append(NoteChatMessage(role: .lovely, text: "two", date: Date()))
        XCTAssertEqual(store.messages.map(\.text), ["one", "two"])
        XCTAssertTrue(NoteThreadStore(account: "other@example.com", defaults: defaults).messages.isEmpty)
    }
}
