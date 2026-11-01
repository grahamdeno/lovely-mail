import XCTest
@testable import Reelmail

@MainActor
final class FeedStoreTests: XCTestCase {
    func testFirstGmailFailureDoesNotShowDemoMail() async {
        let client = FakeInboxClient()
        client.fails = true
        let store = FeedStore(gmail: client, summarizeOnDevice: false)
        await store.load()
        XCTAssertEqual(store.mode, .gmail)
        XCTAssertTrue(store.posts.isEmpty)
        XCTAssertTrue(store.sentByMe.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testRefreshFailurePreservesLoadedMailAndRecoveryClearsError() async {
        let client = FakeInboxClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false)
        await store.load()
        let ids = store.posts.map(\.id)
        XCTAssertEqual(ids, ["fixture-live"])
        client.fails = true
        await store.load()
        XCTAssertEqual(store.posts.map(\.id), ids)
        XCTAssertNotNil(store.errorMessage)
        client.fails = false
        await store.load()
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.mode, .gmail)
    }

    func testLostCredentialsDoNotSwitchToDemo() async {
        let client = FakeInboxClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false)
        await store.load()
        client.isSignedIn = false
        await store.load()
        XCTAssertEqual(store.mode, .gmail)
        XCTAssertEqual(store.posts.map(\.id), ["fixture-live"])
        XCTAssertNotNil(store.errorMessage)
    }

    func testExplicitDisconnectReturnsToLabeledSampleMode() async {
        let client = FakeInboxClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false)
        await store.load()
        await store.disconnectGmail()
        XCTAssertEqual(store.mode, .sample)
        XCTAssertEqual(store.posts.count, SampleData.emails.count)
        XCTAssertEqual(store.sentByMe.count, SampleData.sentByMe.count)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(client.isSignedIn)
    }
}

@MainActor
private final class FakeInboxClient: GmailInboxClient {
    let config = GmailConfig(clientID: "123-fixture.apps.googleusercontent.com")
    var isSignedIn = true
    var fails = false
    enum Failure: Error { case offline }

    func fetchInbox(maxResults: Int) async throws -> [Email] {
        if fails { throw Failure.offline }
        return [Email(id: "fixture-live", threadId: "fixture-thread",
                      from: Person(id: "sender", name: "Test Sender", email: "sender@reelmail.example", hue: 0.4),
                      to: ["owner@reelmail.example"], subject: "Fixture message",
                      date: Date(timeIntervalSince1970: 1700000000), body: "A deterministic fictional message.")]
    }
    func signIn() async throws { isSignedIn = true }
    func signOut() { isSignedIn = false }
}
