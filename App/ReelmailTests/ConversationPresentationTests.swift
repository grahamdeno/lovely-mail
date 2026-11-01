import XCTest
@testable import Reelmail

final class ConversationPresentationTests: XCTestCase {
    private func email(_ body: String, sent: Bool = false, date: TimeInterval = 1700000000, thread: String = "topic") -> Email {
        Email(id: UUID().uuidString, threadId: thread,
              from: Person(id: "person", name: "Demo Person", email: "person@demo.example", hue: 0.4),
              to: ["owner@demo.example"], subject: "Demo topic",
              date: Date(timeIntervalSince1970: date), body: body, isFromMe: sent)
    }

    func testShortSentReplyShowsOriginalWithoutSummary() {
        let result = ConversationPresentation.preview(email("I’m in! Where should we meet?", sent: true), summary: nil)
        XCTAssertEqual(result.text, "I’m in! Where should we meet?")
        XCTAssertNil(result.label)
        XCTAssertFalse(result.concealed)
    }

    func testSensitiveUnSummarizedReplyIsConcealed() {
        let result = ConversationPresentation.preview(email("Your verification code is 123456", sent: true), summary: nil)
        XCTAssertTrue(result.concealed)
        XCTAssertFalse(result.text.contains("123456"))
    }

    func testLongUnSummarizedMessageUsesLabeledExcerpt() {
        let result = ConversationPresentation.preview(email(String(repeating: "Long message. ", count: 50)), summary: nil)
        XCTAssertEqual(result.label, "Excerpt")
        XCTAssertLessThanOrEqual(result.text.count, 321)
    }

    func testOnlyNearbySameSenderAndTopicMessagesGroup() {
        let first = email("First")
        XCTAssertTrue(ConversationPresentation.groups(email("Next", date: 1700000060), after: first))
        XCTAssertFalse(ConversationPresentation.groups(email("Later", date: 1700000600), after: first))
        XCTAssertFalse(ConversationPresentation.groups(email("Other topic", date: 1700000060, thread: "other"), after: first))
        XCTAssertFalse(ConversationPresentation.groups(email("Reply", sent: true, date: 1700000060), after: first))
    }
}
