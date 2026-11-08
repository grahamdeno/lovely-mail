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

    func testTrashLeavesTheFeedAtOnceCallsGmailAndCanBeUndone() async {
        let client = FakeInboxClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
        await store.load()
        let post = store.posts[0]
        await store.moveToTrash(post)
        XCTAssertEqual(client.trashed, ["fixture-live"])
        XCTAssertTrue(store.activePosts.isEmpty)
        await store.restoreFromTrash(post)
        XCTAssertEqual(client.untrashed, ["fixture-live"])
        XCTAssertEqual(store.activePosts.map(\.id), ["fixture-live"])
    }

    func testRefusedTrashBringsMailBackAndAsksForPermission() async {
        let client = FakeInboxClient()
        client.trashError = GmailService.GmailError.needsTrashPermission
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
        await store.load()
        await store.moveToTrash(store.posts[0])
        XCTAssertEqual(store.activePosts.map(\.id), ["fixture-live"], "The message must not vanish when Gmail refuses")
        XCTAssertTrue(store.needsTrashPermission)
        XCTAssertFalse(store.needsReconnect, "A permission request is not a sign-out")
        XCTAssertNotNil(store.errorMessage)
    }

    func testDemoTrashOnlyHidesFictionalMail() async {
        let client = FakeInboxClient()
        client.isSignedIn = false
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
        await store.load()
        XCTAssertEqual(store.mode, .sample)
        let before = store.activePosts.count
        await store.moveToTrash(store.posts[0])
        XCTAssertEqual(store.activePosts.count, before - 1)
        XCTAssertTrue(client.trashed.isEmpty)
    }

    func testDoneMarksReadInGmailCountsAndCanBeUndone() async {
        let client = FakeInboxClient()
        let defaults = UserDefaults(suiteName: "done-\(UUID())")!
        let store = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await store.load()
        let post = store.posts[0]
        XCTAssertTrue(post.email.isUnread)
        XCTAssertTrue(store.isTodo(post))
        await store.markDone(post)
        XCTAssertEqual(client.markedRead, ["fixture-live"])
        XCTAssertFalse(store.isTodo(post))
        XCTAssertEqual(store.doneToday, 1)
        XCTAssertEqual(store.lastDone?.id, "fixture-live")
        XCTAssertTrue(store.undo.pending.contains { $0.title.hasPrefix("Done") }, "Done offers the app-wide Undo bar")
        await store.undoDone(post)
        XCTAssertEqual(client.markedUnread, ["fixture-live"])
        XCTAssertTrue(store.isTodo(post))
        XCTAssertEqual(store.doneToday, 0)
    }

    func testRefusedDoneStaysOnTheToDo() async {
        let client = FakeInboxClient()
        client.readError = GmailService.GmailError.needsTrashPermission
        let store = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: UserDefaults(suiteName: "done-\(UUID())")!, cacheStore: nil)
        await store.load()
        await store.markDone(store.posts[0])
        XCTAssertTrue(store.isTodo(store.posts[0]), "Still unread when Gmail refuses")
        XCTAssertTrue(store.undo.pending.isEmpty, "No Undo offered for a Done that did not happen")
        XCTAssertEqual(store.doneToday, 0)
        XCTAssertTrue(store.needsTrashPermission)
        XCTAssertNotNil(store.errorMessage)
    }

    func testDemoDoneNeverCallsGmail() async {
        let client = FakeInboxClient()
        client.isSignedIn = false
        let store = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: UserDefaults(suiteName: "done-\(UUID())")!, cacheStore: nil)
        await store.load()
        guard let post = store.digest.todo.first else { return XCTFail("Demo needs unread mail") }
        await store.markDone(post)
        XCTAssertTrue(client.markedRead.isEmpty)
        XCTAssertFalse(store.digest.todo.contains { $0.id == post.id })
    }

    func testOtherAddressMakesNotesToSelfAndIsAccountScoped() async throws {
        let suite = "reelmail.notes-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeedStore(gmail: FakeInboxClient(), summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await store.load()
        XCTAssertEqual(store.section(for: store.posts[0]), .waiting)
        XCTAssertEqual(store.addOtherAddress("Pal@reelmail.example"), .added)
        XCTAssertEqual(store.section(for: store.posts[0]), .notes)
        XCTAssertEqual(store.noteCount, 1)
        XCTAssertTrue(store.people.isEmpty, "Your own addresses are not people")
        XCTAssertEqual(store.sections.map { $0.section }, [.notes])
        XCTAssertEqual(store.demoRules.otherAddresses, [], "Live addresses must not leak into the demo namespace")
        store.removeOtherAddress("pal@reelmail.example")
        XCTAssertEqual(store.section(for: store.posts[0]), .waiting)
        XCTAssertEqual(store.addOtherAddress("not an address"), .invalid)
        XCTAssertEqual(store.addOtherAddress("graham.denoyer@icloud.com"), .added, "A normal address is accepted")
    }

    /// Build 1006 on the owner's phone said "That doesn't look like an email address" for a valid address,
    /// because the Gmail account was not known yet (first load still running or failed after reconnect).
    func testAddressAddedBeforeAccountIsKnownWaitsAndIsSaved() async throws {
        let suite = "reelmail.pending-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = FakeInboxClient()
        client.fails = true
        let store = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await store.load()
        XCTAssertEqual(store.mode, .gmail)
        XCTAssertNil(store.account)
        XCTAssertEqual(store.addOtherAddress("Pal@reelmail.example"), .pending)
        XCTAssertEqual(store.pendingOtherAddresses, ["pal@reelmail.example"])
        client.fails = false
        await store.load()
        XCTAssertEqual(store.otherAddresses, ["pal@reelmail.example"])
        XCTAssertTrue(store.pendingOtherAddresses.isEmpty)
        XCTAssertEqual(store.section(for: store.posts[0]), .notes)
    }

    /// Pull-to-refresh and view tasks are cancelled when the gesture ends or the view goes away.
    /// The load itself must keep going (it may be waiting out Gmail's rate limit).
    func testCancellingTheCallerDoesNotCancelTheLoad() async throws {
        let client = FakeInboxClient()
        client.delayNanoseconds = 300_000_000
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil)
        let caller = Task { await store.load() }
        try await Task.sleep(nanoseconds: 50_000_000)
        caller.cancel()
        await caller.value
        XCTAssertEqual(store.posts.count, 1, "The load finished even though its caller was cancelled")
        XCTAssertNil(store.errorMessage)
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
        store.setSenderRule("pal@reelmail.example", destination: .filtered)
        XCTAssertTrue(store.activePosts.isEmpty)
        XCTAssertEqual(store.filteredPosts.count, 1)
        XCTAssertEqual(store.demoRules.decision(messageID: "fixture-live", sender: "pal@reelmail.example").destination, .inbox,
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
    var delayNanoseconds: UInt64 = 0
    enum Failure: Error { case offline }

    var fetches = 0
    var lastKnown: MailboxSnapshot?
    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits) async throws -> MailboxSnapshot {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if fails { throw Failure.offline }
        if expires { throw GmailService.GmailError.sessionExpired }
        fetches += 1; lastKnown = known
        let inbox = [Email(id: "fixture-live", threadId: "fixture-thread",
                      from: Person(id: "sender", name: "Test Sender", email: "pal@reelmail.example", hue: 0.4),
                      to: ["owner@reelmail.example"], subject: "Fixture message",
                      date: Date(timeIntervalSince1970: 1700000000), body: "A deterministic fictional message. Can you call me?")]
        return MailboxSnapshot(account: "owner@reelmail.example", inbox: inbox, sent: [], fetchedAt: Date(timeIntervalSince1970: 1700000100))
    }
    var trashed: [String] = []
    var untrashed: [String] = []
    var trashError: Error?
    func trash(messageID: String) async throws {
        if let trashError { throw trashError }
        trashed.append(messageID)
    }
    func untrash(messageID: String) async throws { untrashed.append(messageID) }
    var markedRead: [String] = []
    var markedUnread: [String] = []
    var readError: Error?
    func markRead(messageID: String) async throws {
        if let readError { throw readError }
        markedRead.append(messageID)
    }
    func markUnread(messageID: String) async throws { markedUnread.append(messageID) }
    func signIn() async throws { isSignedIn = true }
    func signOut() { isSignedIn = false }

    func testStarterReplyTopicReadsNaturally() {
        XCTAssertEqual(TemplateReplyDrafter.topic("Carpool Thursday?"), "carpool Thursday")
        XCTAssertEqual(TemplateReplyDrafter.topic("IRS letter."), "IRS letter")
        XCTAssertEqual(TemplateReplyDrafter.topic("  "), "your note")
    }

    func testKidReasonsReadAsPlainWords() {
        XCTAssertEqual(KidInsights.plainReasons(["Names Ava", "Mentions school: oakridge elementary", "Mentions teacher: ms. rivera"]),
                       "Mentions Ava, Oakridge Elementary, Ms. Rivera")
        XCTAssertEqual(KidInsights.plainReasons([]), "")
    }
}
