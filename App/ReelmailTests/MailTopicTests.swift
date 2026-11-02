import XCTest
@testable import Reelmail

final class MailTopicTests: XCTestCase {
    private func post(_ id: String, thread: String = "topic", date: TimeInterval, needsReply: Bool = false) -> Post {
        let email = Email(id: id, threadId: thread, from: SampleData.maya, to: [SampleData.me.email],
            subject: "Same subject", date: Date(timeIntervalSince1970: date), body: "A fictional update")
        var summary = FallbackSummarizer().summarizeSync(SummaryInput(email: email))
        summary.needsReply = needsReply
        return Post(email: email, summary: summary)
    }
    private func sent(_ date: TimeInterval, thread: String = "topic") -> Email {
        Email(id: "sent", threadId: thread, from: SampleData.me, to: [SampleData.maya.email],
            subject: "Re: Same subject", date: Date(timeIntervalSince1970: date), body: "I’ll check and confirm.", isUnread: false, isFromMe: true)
    }
    func testSameTopicUpdatesOnePostAndKeepsUnfinishedRequest() throws {
        let request = post("first", date: 100, needsReply: true)
        let reply = sent(200)
        let before = try XCTUnwrap(MailTopic.make(posts: [request], sent: [reply]).first)
        XCTAssertTrue(before.possibleReply, "A reply is not evidence of completion")
        let topics = MailTopic.make(posts: [request, post("update", date: 300)], sent: [reply])
        XCTAssertEqual(topics.count, 1)
        let after = try XCTUnwrap(topics.first)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.origin.id, "first")
        XCTAssertEqual(after.latest.id, "update")
        XCTAssertEqual(after.lastReply?.id, reply.id)
        XCTAssertTrue(after.possibleReply)
    }
    func testNewRequestAfterReplyRemainsPossible() throws {
        let topic = try XCTUnwrap(MailTopic.make(posts: [post("new", date: 300, needsReply: true)], sent: [sent(200)]).first)
        XCTAssertTrue(topic.possibleReply)
    }
    func testSubjectDoesNotMergeDifferentOrMissingThreads() {
        let topics = MailTopic.make(posts: [post("a", thread: "one", date: 100), post("b", thread: "two", date: 200),
            post("c", thread: "", date: 300), post("d", thread: "", date: 400)], sent: [])
        XCTAssertEqual(topics.count, 4)
    }
    func testReplyFromAnotherTopicDoesNotClearRequest() throws {
        let topic = try XCTUnwrap(MailTopic.make(posts: [post("a", date: 100, needsReply: true)], sent: [sent(200, thread: "other")]).first)
        XCTAssertNil(topic.lastReply)
        XCTAssertTrue(topic.possibleReply)
    }
    func testSensitiveSourceConcealsWholeTopic() throws {
        var sensitive = post("private", date: 100)
        sensitive.summary.sensitive = true
        let topic = try XCTUnwrap(MailTopic.make(posts: [sensitive, post("public", date: 200)], sent: []).first)
        XCTAssertTrue(topic.sensitive)
        XCTAssertTrue(topic.preview.concealed)
        XCTAssertNil(topic.replyContext)
    }
    func testTimestampHasNoSecondCounter() {
        XCTAssertEqual(MailTime.label(Date(timeIntervalSince1970: 100), now: Date(timeIntervalSince1970: 1905)), "30 min ago")
    }
    func testExcerptKeepsRequestInsteadOfOnlyFirstSentence() {
        let body = "Hi families,\nThe game is Friday at 9. Team photos follow. Please confirm whether your player can make it.\nThanks, Dana"
        let preview = MailTopic.sourcePreview(body, category: .events, automated: false)
        XCTAssertTrue(preview.contains("The game is Friday at 9."))
        XCTAssertTrue(preview.contains("Please confirm"))
        XCTAssertFalse(preview.contains("Thanks, Dana"))
    }
    func testMayaRequestAndDeadlineRemainAfterHoldingReply() throws {
        let fallback = FallbackSummarizer()
        let posts = SampleData.emails.filter { $0.from.id == SampleData.maya.id }.map {
            Post(email: $0, summary: fallback.summarizeSync(SummaryInput(email: $0)))
        }
        let topic = try XCTUnwrap(MailTopic.make(posts: posts, sent: SampleData.sentByMe).first)
        XCTAssertTrue(topic.possibleReply)
        XCTAssertTrue(topic.preview.text.contains("Thursday"))
        XCTAssertEqual(topic.preview.label, "Excerpt")
        XCTAssertNotNil(topic.replyContext)
    }
}

@MainActor
final class HomeFilteringTests: XCTestCase {
    func testSenderCorrectionSurvivesNewStoreAndCanBeRestored() async throws {
        let suite = "reelmail.topic-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = FeedStore(gmail: TopicDemoClient(), summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await first.load()
        XCTAssertEqual(first.topics.filter { $0.person.id == SampleData.maya.id }.count, 1)
        XCTAssertTrue(first.demoRules.setSender(SampleData.maya.email, destination: .filtered))
        XCTAssertFalse(first.topics.contains { $0.person.id == SampleData.maya.id })
        XCTAssertFalse(first.people.contains { $0.id == SampleData.maya.id })
        XCTAssertEqual(first.filteredDemoPosts.filter { $0.email.from.id == SampleData.maya.id }.count, 2)
        let reopened = FeedStore(gmail: TopicDemoClient(), summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await reopened.load()
        XCTAssertFalse(reopened.topics.contains { $0.person.id == SampleData.maya.id })
        XCTAssertTrue(reopened.demoRules.setSender(SampleData.maya.email, destination: nil))
        XCTAssertTrue(reopened.topics.contains { $0.person.id == SampleData.maya.id })
        XCTAssertTrue(reopened.people.contains { $0.id == SampleData.maya.id })
    }
}

@MainActor
private final class TopicDemoClient: GmailInboxClient {
    let config = GmailConfig(clientID: "")
    var isSignedIn: Bool { false }
    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits) async throws -> MailboxSnapshot { XCTFail("No Gmail fetching in topic demo tests"); return .empty }
    func signIn() async throws { XCTFail("No sign-in in topic demo tests") }
    func trash(messageID: String) async throws { XCTFail("No Gmail changes in topic demo tests") }
    func untrash(messageID: String) async throws { XCTFail("No Gmail changes in topic demo tests") }
    func signOut() {}
}
