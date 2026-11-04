import XCTest
@testable import Reelmail

final class Step8Tests: XCTestCase {
    private func email(_ id: String, from: String, name: String = "Sender", daysAgo: Double = 1, to: [String] = ["me@example.com"], mine: Bool = false) -> Email {
        Email(id: id, threadId: id, from: Person(id: from, name: name, email: from, hue: 0.4), to: to, subject: "Hello",
              date: Date().addingTimeInterval(-daysAgo * 86_400), body: "b", isFromMe: mine)
    }

    func testShoeboxQueryCannotAddSearchTerms() {
        XCTAssertEqual(ShoeboxRule.backfillQuery(sender: "news@school.example"), "from:news@school.example newer_than:10d")
        XCTAssertEqual(ShoeboxRule.backfillQuery(sender: "a@b.example OR in:anywhere"), "from:a@b.exampleORin:anywhere newer_than:10d")
    }

    func testShoeboxAddressMustLookLikeAnAddress() {
        let d = UserDefaults(suiteName: "sb-\(UUID().uuidString)")!
        ShoeboxRule.setAddress("not an address", defaults: d)
        XCTAssertNil(ShoeboxRule.address(defaults: d))
        ShoeboxRule.setAddress("Box@Example.com", defaults: d)
        XCTAssertEqual(ShoeboxRule.address(defaults: d), "box@example.com")
    }

    func testScreenedOutFindsOnlyNewUnknownSenders() {
        let inbox = [email("1", from: "new@example.com", daysAgo: 2), email("2", from: "old@example.com", daysAgo: 60),
                     email("3", from: "friend@example.com", daysAgo: 1), email("4", from: "accepted@example.com", daysAgo: 1)]
        let sent = [email("s", from: "me@example.com", to: ["Friend <friend@example.com>"], mine: true)]
        let found = ScreenedOut.candidates(inbox: inbox, sent: sent, approved: ["accepted@example.com"], mine: ["me@example.com"], now: Date())
        XCTAssertEqual(found.map(\.address), ["new@example.com"])
    }

    func testDeclinePreviewSaysNothingIsDeleted() {
        let c = ScreenedOut.Candidate(address: "new@example.com", name: "New", messageIDs: ["1", "2"], subject: "Hi")
        XCTAssertTrue(ScreenedOut.declinePreview(c).lines.joined().contains("Nothing is deleted"))
        XCTAssertEqual(ScreenedOut.declinePreview(c).kind, .label)
    }

    func testOneClickUnsubscribeRules() {
        let h = "<mailto:u@news.example>, <https://news.example/unsub?id=1>"
        let p = "List-Unsubscribe=One-Click"
        XCTAssertEqual(OneClickUnsubscribe.target(listUnsubscribe: h, post: p, senderAddress: "hi@mail.news.example", subject: "Weekly deals")?.host, "news.example")
        XCTAssertNil(OneClickUnsubscribe.target(listUnsubscribe: h, post: nil, senderAddress: "hi@news.example", subject: "Weekly deals"), "no one-click header")
        XCTAssertNil(OneClickUnsubscribe.target(listUnsubscribe: "<https://tracker.other.example/u>", post: p, senderAddress: "hi@news.example", subject: "Deals"), "other company")
        XCTAssertNil(OneClickUnsubscribe.target(listUnsubscribe: "<http://news.example/u>", post: p, senderAddress: "hi@news.example", subject: "Deals"), "not https")
        XCTAssertNil(OneClickUnsubscribe.target(listUnsubscribe: h, post: p, senderAddress: "alerts@mail.fidelity.com", subject: "Update"), "financial sender")
        XCTAssertNil(OneClickUnsubscribe.target(listUnsubscribe: h, post: p, senderAddress: "hi@news.example", subject: "Your password reset"), "security mail")
        let req = OneClickUnsubscribe.request(URL(string: "https://news.example/unsub")!)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(String(data: req.httpBody ?? Data(), encoding: .utf8), "List-Unsubscribe=One-Click")
    }
}

final class ScreenedOutCheckTests: XCTestCase {
    func testOnlyConfirmedSendersShowWhenChecked() {
        let e = Email(id: "1", threadId: "1", from: Person(id: "n", name: "New", email: "new@example.com", hue: 0.1), to: ["me@example.com"],
                      subject: "Hi", date: Date(), body: "b")
        XCTAssertTrue(ScreenedOut.candidates(inbox: [e], sent: [], approved: [], mine: [], now: Date(), checked: [:]).isEmpty, "unchecked waits")
        XCTAssertTrue(ScreenedOut.candidates(inbox: [e], sent: [], approved: [], mine: [], now: Date(), checked: ["new@example.com": false]).isEmpty)
        XCTAssertEqual(ScreenedOut.candidates(inbox: [e], sent: [], approved: [], mine: [], now: Date(), checked: ["new@example.com": true]).count, 1)
    }

    func testHistoryQueryIsGroupedAndCannotBeWidened() {
        XCTAssertEqual(ScreenedOut.historyQuery("a@b.example"), "(from:a@b.example older_than:14d) OR to:a@b.example")
        XCTAssertEqual(ScreenedOut.historyQuery("a@b.example) OR (in:anywhere"), "(from:a@b.exampleORin:anywhere older_than:14d) OR to:a@b.exampleORin:anywhere")
    }
}
