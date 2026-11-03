import XCTest
@testable import Reelmail

final class AutoReplyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let me = "pat@lovely.example"
    private var context: TriageContext { TriageContext(myAddresses: [me], otherAddresses: [], now: now) }

    private func mail(_ id: String, thread: String = "t1", from: String = "dana@x.example", subject: String = "Re: Roster",
                      body: String, daysAgo: Double = 1, bulk: Bool = false, autoReply: Bool = false) -> Email {
        Email(id: id, threadId: thread, from: Person(id: from, name: from, email: from, hue: 0.3), to: [me], subject: subject,
              date: now.addingTimeInterval(-daysAgo * 86_400), body: body, bulk: bulk, autoReply: autoReply)
    }
    private func post(_ email: Email) -> Post {
        Post(email: email, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: email)))
    }

    // MARK: Detection

    func testSubjectPrefixes() {
        for subject in ["Automatic reply: Practice", "Auto: Practice", "Autoreply: Practice", "Auto-reply: Practice",
                        "Out of Office", "Out of the office until Monday", "OOO: back Monday", "Away: Nov 9", "Re: Automatic reply: Practice"] {
            XCTAssertTrue(AutoReply.subjectIsAutoReply(subject), subject)
        }
        XCTAssertFalse(AutoReply.subjectIsAutoReply("Practice moved to Thursday"))
        XCTAssertFalse(AutoReply.subjectIsAutoReply("Re: Are you out of office Friday?"))
    }

    func testHeaders() {
        XCTAssertTrue(AutoReply.isAutoReply(autoSubmitted: "auto-replied", xAutoreply: nil, xAutorespond: nil))
        XCTAssertTrue(AutoReply.isAutoReply(autoSubmitted: nil, xAutoreply: "yes", xAutorespond: nil))
        XCTAssertTrue(AutoReply.isAutoReply(autoSubmitted: nil, xAutoreply: nil, xAutorespond: "yes"))
        XCTAssertFalse(AutoReply.isAutoReply(autoSubmitted: "no", xAutoreply: nil, xAutorespond: nil))
        XCTAssertFalse(AutoReply.isAutoReply(autoSubmitted: "auto-generated", xAutoreply: nil, xAutorespond: nil), "a system notice, handled by other rules")
        XCTAssertFalse(AutoReply.isAutoReply(autoSubmitted: nil, xAutoreply: nil, xAutorespond: nil))
    }

    func testBodyNeedsTwoPhrases() {
        XCTAssertTrue(AutoReply.bodyIsAutoReply("I am out of the office until Nov 9 with limited access to email."))
        XCTAssertTrue(AutoReply.bodyIsAutoReply("I\u{2019}m currently away and will respond when I return."))
        XCTAssertFalse(AutoReply.bodyIsAutoReply("I'll be out of the office Friday, can you cover the desk?"), "one phrase from a person is not enough")
    }

    func testAPersonsAskStaysWaiting() {
        let email = mail("a", subject: "Friday", body: "I'll be out of the office Friday, can you cover the desk?")
        XCTAssertFalse(email.isAutoReply)
        let assessment = FeedTriage.assess(post(email), route: .inbox, context: context)
        XCTAssertEqual(assessment.section, .waiting)
    }

    // MARK: Sorting

    func testAutoReplyGoesToUpdates() {
        for email in [mail("a", subject: "Automatic reply: Practice", body: "Thanks for writing. I will be back Monday."),
                      mail("b", subject: "Hello", body: "I am out of the office until Monday with limited access to email."),
                      mail("c", subject: "Hello", body: "Thanks.", autoReply: true)] {
            let assessment = FeedTriage.assess(post(email), route: .inbox, context: context)
            XCTAssertEqual(assessment.section, .updates, email.id)
            XCTAssertEqual(assessment.reason, "Automatic reply")
        }
    }

    func testMarkSurvivesOldCache() throws {
        let marked = mail("a", body: "x", autoReply: true)
        XCTAssertTrue(marked.isAutoReply)
        let plain = mail("b", body: "x")
        XCTAssertNil(plain.autoReplyMark)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        object.removeValue(forKey: "autoReplyMark")
        let decoded = try JSONDecoder().decode(Email.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isAutoReply)
    }

    // MARK: Not an answer

    private func ask(daysAgo: Double = 5) -> Email {
        Email(id: "s1", threadId: "t1", from: Person(id: me, name: "Pat", email: me, hue: 0.2), to: ["dana@x.example"], subject: "Roster",
              date: now.addingTimeInterval(-daysAgo * 86_400), body: "Hi Dana,\nCan you send the roster by Friday?", isFromMe: true)
    }

    func testAutoReplyDoesNotAnswerAnAsk() {
        let item = WaitingOnThem.candidates(sent: [ask()], context: context, dismissed: [], now: now)
        XCTAssertEqual(item.count, 1)
        let auto = mail("r1", subject: "Automatic reply: Roster", body: "I am out of the office until Monday.", daysAgo: 4)
        XCTAssertFalse(WaitingOnThem.answeredInLoadedMail(item[0], inbox: [auto], context: context))
        XCTAssertEqual(WaitingOnThem.open(candidates: item, inbox: [auto], context: context, lookups: [:]).count, 1)
        let real = mail("r2", body: "Sure, sending it now.", daysAgo: 3)
        XCTAssertTrue(WaitingOnThem.answeredInLoadedMail(item[0], inbox: [auto, real], context: context))
    }

    func testAutoReplyInAThreadLookupDoesNotAnswer() {
        let item = WaitingOnThem.candidates(sent: [ask()], context: context, dismissed: [], now: now)[0]
        let date = now.addingTimeInterval(-3 * 86_400)
        XCTAssertFalse(WaitingOnThem.answered(item, senders: [ThreadSender(address: "dana@x.example", date: date, isAutoReply: true)], context: context))
        XCTAssertTrue(WaitingOnThem.answered(item, senders: [ThreadSender(address: "dana@x.example", date: date)], context: context))
    }

    func testAutoReplyDoesNotClosePromise() {
        let promise = Email(id: "s1", threadId: "t1", from: Person(id: me, name: "Pat", email: me, hue: 0.2), to: ["dana@x.example"],
                            subject: "Form", date: now.addingTimeInterval(-3 * 86_400), body: "I'll send the signed form tonight.", isFromMe: true)
        let auto = mail("r1", subject: "Out of Office", body: "Away until Monday.", daysAgo: 2)
        XCTAssertEqual(PromiseRules.open(sent: [promise], inbox: [auto], context: context, closed: [], now: now).count, 1)
        let real = mail("r2", body: "Thanks!", daysAgo: 2)
        XCTAssertTrue(PromiseRules.open(sent: [promise], inbox: [real], context: context, closed: [], now: now).isEmpty)
    }

    func testAutoReplyYieldsNoDates() {
        let auto = mail("a", subject: "Automatic reply: Practice", body: "I am out of the office until Nov 9.", daysAgo: 0)
        XCTAssertTrue(MailDates.extract(auto, now: now).isEmpty)
    }
}
