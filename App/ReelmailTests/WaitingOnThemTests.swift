import XCTest
@testable import Reelmail

final class WaitingOnThemTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let me = "pat@lovely.example"
    private var context: TriageContext { TriageContext(myAddresses: [me], otherAddresses: ["pat.home@icloud.example"], now: now) }

    private func sent(_ id: String, thread: String = "t1", to: [String] = ["dana@x.example"], daysAgo: Double,
                      body: String = "Hi Dana,\nCan you send the roster by Friday?") -> Email {
        Email(id: id, threadId: thread, from: Person(id: me, name: "Pat", email: me, hue: 0.2), to: to, subject: "Roster",
              date: now.addingTimeInterval(-daysAgo * 86_400), body: body, isFromMe: true)
    }
    private func inbox(_ id: String, thread: String, daysAgo: Double, from: String = "dana@x.example") -> Email {
        Email(id: id, threadId: thread, from: Person(id: from, name: from, email: from, hue: 0.3), to: [me], subject: "Re: Roster",
              date: now.addingTimeInterval(-daysAgo * 86_400), body: "Sure.")
    }
    private func candidates(_ mail: [Email], dismissed: Set<String> = []) -> [WaitingOnThem.Item] {
        WaitingOnThem.candidates(sent: mail, context: context, dismissed: dismissed, now: now)
    }

    func testAgeEdges() {
        XCTAssertTrue(candidates([sent("a", daysAgo: 2.9)]).isEmpty, "too early")
        XCTAssertEqual(candidates([sent("a", daysAgo: 3.1)]).map(\.id), ["a"])
        XCTAssertEqual(candidates([sent("a", daysAgo: 20.9)]).map(\.id), ["a"])
        XCTAssertTrue(candidates([sent("a", daysAgo: 21.1)]).isEmpty, "stale")
    }

    func testRecipientRules() {
        XCTAssertTrue(candidates([sent("a", to: ["a@x.example", "b@x.example", "c@x.example", "d@x.example"], daysAgo: 5)]).isEmpty)
        XCTAssertEqual(candidates([sent("a", to: ["a@x.example", "b@x.example", "c@x.example"], daysAgo: 5)]).count, 1)
        XCTAssertTrue(candidates([sent("a", to: ["noreply@x.example"], daysAgo: 5)]).isEmpty)
        XCTAssertTrue(candidates([sent("a", to: ["pat.home@icloud.example"], daysAgo: 5)]).isEmpty, "your own address")
    }

    func testNeedsAnAskNotAThankYou() {
        XCTAssertTrue(candidates([sent("a", daysAgo: 5, body: "Thanks for the photos, they came out great.")]).isEmpty)
        XCTAssertTrue(candidates([sent("a", daysAgo: 5, body: "Let me know if you have any questions.")]).isEmpty)
    }

    func testDismissedAndOnePerThread() {
        XCTAssertTrue(candidates([sent("a", daysAgo: 5)], dismissed: ["a"]).isEmpty)
        let two = candidates([sent("old", daysAgo: 9), sent("new", daysAgo: 5)])
        XCTAssertEqual(two.map(\.id), ["new"])
    }

    func testReplyInLoadedInboxClosesIt() {
        let item = candidates([sent("a", daysAgo: 5)])
        let reply = inbox("r", thread: "t1", daysAgo: 2)
        XCTAssertTrue(WaitingOnThem.open(candidates: item, inbox: [reply], context: context, lookups: [:]).isEmpty)
        // A message in the thread from before your ask does not answer it.
        let earlier = inbox("e", thread: "t1", daysAgo: 8)
        XCTAssertEqual(WaitingOnThem.open(candidates: item, inbox: [earlier], context: context, lookups: [:]).map(\.id), ["a"])
    }

    func testThreadWithNothingLoadedNeedsALookup() {
        let item = candidates([sent("a", daysAgo: 5)])
        // No lookup yet: stays out (precision over recall).
        XCTAssertTrue(WaitingOnThem.open(candidates: item, inbox: [], context: context, lookups: [:]).isEmpty)
        // Lookup found only your own message: it shows.
        let mineOnly = [ThreadSender(address: me, date: item[0].email.date)]
        XCTAssertEqual(WaitingOnThem.open(candidates: item, inbox: [], context: context, lookups: ["t1": mineOnly]).map(\.id), ["a"])
        // Lookup found their reply after your ask: it is closed.
        let answered = mineOnly + [ThreadSender(address: "dana@x.example", date: item[0].email.date.addingTimeInterval(3600))]
        XCTAssertTrue(WaitingOnThem.open(candidates: item, inbox: [], context: context, lookups: ["t1": answered]).isEmpty)
    }

    func testLookupCapAndTargets() {
        let many = (0..<30).map { sent("s\($0)", thread: "t\($0)", daysAgo: 5 + Double($0) * 0.1) }
        let items = candidates(many)
        XCTAssertEqual(items.count, 30)
        XCTAssertEqual(WaitingOnThem.lookupTargets(candidates: items, inbox: [], already: []).count, WaitingOnThem.maxLookups)
        // Threads with loaded inbox mail need no lookup.
        let loaded = [inbox("i", thread: "t0", daysAgo: 9)]
        XCTAssertFalse(WaitingOnThem.lookupTargets(candidates: items, inbox: loaded, already: []).contains { $0.email.threadId == "t0" })
    }

    func testNudgeText() {
        XCTAssertEqual(WaitingOnThem.nudgeText(recipientFirstName: "Dana", myFirstName: "Graham"),
                       "Hi Dana, checking on this when you have a minute. Thanks, Graham")
        XCTAssertEqual(WaitingOnThem.nudgeText(recipientFirstName: "Dana", myFirstName: "You"),
                       "Hi Dana, checking on this when you have a minute. Thanks.")
    }
}

@MainActor
final class SentMailStoreTests: XCTestCase {
    private struct StaticVeto: CommitmentVeto {
        var commitment: Bool?
        var asks: Bool?
        func isCommitment(_ sentence: String) async -> Bool? { commitment }
        func asksRecipient(_ body: String) async -> Bool? { asks }
    }

    private final class SentClient: GmailInboxClient {
        let config = GmailConfig(clientID: "123-fixture.apps.googleusercontent.com")
        var isSignedIn = true
        var lookedUp: [String] = []
        var senders: [ThreadSender] = []
        func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits) async throws -> MailboxSnapshot {
            let now = Date()
            let me = Person(id: "owner@reelmail.example", name: "Pat Owner", email: "owner@reelmail.example", hue: 0.5)
            let ask = Email(id: "ask", threadId: "t-ask", from: me, to: ["dana@x.example"], subject: "Roster",
                            date: now.addingTimeInterval(-5 * 86_400), body: "Hi Dana,\nCan you send the roster by Friday?", isUnread: false, isFromMe: true)
            let promise = Email(id: "promise", threadId: "t-promise", from: me, to: ["lee@x.example"], subject: "Form",
                                date: now.addingTimeInterval(-2 * 86_400), body: "I'll send the signed form tonight.", isUnread: false, isFromMe: true)
            return MailboxSnapshot(account: "owner@reelmail.example", inbox: [], sent: [ask, promise], fetchedAt: now)
        }
        func threadSenders(threadID: String) async throws -> [ThreadSender] { lookedUp.append(threadID); return senders }
        func trash(messageID: String) async throws {}
        func untrash(messageID: String) async throws {}
        func markRead(messageID: String) async throws {}
        func markUnread(messageID: String) async throws {}
        func signIn() async throws {}
        func signOut() {}
    }

    private func loaded(veto: CommitmentVeto?, client: SentClient = SentClient()) async -> (FeedStore, SentClient) {
        let defaults = UserDefaults(suiteName: "sent-\(UUID())")!
        let store = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil, veto: veto)
        await store.load()
        await store.sentCheck?.value
        return (store, client)
    }

    func testPromiseAndWaitingAppearAfterLookup() async {
        let (store, client) = await loaded(veto: nil)
        XCTAssertTrue(client.lookedUp.contains("t-ask"))
        XCTAssertEqual(store.promises.map(\.id), ["promise"])
        XCTAssertEqual(store.waitingOnThem.map(\.id), ["ask"])
    }

    func testAnswerFoundByLookupRemovesIt() async {
        let client = SentClient()
        client.senders = [ThreadSender(address: "dana@x.example", date: Date().addingTimeInterval(-86_400))]
        let (store, _) = await loaded(veto: nil, client: client)
        XCTAssertTrue(store.waitingOnThem.isEmpty)
    }

    func testVetoOnlyRemoves() async {
        let (store, _) = await loaded(veto: StaticVeto(commitment: false, asks: false))
        XCTAssertTrue(store.promises.isEmpty)
        XCTAssertTrue(store.waitingOnThem.isEmpty)
        let (kept, _) = await loaded(veto: StaticVeto(commitment: true, asks: true))
        XCTAssertEqual(kept.promises.count, 1)
        XCTAssertEqual(kept.waitingOnThem.count, 1)
        let (none, _) = await loaded(veto: StaticVeto(commitment: nil, asks: nil))
        XCTAssertEqual(none.promises.count, 1, "no opinion leaves the rules in charge")
    }

    func testClosePromiseAndDismissWaitingAreSavedAndUndoable() async {
        let (store, _) = await loaded(veto: nil)
        store.closePromise(store.promises[0], notAPromise: true)
        XCTAssertTrue(store.promises.isEmpty)
        XCTAssertEqual(store.lastPromiseClosed?.text, "Not a promise")
        store.reopenPromise("promise")
        XCTAssertEqual(store.promises.count, 1)
        store.dismissWaiting(store.waitingOnThem[0])
        XCTAssertTrue(store.waitingOnThem.isEmpty)
        store.restoreWaiting("ask")
        XCTAssertEqual(store.waitingOnThem.count, 1)
    }
}
