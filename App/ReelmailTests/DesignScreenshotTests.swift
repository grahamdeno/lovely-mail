import XCTest
import SwiftUI
import UIKit
@testable import Reelmail

/// Rendering evidence, not an assertion of visual quality or device validation.
@MainActor
final class DesignScreenshotTests: XCTestCase {
    func testHomeScreenshot() async throws {
        let store = await demoStore()
        try await capture(RootView().environment(store).environment(Router()), name: "01-Home-demo")
    }
    func testPeopleScreenshot() async throws {
        let store = await demoStore()
        let router = Router(); router.tab = .people
        try await capture(RootView().environment(store).environment(router), name: "02-People-demo")
    }
    func testTimelineScreenshot() async throws {
        let store = await demoStore()
        let person = try XCTUnwrap(store.people.first)
        try await capture(NavigationStack { ThreadView(person: person) }.environment(store).environment(Router()), name: "03-Timeline-demo")
    }
    func testLargerTextScreenshots() async throws {
        let store = await demoStore()
        let router = Router()
        try await capture(RootView().environment(store).environment(router).dynamicTypeSize(.accessibility2), name: "04-Home-larger-text")
        router.tab = .people
        try await capture(RootView().environment(store).environment(router).dynamicTypeSize(.accessibility2), name: "05-People-larger-text")
        let person = try XCTUnwrap(store.people.first)
        try await capture(NavigationStack { ThreadView(person: person) }.environment(store).environment(router).dynamicTypeSize(.accessibility2), name: "06-Timeline-larger-text")
    }
    func testReviewSortingScreenshot() async throws {
        let store = await demoStore()
        store.demoReview.reset()
        defer { store.demoReview.reset() }
        let recent = store.activePosts.sorted { $0.email.date > $1.email.date }
        if let first = recent.first { store.demoReview.mark(first.id, shown: store.section(for: first), correct: store.section(for: first)) }
        if recent.count > 1 {
            let second = recent[1]
            store.demoReview.mark(second.id, shown: store.section(for: second), correct: store.section(for: second) == .people ? .waiting : .people)
        }
        try await capture(NavigationStack { SortingReviewView() }.environment(store).environment(Router()), name: "07-Review-sorting")
    }
    func testDarkModeScreenshots() async throws {
        let store = await demoStore()
        let router = Router()
        try await capture(RootView().environment(store).environment(router), name: "08-Home-dark", dark: true)
        router.tab = .people
        try await capture(RootView().environment(store).environment(router), name: "09-People-dark", dark: true)
    }
    func testNeonScreenshot() async throws {
        let store = await demoStore()
        ThemeState.neon = true
        defer { ThemeState.neon = false }
        try await capture(RootView().environment(store).environment(Router()), name: "10-Home-neon", dark: true)
    }
    func testEmailScreenshots() async throws {
        let store = await demoStore()
        let waiting = try XCTUnwrap(store.needsReplyPosts.first)
        try await capture(NavigationStack { OpenEmailView(postID: waiting.id) }.environment(store).environment(Router()), name: "11-Email-waiting")
        try await capture(NavigationStack { OpenEmailView(postID: waiting.id) }.environment(store).environment(Router()), name: "12-Email-dark", dark: true)
        try await capture(NavigationStack { OpenEmailView(postID: waiting.id) }.environment(store).environment(Router()).dynamicTypeSize(.accessibility2), name: "13-Email-larger-text")
    }
    func testSettingsAndPeopleScreenshots() async throws {
        let store = await demoStore()
        try await capture(NavigationStack { SettingsView() }.environment(store).environment(Router()), name: "14-Settings")
        let router = Router(); router.tab = .people
        try await capture(RootView().environment(store).environment(router), name: "15-People-orgs-row")
    }
    func testSprint3Screenshots() async throws {
        let client = Sprint3ScreenshotClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil,
                              veto: nil)
        await store.load()
        await store.sentCheck?.value
        XCTAssertEqual(store.promises.count, 1)
        XCTAssertEqual(store.waitingOnThem.count, 1)
        try await capture(RootView().environment(store).environment(Router()), name: "16-Home-promises-and-waiting")
        try await capture(NavigationStack { WaitingOnThemListView() }.environment(store).environment(Router()), name: "17-Waiting-on-them-list")
        // The same unread mail, put off and now back.
        store.putOff(store.posts[0], until: Date().addingTimeInterval(-60))
        try await capture(RootView().environment(store).environment(Router()), name: "18-Home-back-from-Later")
    }
    /// Sprint 4: fictional mail only. Views that need a dated or group message are captured when the demo mail has one.
    func testSprint4Screenshots() async throws {
        let store = await demoStore()
        let router = Router()
        try await capture(NavigationStack { ComingUpListView() }.environment(store).environment(router), name: "19-Coming-up-list")
        if let entry = store.comingUp.first {
            try await capture(NavigationStack { OpenEmailView(postID: entry.post.id) }.environment(store).environment(router), name: "20-Email-with-date-row")
        }
        let mine = Set([store.account ?? ""] + store.otherAddresses).subtracting([""])
        if let group = store.posts.first(where: { ReplyRecipients.offersReplyAll($0.email, mine: mine, organization: store.isAutomated($0)) }) {
            let replyAll = Router(); replyAll.draftReplyAll = true
            try await capture(DraftReplySheet(post: group).environment(store).environment(replyAll), name: "21-Draft-reply-all")
        }
        try await capture(NavigationStack { SettingsView() }.environment(store).environment(router), name: "22-Settings-morning-brief")
        try await capture(BriefOfferCard().padding(20).background(CalmStyle.background).environment(store), name: "23-Home-brief-offer")
    }
    /// Sprint 5: fictional mail only.
    /// LifeOS shell (Nov 13, 2026): the sorting card on its dotted ground, and Search with the new bottom bar.
    func testLifeOSShellScreenshots() async throws {
        let store = await demoStore()
        try await capture(NavigationStack { SessionView() }.environment(store).environment(Router()), name: "26-Sort-card")
        let router = Router(); router.tab = .search
        try await capture(RootView().environment(store).environment(router), name: "27-Search-tab-bar")
    }

    func testSprint5Screenshots() async throws {
        let client = Sprint3ScreenshotClient()
        let store = FeedStore(gmail: client, summarizeOnDevice: false, cacheStore: nil, veto: nil)
        await store.load()
        await store.sentCheck?.value
        try await capture(NavigationStack { TestingToolsView() }.environment(store).environment(Router()), name: "24-Testing-tools-brief")
        if let item = store.waitingOnThem.first {
            let person = GmailMessageParser.person(fromHeader: item.email.to.first ?? "")
            try await capture(NavigationStack { ThreadView(person: person) }.environment(store).environment(Router()), name: "25-Person-waiting-on-them-row")
        }
    }
    private func demoStore() async -> FeedStore {
        let store = FeedStore(gmail: ScreenshotInboxClient(), summarizeOnDevice: false, cacheStore: nil)
        await store.load()
        XCTAssertEqual(store.mode, .sample)
        return store
    }
    private func foregroundScene() async throws -> UIWindowScene {
        for _ in 0..<100 {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) { return scene }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }, "No foreground scene became available within 10 seconds.")
    }
    private func capture<Content: View>(_ content: Content, name: String, dark: Bool = false) async throws {
        let scene = try await foregroundScene()
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let controller = UIHostingController(rootView: content.preferredColorScheme(dark ? .dark : .light))
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKey() }
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)
        window.layoutIfNeeded()
        XCTAssertEqual(scene.activationState, .foregroundActive)
        XCTAssertTrue(window.windowScene === scene)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true), "Foreground hierarchy capture failed")
        }
        XCTAssertGreaterThan(image.size.width, 0)
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class ScreenshotInboxClient: GmailInboxClient {
    let config = GmailConfig(clientID: "")
    var isSignedIn: Bool { false }
    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits) async throws -> MailboxSnapshot { XCTFail("Screenshot capture must never fetch Gmail"); return .empty }
    func signIn() async throws { XCTFail("Screenshot capture must never sign in") }
    func trash(messageID: String) async throws { XCTFail("Screenshot capture must never trash") }
    func untrash(messageID: String) async throws { XCTFail("Screenshot capture must never trash") }
    func markRead(messageID: String) async throws { XCTFail("Screenshot capture must never change Gmail") }
    func markUnread(messageID: String) async throws { XCTFail("Screenshot capture must never change Gmail") }
    func signOut() {}
}

/// Fictional signed-in mailbox for Sprint 3 screenshots: one unread message, one ask you sent, one promise you made.
@MainActor
private final class Sprint3ScreenshotClient: GmailInboxClient {
    let config = GmailConfig(clientID: "123-fixture.apps.googleusercontent.com")
    var isSignedIn: Bool { true }
    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits) async throws -> MailboxSnapshot {
        let now = Date()
        let owner = Person(id: "pat@lovely.example", name: "Pat Owner", email: "pat@lovely.example", hue: 0.5)
        let dana = Person(id: "dana.reyes@mail.example", name: "Dana Reyes", email: "dana.reyes@mail.example", hue: 0.3)
        let unread = Email(id: "u1", threadId: "tu1", from: dana, to: ["pat@lovely.example"], subject: "Carnival volunteers",
                           date: now.addingTimeInterval(-3 * 86_400), body: "The volunteer list is posted in the front hall.", isUnread: true)
        let ask = Email(id: "s1", threadId: "ts1", from: owner, to: ["Sam Ortiz <sam.ortiz@mail.example>"], subject: "Roster",
                        date: now.addingTimeInterval(-5 * 86_400), body: "Hi Sam,\nCan you send the roster by Friday?", isUnread: false, isFromMe: true)
        let promise = Email(id: "s2", threadId: "ts2", from: owner, to: ["Lee Park <lee.park@mail.example>"], subject: "Signed form",
                            date: now.addingTimeInterval(-2 * 86_400), body: "Thanks Lee.\nI'll send the signed form tonight.", isUnread: false, isFromMe: true)
        return MailboxSnapshot(account: "pat@lovely.example", inbox: [unread], sent: [ask, promise], fetchedAt: now)
    }
    func trash(messageID: String) async throws { XCTFail("Screenshot capture must never trash") }
    func untrash(messageID: String) async throws { XCTFail("Screenshot capture must never trash") }
    func markRead(messageID: String) async throws { XCTFail("Screenshot capture must never change Gmail") }
    func markUnread(messageID: String) async throws { XCTFail("Screenshot capture must never change Gmail") }
    func signIn() async throws {}
    func signOut() {}
}
