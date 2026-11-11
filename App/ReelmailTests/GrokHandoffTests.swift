import XCTest
@testable import Reelmail

/// Hand to Grok: reading the engine's hand-off, the prompt Grok gets, and the Shortcut link. All details are fictional.
final class GrokHandoffTests: XCTestCase {
    func testParseHandoffLine() {
        let r = GrokHandoff.parse("HANDOFF: Search Tennessee unclaimed property for Alex Doe.\nYour Tennessee address was 12 Oak St.")
        XCTAssertEqual(r.task, "Search Tennessee unclaimed property for Alex Doe.")
        XCTAssertEqual(r.rest, "Your Tennessee address was 12 Oak St.")
        let plain = GrokHandoff.parse("Your bill is $142.18, due Friday.")
        XCTAssertNil(plain.task)
        XCTAssertEqual(plain.rest, "Your bill is $142.18, due Friday.")
        XCTAssertNil(GrokHandoff.parse("HANDOFF:   ").task)
    }

    func testExplicitAskForGrok() {
        XCTAssertEqual(GrokHandoff.explicitTask("Ask Grok to find my car registration renewal"), "Find my car registration renewal")
        XCTAssertEqual(GrokHandoff.explicitTask("grok, check the HOA site"), "Check the HOA site")
        XCTAssertNil(GrokHandoff.explicitTask("What did Grok say?"))
        XCTAssertNil(GrokHandoff.explicitTask("Ask Grok to "))
    }

    func testPromptPutsTheStopRuleFirstAndAsksForAReport() {
        let p = GrokHandoff.prompt(task: "File the Tennessee unclaimed property claim.", context: ["Old address: 12 Oak St, Nashville", ""],
                                   reportTo: "alex@example.com")
        XCTAssertTrue(p.hasPrefix("STOP AND ASK ME FIRST"))
        XCTAssertTrue(p.contains("- Old address: 12 Oak St, Nashville"))
        XCTAssertTrue(p.contains("email alex@example.com"))
        XCTAssertTrue(p.contains("\"Grok report: File the Tennessee unclaimed property claim\""))
        XCTAssertFalse(p.contains("- \n"), "empty facts are left out")
    }

    func testShortTitleAndShortcutURL() {
        XCTAssertEqual(GrokHandoff.shortTitle("Find and file every unclaimed property claim in all five states now."),
                       "Find and file every unclaimed property claim in")
        let url = GrokHandoff.shortcutURL(name: "Send to Grok", text: "Hello & bye")
        XCTAssertEqual(url?.scheme, "shortcuts")
        XCTAssertEqual(url?.host, "run-shortcut")
        XCTAssertTrue(url?.absoluteString.contains("name=Send%20to%20Grok") ?? false)
        XCTAssertNil(GrokHandoff.shortcutURL(name: "  ", text: "x"))
    }

    func testFilterPreviewIsAFilter() {
        let p = GrokHandoff.filterPreview(owner: "alex@example.com")
        XCTAssertEqual(p.kind, .filter)
        XCTAssertTrue(p.lines.first?.contains("alex@example.com") ?? false)
    }
}
