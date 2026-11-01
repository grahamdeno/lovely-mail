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

    func testRedirectUsesReversedClientID() {
        let config = GmailConfig(clientID: "123-abc.apps.googleusercontent.com")
        XCTAssertEqual(config.redirectScheme, "com.googleusercontent.apps.123-abc")
        XCTAssertEqual(config.redirectURI, "com.googleusercontent.apps.123-abc:/oauthredirect")
        let url = config.authorizationURL(pkce: PKCE(verifier: "v"), state: "s")?.absoluteString ?? ""
        XCTAssertTrue(url.contains("gmail.readonly"))
        XCTAssertTrue(url.contains("code_challenge_method=S256"))
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
