import XCTest
@testable import Reelmail

final class PromiseRulesTests: XCTestCase {
    private struct Corpus: Decodable {
        struct Case: Decodable { let id: String; let text: String; let commitment: Bool }
        let cases: [Case]
    }
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let context = TriageContext(myAddresses: ["pat@lovely.example"], otherAddresses: ["pat.home@icloud.example"], now: Date(timeIntervalSince1970: 2_000_000_000))

    func testPromiseScorecard() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "promise-corpus", withExtension: "json"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        var falsePositives: [String] = [], misses: [String] = []
        for c in corpus.cases {
            let got = PromiseRules.isCommitment(c.text)
            if got && !c.commitment { falsePositives.append(c.id + ": " + c.text) }
            if !got && c.commitment { misses.append(c.id + ": " + c.text) }
        }
        let positives = corpus.cases.filter(\.commitment).count
        XCTAssertTrue(falsePositives.isEmpty, "False commitments: \(falsePositives)")
        XCTAssertGreaterThanOrEqual(Double(positives - misses.count) / Double(positives), 0.9, "Missed: \(misses)")
    }

    private func mail(_ id: String, thread: String = "t1", from: String, to: [String], daysAgo: Double, body: String = "x") -> Email {
        Email(id: id, threadId: thread, from: Person(id: from, name: from, email: from, hue: 0.2), to: to, subject: "Hi",
              date: now.addingTimeInterval(-daysAgo * 86_400), body: body, isFromMe: from == "pat@lovely.example")
    }

    func testOpenPromiseAppearsAndRespectsWindow() {
        let recent = mail("s1", from: "pat@lovely.example", to: ["dana@x.example"], daysAgo: 3, body: "I'll send the signed form tonight.")
        let old = mail("s2", thread: "t2", from: "pat@lovely.example", to: ["dana@x.example"], daysAgo: 20, body: "I'll send the roster.")
        let items = PromiseRules.open(sent: [recent, old], inbox: [], context: context, closed: [], now: now)
        XCTAssertEqual(items.map(\.id), ["s1"])
    }

    func testLaterMessageInThreadClosesIt() {
        let promise = mail("s1", from: "pat@lovely.example", to: ["dana@x.example"], daysAgo: 3, body: "I'll send the form.")
        let theirs = mail("i1", from: "dana@x.example", to: ["pat@lovely.example"], daysAgo: 1)
        XCTAssertTrue(PromiseRules.open(sent: [promise], inbox: [theirs], context: context, closed: [], now: now).isEmpty)
        let followUp = mail("s2", from: "pat@lovely.example", to: ["dana@x.example"], daysAgo: 1)
        XCTAssertTrue(PromiseRules.open(sent: [promise, followUp], inbox: [], context: context, closed: [], now: now).isEmpty)
    }

    func testClosedAndOwnAndNoReplyRecipientsAreExcluded() {
        let toSelf = mail("s1", from: "pat@lovely.example", to: ["pat.home@icloud.example"], daysAgo: 2, body: "I'll send the form.")
        let toBot = mail("s2", thread: "t2", from: "pat@lovely.example", to: ["noreply@x.example"], daysAgo: 2, body: "I'll send the form.")
        let ok = mail("s3", thread: "t3", from: "pat@lovely.example", to: ["dana@x.example"], daysAgo: 2, body: "I'll send the form.")
        XCTAssertEqual(PromiseRules.open(sent: [toSelf, toBot, ok], inbox: [], context: context, closed: [], now: now).map(\.id), ["s3"])
        XCTAssertTrue(PromiseRules.open(sent: [ok], inbox: [], context: context, closed: ["s3"], now: now).isEmpty)
    }

    func testVetoOnlyRemoves() {
        let ok = mail("s1", from: "pat@lovely.example", to: ["dana@x.example"], daysAgo: 2, body: "I'll send the form.")
        XCTAssertTrue(PromiseRules.open(sent: [ok], inbox: [], context: context, closed: [], veto: { _, _ in false }, now: now).isEmpty)
        let none = mail("s2", from: "pat@lovely.example", to: ["dana@x.example"], daysAgo: 2, body: "Thanks, see you there.")
        XCTAssertTrue(PromiseRules.open(sent: [none], inbox: [], context: context, closed: [], veto: { _, _ in true }, now: now).isEmpty)
    }

    func testRecipientLine() {
        let one = mail("s1", from: "pat@lovely.example", to: ["Dana <dana@x.example>"], daysAgo: 1)
        XCTAssertEqual(PromiseRules.recipientLine(one) { _ in "Dana" }, "Dana")
        let three = mail("s2", from: "pat@lovely.example", to: ["a@x.example", "b@x.example", "c@x.example"], daysAgo: 1)
        XCTAssertEqual(PromiseRules.recipientLine(three) { _ in "Dana" }, "Dana and 2 others")
    }
}
