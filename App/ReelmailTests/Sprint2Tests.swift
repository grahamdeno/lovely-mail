import XCTest
@testable import Reelmail

/// Sprint 2: search rules, refresh messages, Promotions, stub bodies, plain asks.
final class Sprint2Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func post(from name: String, _ address: String, subject: String, body: String) -> Post {
        let person = Person(id: address, name: name, email: address, hue: 0.3)
        let email = Email(id: UUID().uuidString, threadId: "t", from: person, to: ["pat@lovely.example"],
                          subject: subject, date: now, body: body)
        return Post(email: email, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: email)))
    }

    // MARK: Search

    func testTokensSplitOnWhitespaceAndLowercase() {
        XCTAssertEqual(MailSearch.tokens("  Dana  BROOKS "), ["dana", "brooks"])
        XCTAssertEqual(MailSearch.tokens("   "), [])
    }

    func testEveryWordMustMatchButInAnyField() {
        let p = post(from: "Dana Brooks", "dana@rink.example", subject: "Game Sunday", body: "Ice time at nine.")
        XCTAssertTrue(MailSearch.matches(p, tokens: MailSearch.tokens("dana sunday")))
        XCTAssertTrue(MailSearch.matches(p, tokens: MailSearch.tokens("brooks ice")))
        XCTAssertFalse(MailSearch.matches(p, tokens: MailSearch.tokens("dana tuesday")))
        XCTAssertFalse(MailSearch.matches(p, tokens: []))
    }

    func testPersonMatchesNameOrAddress() {
        let person = Person(id: "a", name: "Dana Brooks", email: "dana@rink.example", hue: 0.3)
        XCTAssertTrue(MailSearch.matches(person, tokens: ["rink"]))
        XCTAssertTrue(MailSearch.matches(person, tokens: ["brooks", "dana"]))
        XCTAssertFalse(MailSearch.matches(person, tokens: ["sunday"]))
    }

    // MARK: Refresh message

    func testRefreshMessagesArePlainAndKeepMail() {
        let offline = RefreshProblem.message(for: URLError(.notConnectedToInternet))
        XCTAssertTrue(offline.contains("Can't reach Gmail"))
        XCTAssertTrue(offline.contains("unchanged"))
        let slow = RefreshProblem.message(for: GmailService.GmailError.refused(429, GmailAPIError(reason: "RATE_LIMIT_EXCEEDED", message: "x")))
        XCTAssertTrue(slow.contains("slow down"))
        let server = RefreshProblem.message(for: GmailService.GmailError.http(503))
        XCTAssertTrue(server.contains("trouble"))
        let other = RefreshProblem.message(for: NSError(domain: "x", code: 1))
        XCTAssertEqual(other, "Gmail could not refresh. Your loaded mail is unchanged.")
    }

    // MARK: Stub bodies

    func testHTMLWinsOverAStubPlainPart() {
        let html = String(repeating: "Welcome to your account. ", count: 20)
        XCTAssertEqual(GmailMessageParser.preferred(plain: "View in browser", html: html), html)
    }

    func testRealPlainTextIsKept() {
        let plain = String(repeating: "A real plain text body. ", count: 20)
        XCTAssertEqual(GmailMessageParser.preferred(plain: plain, html: plain + " more html"), plain)
        XCTAssertEqual(GmailMessageParser.preferred(plain: "Short note", html: "Short"), "Short note")
        XCTAssertEqual(GmailMessageParser.preferred(plain: nil, html: "Only html"), "Only html")
        XCTAssertNil(GmailMessageParser.preferred(plain: nil, html: nil))
    }

    // MARK: Promotions

    func testPromotionalMarkSurvivesOldCache() throws {
        let person = Person(id: "a", name: "Shop", email: "news@shop.example", hue: 0.1)
        let promo = Email(id: "1", threadId: "t", from: person, to: [], subject: "Hi", date: now, body: "x", bulk: true, promotional: true)
        XCTAssertTrue(promo.isPromotional)
        let plain = Email(id: "2", threadId: "t", from: person, to: [], subject: "Hi", date: now, body: "x")
        XCTAssertFalse(plain.isPromotional)
        XCTAssertNil(plain.promotionalMark)
        // Mail cached before the field existed has no key; it must still decode.
        let old = try JSONEncoder().encode(plain)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        object.removeValue(forKey: "promotionalMark")
        let decoded = try JSONDecoder().decode(Email.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isPromotional)
    }

    func testListFooterNeedsRealFooterText() {
        XCTAssertTrue(ReplySignals.hasListFooter("Three soups.\nUnsubscribe | Update preferences"))
        XCTAssertTrue(ReplySignals.hasListFooter("View this email in your browser"))
        XCTAssertFalse(ReplySignals.hasListFooter("Here is the newsletter draft for the club."))
    }

    // MARK: Plain asks

    func testPlainAsksFound() {
        for body in ["I need the signed form by Thursday.", "Please keep me posted.", "Remind me what time it starts.",
                     "We should touch base next week.", "Let us know which dates work."] {
            XCTAssertNotNil(ReplySignals.askSentence(in: body), body)
        }
    }

    func testLetUsKnowCourtesyIsNotAnAsk() {
        XCTAssertNil(ReplySignals.askSentence(in: "Thanks for coming. Let us know if you have any questions."))
        XCTAssertNil(ReplySignals.askSentence(in: "Let us know if there is anything else."))
    }
}
