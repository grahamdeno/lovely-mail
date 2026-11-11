import XCTest
@testable import Reelmail

/// Send to Grok: reading the engine's hand-off, the short prompt, what counts as sent, and matching the report.
/// All details are fictional.
final class GrokHandoffTests: XCTestCase {
    func testParsePullsTheHandoffLineSoTheBubbleNeverShowsIt() {
        let r = GrokHandoff.parse("HANDOFF: Search Tennessee unclaimed property for Alex Doe.\nYour Tennessee address was 12 Oak St.")
        XCTAssertEqual(r.task, "Search Tennessee unclaimed property for Alex Doe.")
        XCTAssertEqual(r.rest, "Your Tennessee address was 12 Oak St.")
        XCTAssertFalse(r.rest.contains("HANDOFF"))
        let plain = GrokHandoff.parse("Your bill is $142.18, due Friday.")
        XCTAssertNil(plain.task)
        XCTAssertNil(GrokHandoff.parse("HANDOFF:   ").task)
    }

    func testExplicitAskForGrokStripsThePrefixes() {
        XCTAssertEqual(GrokHandoff.explicitTask("Ask Grok to find my car registration renewal"), "Find my car registration renewal")
        XCTAssertEqual(GrokHandoff.explicitTask("grok, check the HOA site"), "Check the HOA site")
        XCTAssertEqual(GrokHandoff.explicitTask("Have Grok renew the library card"), "Renew the library card")
        XCTAssertNil(GrokHandoff.explicitTask("What did Grok say?"))
        XCTAssertNil(GrokHandoff.explicitTask("Ask Grok to "))
    }

    func testPromptIsShortStartsWithTheStopLineAndNamesTheReportSubject() {
        let task = "Search Tennessee unclaimed property for Alex Doe at 12 Oak St, Nashville."
        let p = GrokHandoff.prompt(task: task, facts: [GrokFact(text: "From: State Treasury"), GrokFact(text: "")], reportTo: "alex@example.com")
        XCTAssertTrue(p.hasPrefix(GrokHandoff.stopLine))
        XCTAssertEqual(p.components(separatedBy: task).count - 1, 1, "the task appears once")
        XCTAssertTrue(p.contains("- From: State Treasury"))
        XCTAssertTrue(p.hasSuffix("reply by email to alex@example.com with the subject exactly: Grok report: Search Tennessee unclaimed property for Alex Doe at"))
    }

    func testPromptDropsHealthFactsAndKeepsAtMostThree() {
        let facts = [GrokFact(text: "Clinic portal: lab results", isHealth: true), GrokFact(text: "a"), GrokFact(text: "b"), GrokFact(text: "c"), GrokFact(text: "d")]
        let p = GrokHandoff.prompt(task: "Do it.", facts: facts, reportTo: "alex@example.com")
        XCTAssertFalse(p.contains("Clinic"))
        XCTAssertTrue(p.contains("- c") && !p.contains("- d"))
        let onlyHealth = GrokHandoff.prompt(task: "Do it.", facts: [GrokFact(text: "Clinic", isHealth: true)], reportTo: "x@example.com")
        XCTAssertFalse(onlyHealth.contains("From my mail"))
    }

    func testOnlyA200IsAccepted() {
        XCTAssertEqual(GrokHandoff.outcome(configured: true, status: 200, transportFailed: false), .accepted)
        XCTAssertEqual(GrokHandoff.outcome(configured: true, status: 202, transportFailed: false), .notSent(.rejected(202)))
        XCTAssertEqual(GrokHandoff.outcome(configured: true, status: 500, transportFailed: false), .notSent(.rejected(500)))
        XCTAssertEqual(GrokHandoff.outcome(configured: true, status: nil, transportFailed: true), .notSent(.unreachable))
        XCTAssertFalse(GrokSendResult.accepted.opensShareSheet)
    }

    func testMissingWebhookIsNotSentAndOpensTheShareSheet() {
        let r = GrokHandoff.outcome(configured: false, status: 200, transportFailed: false)
        XCTAssertEqual(r, .notSent(.noWebhook))
        XCTAssertFalse(r.accepted)
        XCTAssertTrue(r.opensShareSheet)
        XCTAssertTrue(r.note.contains("Share sheet is open"))
    }

    func testReportMatchesItsTitleAndPayloadShape() throws {
        let title = GrokHandoff.shortTitle("Search Tennessee unclaimed property for Alex Doe.")
        XCTAssertTrue(GrokHandoff.isReport(subject: "Re: Grok report: Search Tennessee unclaimed property for Alex Doe", title: title))
        XCTAssertFalse(GrokHandoff.isReport(subject: "Grok report: Renew the library card", title: title))
        XCTAssertFalse(GrokHandoff.isReport(subject: "Search Tennessee unclaimed property for Alex Doe", title: title))
        let json = try JSONSerialization.jsonObject(with: GrokHandoff.payload(task: "T", prompt: "P")) as? [String: String]
        XCTAssertEqual(json, ["source": "lovely", "task": "T", "prompt": "P"])
    }

    func testFilterPreviewIsAFilter() {
        let p = GrokHandoff.filterPreview(owner: "alex@example.com")
        XCTAssertEqual(p.kind, .filter)
        XCTAssertTrue(p.lines.first?.contains("alex@example.com") ?? false)
    }
}
