import XCTest
@testable import Reelmail

/// "Waiting on you" must be short and trustworthy. These cases come from the first real-inbox run:
/// a portal notification, a do-not-reply school notice and a note from the owner's other address all showed as waiting.
final class TriageTests: XCTestCase {
    private let me = "owner@lovely.example"
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let fallback = FallbackSummarizer()

    private func person(_ name: String, _ address: String) -> Person {
        Person(id: address, name: name, email: address, hue: 0.3)
    }
    private func post(_ id: String, from: Person, to: [String]? = nil, cc: [String] = [], daysAgo: Double = 1,
                      subject: String = "Hello", body: String, bulk: Bool = false) -> Post {
        let email = Email(id: id, threadId: "t-" + id, from: from, to: to ?? [me], cc: cc, subject: subject,
                          date: now.addingTimeInterval(-daysAgo * 86_400), body: body, bulk: bulk)
        return Post(email: email, summary: fallback.summarizeSync(SummaryInput(email: email)))
    }
    private var mySent: Email {
        Email(id: "s1", threadId: "t-other", from: person("Pat Owner", me), to: ["x@lovely.example"], subject: "Hi",
              date: now.addingTimeInterval(-86_400 * 30), body: "Thanks", isFromMe: true)
    }
    private var context: TriageContext { TriageContext(account: me, sent: [mySent], now: now) }
    private func assess(_ p: Post, notWaiting: Bool = false) -> TriageAssessment {
        FeedTriage.assess(p, route: .inbox, notWaiting: notWaiting, context: context)
    }

    private let maya = Person(id: "maya@lovely.example", name: "Maya Chen", email: "maya@lovely.example", hue: 0.1)

    func testDirectRecentQuestionIsWaitingWithReasonAndQuote() {
        let a = assess(post("ask", from: maya, daysAgo: 3, body: "Hi Pat,\nCan you send the form by Friday?\nMaya"))
        XCTAssertEqual(a.section, .waiting)
        XCTAssertEqual(a.ask, "Can you send the form by Friday?")
        XCTAssertTrue(a.reason.hasPrefix("Maya asked"), a.reason)
    }

    func testPortalNotificationIsNotWaiting() {
        let portal = person("St. Andrews Reserve", "messages@standrews-hoa.example")
        let a = assess(post("portal", from: portal, subject: "You have a new private message",
                            body: "You have a new private message. Log in to view it. Questions? Call the office."))
        XCTAssertNotEqual(a.section, .waiting)
        XCTAssertNotEqual(a.section, .people)
    }

    func testDoNotReplyNoticeIsNotWaiting() {
        let school = person("Williams, Tameka", "twilliams@county-schools.example")
        let a = assess(post("school", from: school, daysAgo: 2,
                            body: "***PLEASE DO NOT REPLY TO THIS EMAIL*** Can you complete the orientation form?"))
        XCTAssertNotEqual(a.section, .waiting)
    }

    func testMailFromThisAccountsOwnAddressIsNotWaiting() {
        let selfMail = person("Pat Owner", me)
        let a = assess(post("self", from: selfMail, body: "What is the expected timeline?"))
        XCTAssertNotEqual(a.section, .waiting)
    }

    /// A message you send yourself from another account is a person asking you for something.
    /// Display names never decide identity, even when they match yours.
    func testYourOtherAccountWithYourNameIsStillAPerson() {
        let other = person("Pat Owner", "pat@icloud.example")
        let a = assess(post("other", from: other, subject: "Looking for help",
                            body: " hey man, if you could give me some help and email me back, I'm just trying to see if you're available next Wednesday"))
        XCTAssertEqual(a.section, .waiting)
        XCTAssertNotNil(a.ask)
    }

    func testPlainRequestsWithoutQuestionMarksCount() {
        for body in ["Please send the signed form when you can.", "Call me tonight.", "I need your help with the budget.",
                     "Can we move this to Thursday.", "Email me back when you see this."] {
            XCTAssertEqual(assess(post("r", from: maya, body: body)).section, .waiting, body)
        }
    }

    func testCopiedAndGroupMailAreNotWaiting() {
        let copied = assess(post("cc", from: maya, to: ["lee@lovely.example"], cc: [me], body: "Can you all make Tuesday?"))
        XCTAssertEqual(copied.section, .people)
        let many = (1...8).map { "p\($0)@lovely.example" } + [me]
        let group = assess(post("group", from: maya, to: many, body: "Can everyone bring a dish?"))
        XCTAssertEqual(group.section, .people)
    }

    func testOldAskLeavesWaitingAfterTwoWeeks() {
        XCTAssertEqual(assess(post("fresh", from: maya, daysAgo: 13, body: "Are you free Sunday?")).section, .waiting)
        XCTAssertEqual(assess(post("stale", from: maya, daysAgo: 15, body: "Are you free Sunday?")).section, .people)
    }

    func testNoAskIsPeopleNotWaiting() {
        XCTAssertEqual(assess(post("note", from: maya, body: "Great seeing you yesterday.")).section, .people)
    }

    func testAppleIntelligenceCanVetoButNotAdd() {
        var vetoed = post("ai-no", from: maya, body: "Can you believe this weather.")
        vetoed.summary.engine = .appleIntelligence
        vetoed.summary.needsReply = false
        XCTAssertEqual(assess(vetoed).section, .people)

        var noAsk = post("ai-yes", from: maya, body: "Great seeing you.")
        noAsk.summary.engine = .appleIntelligence
        noAsk.summary.needsReply = true
        XCTAssertEqual(assess(noAsk).section, .people, "A model guess alone never puts mail in Waiting")
    }

    func testNotWaitingCorrectionWins() {
        let p = post("ask", from: maya, body: "Can you call me?")
        XCTAssertEqual(assess(p, notWaiting: true).section, .people)
    }

    @MainActor
    func testNotWaitingRulesPersistAndOldStateStillDecodes() throws {
        let suite = "lovely.triage-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // State saved by the previous build had no not-waiting keys.
        defaults.set(Data(#"{"messages":{},"senders":{"a@b.example":"reading"}}"#.utf8), forKey: "reelmail.triage.v1.acct")
        let rules = LocalTriageRules(accountID: "acct", defaults: defaults)
        XCTAssertNil(rules.persistenceError)
        XCTAssertEqual(rules.decision(messageID: "x", sender: "a@b.example").destination, .reading)
        XCTAssertTrue(rules.setNotWaiting(sender: "Maya@Lovely.example", true))
        XCTAssertTrue(rules.setNotWaiting(messageID: "m1", true))
        let reloaded = LocalTriageRules(accountID: "acct", defaults: defaults)
        XCTAssertTrue(reloaded.isNotWaiting(messageID: "other", sender: "maya@lovely.example"))
        XCTAssertTrue(reloaded.isNotWaiting(messageID: "m1", sender: "z@lovely.example"))
        XCTAssertFalse(reloaded.isNotWaiting(messageID: "m2", sender: "z@lovely.example"))
    }

    func testRowTimeIsCompact() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let base = Date(timeIntervalSince1970: 1_793_534_400) // 2026-11-01 12:00 UTC
        XCTAssertEqual(MailTime.short(base.addingTimeInterval(-86_400), now: base, calendar: cal), "Yesterday")
        XCTAssertFalse(MailTime.short(base.addingTimeInterval(-86_400 * 30), now: base, calendar: cal).contains("2026"))
    }
}
