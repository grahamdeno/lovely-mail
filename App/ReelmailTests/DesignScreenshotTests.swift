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
    private func capture<Content: View>(_ content: Content, name: String) async throws {
        let scene = try await foregroundScene()
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let controller = UIHostingController(rootView: content.preferredColorScheme(.light))
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
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
    func signOut() {}
}
