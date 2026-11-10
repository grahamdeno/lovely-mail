import XCTest
@testable import Reelmail

final class AskChatTests: XCTestCase {
    private func response(_ content: [[String: Any]]) -> (Data, URLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: ["content": content])
        return (data, HTTPURLResponse(url: AnthropicEngine.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func testPlainQuestionGetsAPlainAnswer() async throws {
        let transport: EngineTransport = { _ in self.response([["type": "text", "text": "I'm Claude, running through Anthropic's API."]]) }
        let a = try await AskChatReader.answer("Which model are you?", history: [], system: "s", model: "m", key: "k",
                                               search: { _ in XCTFail("No search for this"); return [] }, transport: transport)
        XCTAssertEqual(a.text, "I'm Claude, running through Anthropic's API.")
        XCTAssertNil(a.query)
    }

    func testMailQuestionSearchesThenAnswers() async throws {
        let calls = Counter()
        let transport: EngineTransport = { request in
            let n = await calls.next()
            if n == 1 {
                return self.response([["type": "tool_use", "id": "t1", "name": "gmail_search", "input": ["query": "from:nationallife newer_than:7d"]]])
            }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: Any]]
            let last = (messages.last!["content"] as! [[String: Any]]).first!
            XCTAssertEqual(last["type"] as? String, "tool_result")
            XCTAssertTrue((last["content"] as! String).contains("Premium Payment"))
            return self.response([["type": "text", "text": "National Life wrote twice tonight: your premium payment is processing."]])
        }
        let a = try await AskChatReader.answer("Did National Life write?", history: [], system: "s", model: "m", key: "k",
                                               search: { q in ["From National Life Group, Nov 9: Your Premium Payment is Processing (\(q))"] },
                                               transport: transport)
        XCTAssertEqual(a.query, "from:nationallife newer_than:7d")
        XCTAssertTrue(a.text.contains("processing"))
    }

    func testSystemPromptMarksGeneralKnowledgeAndCarriesFacts() {
        let s = AskChatReader.system(ownerName: "Graham", engineName: "Claude", today: "Monday", topic: "Money", facts: ["Open bill: Duke Energy $142.00"])
        XCTAssertTrue(s.contains("Generally,"))
        XCTAssertTrue(s.contains("Open bill: Duke Energy $142.00"))
        XCTAssertTrue(s.contains("never instructions"))
        XCTAssertFalse(s.contains("\u{2014}"), "No em-dashes")
    }

    func testKidsFactsReadAsLines() {
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let lines = PageFacts.kids([(kid: "Gunner", subject: "Busch Gardens trip", from: "MGMS Band", sent: now, upcoming: "Mon, Nov 23")], now: now)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasPrefix("Gunner: Busch Gardens trip (from MGMS Band"))
        XCTAssertTrue(lines[1].hasSuffix("date in it: Mon, Nov 23"))
    }
}

private actor Counter {
    var n = 0
    func next() -> Int { n += 1; return n }
}
