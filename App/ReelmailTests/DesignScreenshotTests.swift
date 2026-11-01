import XCTest
import SwiftUI
import UIKit
@testable import Reelmail

/// Rendered evidence only: these tests do not assert visual quality or replace device review.
@MainActor
final class DesignScreenshotTests: XCTestCase {
    func testHomeScreenshot() async throws {
        let store = await demoStore()
        let router = Router()
        try await capture(RootView().environment(store).environment(router), name: "01-Home-demo")
    }

    func testPeopleScreenshot() async throws {
        let store = await demoStore()
        let router = Router()
        router.tab = .people
        try await capture(RootView().environment(store).environment(router), name: "02-People-demo")
    }

    func testTimelineScreenshot() async throws {
        let store = await demoStore()
        let router = Router()
        let person = try XCTUnwrap(store.people.first)
        try await capture(
            NavigationStack { ThreadView(person: person) }.environment(store).environment(router),
            name: "03-Timeline-demo")
    }

    private func demoStore() async -> FeedStore {
        let store = FeedStore(gmail: ScreenshotInboxClient(), summarizeOnDevice: false)
        await store.load()
        XCTAssertEqual(store.mode, .sample)
        return store
    }

    private func capture<Content: View>(_ content: Content, name: String) async throws {
        let controller = UIHostingController(rootView: content.preferredColorScheme(.light))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)
        window.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true),
                          "View hierarchy could not be captured")
        }
        XCTAssertGreaterThan(image.size.width, 0)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class ScreenshotInboxClient: GmailInboxClient {
    let config = GmailConfig(clientID: "")
    var isSignedIn: Bool { false }
    func fetchInbox(maxResults: Int) async throws -> [Email] {
        XCTFail("Screenshot capture must never fetch Gmail")
        return []
    }
    func signIn() async throws { XCTFail("Screenshot capture must never sign in") }
    func signOut() {}
}
