import XCTest
@testable import Reelmail

final class GmailTests: XCTestCase {
    func testOnlyReadOnlyScopeIsRequested() {
        XCTAssertEqual(GmailScope.requested, ["https://www.googleapis.com/auth/gmail.readonly"])
        for scope in GmailScope.requested {
            XCTAssertFalse(scope.contains("send"))
            XCTAssertFalse(scope.contains("compose"))
            XCTAssertFalse(scope.contains("modify"))
        }
    }

    func testUnconfiguredClientMeansSampleMode() {
        XCTAssertFalse(GmailConfig(clientID: "").isConfigured)
        XCTAssertFalse(GmailConfig(clientID: "$(GOOGLE_IOS_CLIENT_ID)").isConfigured)
        XCTAssertFalse(GmailConfig(clientID: "YOUR_CLIENT_ID.apps.googleusercontent.com").isConfigured)
        XCTAssertTrue(GmailConfig(clientID: "123-abc.apps.googleusercontent.com").isConfigured)
    }

    func testMalformedClientIDsStayInSampleMode() {
        for bad in ["123-abc.apps.googleusercontent.com.evil", " 123-abc", "abc.apps.googleusercontent.com",
                    "123-abc", "123-abc.apps.googleusercontent.com/x"] {
            XCTAssertFalse(GmailConfig(clientID: bad).isConfigured, bad)
        }
        XCTAssertTrue(GmailConfig(clientID: "456735134102-jc712gcpnljkbme25bu6p2l2ivjv6330.apps.googleusercontent.com").isConfigured)
    }

    /// The built app must carry an expanded value (empty for demo/test builds), never the literal $(...) placeholder.
    func testBuiltInfoPlistClientIDIsExpanded() {
        let bundle = Bundle(for: GmailService.self)
        let raw = bundle.object(forInfoDictionaryKey: "GoogleIOSClientID") as? String
        XCTAssertNotNil(raw, "GoogleIOSClientID missing from the app's Info.plist")
        XCTAssertFalse(raw?.contains("$(") ?? true)
        let config = GmailConfig.fromBundle(bundle)
        XCTAssertTrue(config.clientID.isEmpty || config.isConfigured, "Client ID is set but malformed")
    }

    func testCallbackAcceptsMatchingStateAndScheme() {
        let config = GmailConfig(clientID: "123-abc.apps.googleusercontent.com")
        let url = URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?state=s1&code=4/xyz")!
        XCTAssertEqual(config.authorizationCode(from: url, expectedState: "s1"), .success("4/xyz"))
    }

    func testCallbackRejectsWrongStateSchemeOrMissingCode() {
        let config = GmailConfig(clientID: "123-abc.apps.googleusercontent.com")
        let wrongState = URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?state=other&code=c")!
        let wrongScheme = URL(string: "com.googleusercontent.apps.999-x:/oauthredirect?state=s1&code=c")!
        let noCode = URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?state=s1")!
        XCTAssertEqual(config.authorizationCode(from: wrongState, expectedState: "s1"), .failure(.invalid))
        XCTAssertEqual(config.authorizationCode(from: wrongScheme, expectedState: "s1"), .failure(.invalid))
        XCTAssertEqual(config.authorizationCode(from: noCode, expectedState: "s1"), .failure(.invalid))
    }

    func testCallbackReportsGoogleDenial() {
        let config = GmailConfig(clientID: "123-abc.apps.googleusercontent.com")
        let url = URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?state=s1&error=access_denied")!
        XCTAssertEqual(config.authorizationCode(from: url, expectedState: "s1"), .failure(.denied("access_denied")))
        // A denial with a forged state is treated as invalid, not trusted.
        XCTAssertEqual(config.authorizationCode(from: url, expectedState: "s2"), .failure(.invalid))
    }

    func testRedirectUsesReversedClientID() {
        let config = GmailConfig(clientID: "123-abc.apps.googleusercontent.com")
        XCTAssertEqual(config.redirectScheme, "com.googleusercontent.apps.123-abc")
        XCTAssertEqual(config.redirectURI, "com.googleusercontent.apps.123-abc:/oauthredirect")
        let url = config.authorizationURL(pkce: PKCE(verifier: "v"), state: "s")?.absoluteString ?? ""
        XCTAssertTrue(url.contains("gmail.readonly"))
        XCTAssertTrue(url.contains("code_challenge_method=S256"))
        let items = URLComponents(string: url)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "redirect_uri" })?.value, config.redirectURI)
        XCTAssertEqual(items.first(where: { $0.name == "client_id" })?.value, config.clientID)
        XCTAssertEqual(items.first(where: { $0.name == "scope" })?.value, GmailScope.readOnly)
    }

    func testPKCEMatchesRFC7636Example() {
        // RFC 7636 appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let random = PKCE.make()
        XCTAssertEqual(random.verifier.count, 43)
        XCTAssertNil(random.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testParsesFullFormatMessage() throws {
        let body = Data("Hi there,\nSee you Nov 7?".utf8).base64URLEncoded()
        let json = """
        {"id":"m1","threadId":"t1","labelIds":["INBOX","UNREAD"],"snippet":"Hi there","internalDate":"1700000000000",
         "payload":{"mimeType":"multipart/alternative","headers":[
            {"name":"From","value":"Maya Chen <maya@example.com>"},{"name":"Subject","value":"Plans"},{"name":"To","value":"me@example.com"}],
          "parts":[{"mimeType":"text/html","body":{"data":"\(Data("<p>html</p>".utf8).base64URLEncoded())"}},
                   {"mimeType":"text/plain","body":{"data":"\(body)"}}]}}
        """
        let message = try JSONDecoder().decode(GmailMessage.self, from: Data(json.utf8))
        let email = GmailMessageParser.email(from: message)
        XCTAssertEqual(email.from.name, "Maya Chen")
        XCTAssertEqual(email.from.email, "maya@example.com")
        XCTAssertEqual(email.subject, "Plans")
        XCTAssertEqual(email.body, "Hi there,\nSee you Nov 7?")
        XCTAssertTrue(email.isUnread)
    }

    func testOutgoingAndBulkSignalsComeFromGmailNotNames() throws {
        func message(_ from: String, labels: [String] = ["INBOX"], extra: [[String: String]] = []) throws -> GmailMessage {
            let headers = [["name": "From", "value": from], ["name": "To", "value": "Graham <me@example.com>, Jen <jen@example.com>"],
                           ["name": "Cc", "value": "kid@example.com"], ["name": "Subject", "value": "S"]] + extra
            let json: [String: Any] = ["id": "m", "threadId": "t", "labelIds": labels, "internalDate": "1700000000000",
                                       "payload": ["mimeType": "text/plain", "headers": headers, "body": ["data": Data("hi".utf8).base64URLEncoded()]]]
            return try JSONDecoder().decode(GmailMessage.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let mine = GmailMessageParser.email(from: try message("Graham <me@example.com>"), account: "ME@example.com")
        XCTAssertTrue(mine.isFromMe)
        XCTAssertEqual(mine.to, ["me@example.com", "jen@example.com"])
        XCTAssertEqual(mine.cc, ["kid@example.com"])
        let sameNameOtherAddress = GmailMessageParser.email(from: try message("Graham <other@example.com>"), account: "me@example.com")
        XCTAssertFalse(sameNameOtherAddress.isFromMe, "Identity is never inferred from a display name")
        XCTAssertFalse(sameNameOtherAddress.isAutomated)
        let promo = GmailMessageParser.email(from: try message("Shop <deals@shop.example>", labels: ["INBOX", "CATEGORY_PROMOTIONS"]), account: "me@example.com")
        XCTAssertTrue(promo.isAutomated)
        let list = GmailMessageParser.email(from: try message("Ann <ann@example.com>", extra: [["name": "List-Unsubscribe", "value": "<mailto:x@y>"]]), account: nil)
        XCTAssertTrue(list.isAutomated)
        let tracking = GmailMessageParser.email(from: try message("Parcel <shipment-notification@parcel.example>"), account: nil)
        XCTAssertTrue(tracking.isAutomated)
        XCTAssertEqual(GmailMessageParser.stableHue("a@b.c"), GmailMessageParser.stableHue("a@b.c"))
    }

    func testReplyDetectionIgnoresQuotesSignaturesAndFooters() {
        let footer = "Your order shipped.\n\nQuestions? Visit https://help.example\nUnsubscribe here: https://x.example/u"
        XCTAssertFalse(ReplySignals.needsReply(body: footer, automated: false, category: .updates))
        let quoted = "Thanks, sounds good.\n\nOn Mon, Maya wrote:\n> Can you make it Saturday?"
        XCTAssertFalse(ReplySignals.needsReply(body: quoted, automated: false, category: .people))
        let signature = "See you then.\n-- \nMaya | Would you like a demo?"
        XCTAssertFalse(ReplySignals.needsReply(body: signature, automated: false, category: .people))
        XCTAssertTrue(ReplySignals.needsReply(body: "Hi,\nAre you hosting this year?\nMaya", automated: false, category: .people))
        XCTAssertTrue(ReplySignals.needsReply(body: "Let me know if Friday works.", automated: false, category: .people))
        XCTAssertFalse(ReplySignals.needsReply(body: "Are you hosting this year?", automated: true, category: .people))
    }

    func testFeedPriorityOrder() {
        let me = "me@example.com"
        func email(_ id: String, from: Person, date: TimeInterval, body: String, bulk: Bool = false) -> Email {
            Email(id: id, threadId: "t-" + id, from: from, to: [me], subject: id, date: Date(timeIntervalSince1970: date), body: body, bulk: bulk)
        }
        let maya = Person(id: "maya@x.example", name: "Maya", email: "maya@x.example", hue: 0.1)
        let shop = Person(id: "orders@shop.example", name: "Shop", email: "orders@shop.example", hue: 0.2)
        let fallback = FallbackSummarizer()
        func post(_ e: Email) -> Post { Post(email: e, summary: fallback.summarizeSync(SummaryInput(email: e))) }
        let ask = post(email("ask", from: maya, date: 100, body: "Can you bring dessert?"))
        let answered = post(email("answered", from: maya, date: 50, body: "Can you bring a salad?"))
        let note = post(email("note", from: maya, date: 300, body: "Great seeing you."))
        let receipt = post(email("receipt", from: shop, date: 400, body: "Your receipt. Amount due $12.", bulk: true))
        let school = post(email("school", from: shop, date: 500, body: "Permission form due Nov 8 for the field trip.", bulk: true))
        let letter = post(email("letter", from: shop, date: 600, body: "In this issue: three ideas. Unsubscribe anytime.", bulk: true))
        let reply = Email(id: "r", threadId: "t-answered", from: Person(id: me, name: "You", email: me, hue: 0), to: [maya.email], subject: "Re", date: Date(timeIntervalSince1970: 60), body: "Salad it is.", isFromMe: true)
        let replies = FeedTriage.latestReplies(in: [reply])
        func section(_ p: Post) -> FeedSection { FeedTriage.section(for: p, route: .inbox, replies: replies) }
        XCTAssertEqual(section(ask), .waiting)
        XCTAssertEqual(section(answered), .people, "A newer reply from you clears the wait")
        XCTAssertEqual(section(note), .people)
        XCTAssertEqual(section(receipt), .updates)
        XCTAssertEqual(section(school), .dated)
        XCTAssertEqual(section(letter), .reading)
        XCTAssertEqual(FeedTriage.section(for: note, route: .reading, replies: replies), .reading, "Your rule wins")
        XCTAssertEqual(FeedSection.allCases, [.waiting, .people, .dated, .updates, .reading])
    }

    func testCacheKeyHidesAddressAndRoundTrips() throws {
        XCTAssertEqual(MailCache.accountKey("Me@Example.com"), MailCache.accountKey("me@example.com"))
        XCTAssertFalse(MailCache.accountKey("me@example.com").contains("@"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reelmail-cache-test-" + UUID().uuidString)
        let store = MailCacheStore(directory: dir)
        defer { store.removeAll() }
        let email = Email(id: "1", threadId: "t", from: SampleData.maya, to: ["me@example.com"], subject: "S", date: Date(timeIntervalSince1970: 1), body: "B")
        let summary = FallbackSummarizer().summarizeSync(SummaryInput(email: email))
        let cache = MailCache(snapshot: MailboxSnapshot(account: "me@example.com", inbox: [email], sent: [], fetchedAt: Date(timeIntervalSince1970: 2)),
                              summaries: ["1": summary], hidden: ["1"], seen: ["1"])
        try store.save(cache)
        XCTAssertEqual(store.loadCurrent(), cache)
    }

    func testStripHTML() {
        XCTAssertEqual(GmailMessageParser.stripHTML("<p>Hello&nbsp;<b>there</b></p><style>x{}</style>"), "Hello there")
    }

    func testComposeHandoffNeverSends() {
        let url = GmailCompose.appURL(to: "a@example.com", subject: "Re: Hi", body: "Thanks")
        XCTAssertEqual(url?.scheme, "googlegmail")
        XCTAssertEqual(url?.host, "co")
        XCTAssertEqual(GmailCompose.replySubject("Hi"), "Re: Hi")
        XCTAssertEqual(GmailCompose.replySubject("Re: Hi"), "Re: Hi")
    }
}
