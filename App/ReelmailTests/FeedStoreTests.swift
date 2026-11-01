import XCTest
@testable import Reelmail

@MainActor
final class FeedStoreTests: XCTestCase {
    func testFirstGmailFailureDoesNotShowDemoMail() async {
        let client = FakeInboxClient()
        client.fails = true
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
        await store.load()
        XCTAssertEqual(store.mode, .gmail)
        XCTAssertTrue(store.posts.isEmpty)
        XCTAssertTrue(store.sentByMe.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testRefreshFailurePreservesLoadedMailAndRecoveryClearsError() async {
        let client = FakeInboxClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
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
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
        await store.load()
        client.isSignedIn = false
        await store.load()
        XCTAssertEqual(store.mode, .gmail)
        XCTAssertEqual(store.posts.map(\.id), ["fixture-live"])
        XCTAssertNotNil(store.errorMessage)
    }

    func testExplicitDisconnectReturnsToLabeledSampleMode() async {
        let client = FakeInboxClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
        await store.load()
        await store.disconnectGmail()
        XCTAssertEqual(store.mode, .sample)
        XCTAssertEqual(store.posts.count, SampleData.emails.count)
        XCTAssertEqual(store.sentByMe.count, SampleData.sentByMe.count)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(client.isSignedIn)
    }

    func testAccountIdentityComesFromGmailAndRulesAreAccountScoped() async throws {
        let suite = "reelmail.store-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = FakeInboxClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await store.load()
        XCTAssertEqual(store.account, "owner@reelmail.example")
        XCTAssertEqual(store.me.email, "owner@reelmail.example")
        XCTAssertEqual(store.section(for: store.posts[0]), .waiting)
        store.setSenderRule("sender@reelmail.example", destination: .filtered)
        XCTAssertTrue(store.activePosts.isEmpty)
        XCTAssertEqual(store.filteredPosts.count, 1)
        XCTAssertEqual(store.demoRules.decision(messageID: "fixture-live", sender: "sender@reelmail.example").destination, .inbox,
                       "Live rules must not leak into the demo namespace")
    }

    func testCacheMakesRelaunchInstantAndRefreshPassesKnownMail() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reelmail-cache-" + UUID().uuidString)
        let cacheStore = MailCacheStore(directory: dir)
        defer { cacheStore.removeAll() }
        let client = FakeInboxClient()
        let first = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: cacheStore)
        await first.load()
        first.hide(first.posts[0])
        XCTAssertEqual(client.fetches, 1)

        let offline = FakeInboxClient(); offline.fails = true
        let relaunched = FeedStore(gmail: offline, summarizeOnDevice: false, cacheStore: cacheStore)
        await relaunched.load()
        XCTAssertEqual(relaunched.posts.map(\.id), ["fixture-live"], "Cached mail shows even when Gmail is unreachable")
        XCTAssertEqual(relaunched.account, "owner@reelmail.example")
        XCTAssertTrue(relaunched.hidden.contains("fixture-live"))
        XCTAssertNotNil(relaunched.errorMessage)

        let online = FakeInboxClient()
        let refreshed = FeedStore(gmail: online, summarizeOnDevice: false, cacheStore: cacheStore)
        await refreshed.load()
        XCTAssertEqual(online.lastKnown?.inbox.map(\.id), ["fixture-live"], "Known mail is passed so it is not downloaded again")
    }

    func testSessionExpiryAsksForReconnectWithoutLosingMail() async {
        let client = FakeInboxClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
        await store.load()
        client.expires = true
        await store.load()
        XCTAssertTrue(store.needsReconnect)
        XCTAssertEqual(store.posts.map(\.id), ["fixture-live"])
        XCTAssertEqual(store.mode, .gmail)
    }
}

@MainActor
final class FakeInboxClient: GmailInboxClient {
    let config = GmailConfig(clientID: "123-fixture.apps.googleusercontent.com")
    var isSignedIn = true
    var fails = false
    var expires = false
    enum Failure: Error { case offline }

    var fetches = 0
    var lastKnown: MailboxSnapshot?
    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits) async throws -> MailboxSnapshot {
        if fails { throw Failure.offline }
        if expires { throw GmailService.GmailError.sessionExpired }
        fetches += 1; lastKnown = known
        let inbox = [Email(id: "fixture-live", threadId: "fixture-thread",
                      from: Person(id: "sender", name: "Test Sender", email: "sender@reelmail.example", hue: 0.4),
                      to: ["owner@reelmail.example"], subject: "Fixture message",
                      date: Date(timeIntervalSince1970: 1700000000), body: "A deterministic fictional message. Can you call me?")]
        return MailboxSnapshot(account: "owner@reelmail.example", inbox: inbox, sent: [], fetchedAt: Date(timeIntervalSince1970: 1700000100))
    }
    func signIn() async throws { isSignedIn = true }
    func signOut() { isSignedIn = false }
}
