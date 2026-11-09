import XCTest

/// Scrolling, tab switching and launch, measured with Apple's own metrics. The numbers land in the result bundle;
/// scripts/export_audit.py reads them into audit-summary.json. Simulator numbers show relative problems, not a phone's frame rate.
final class AuditSmoothness: XCTestCase {
    private let arguments = ["-uiTestFixtures", "-uiTestAppearance", "light", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-lovely.launchAnimation", "NO"]

    private func options() -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = 5
        return o
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 30), "Home appears")
        // Let the first load and the background reading of older mail finish before measuring.
        _ = app.buttons["home.nextup.open"].waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 6)
        return app
    }

    func testLaunch() {
        let app = XCUIApplication()
        app.launchArguments = arguments
        measure(metrics: [XCTApplicationLaunchMetric()], options: options()) {
            app.launch()
            app.terminate()
        }
    }

    func testHomeScrolling() {
        let app = launched()
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTHitchMetric(application: app)], options: options()) {
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
        app.terminate()
    }

    func testTabSwitching() {
        let app = launched()
        measure(metrics: [XCTHitchMetric(application: app), XCTClockMetric()], options: options()) {
            for tab in ["tab.people", "tab.search", "tab.home", "tab.people", "tab.home"] {
                app.buttons[tab].tap()
            }
        }
        app.terminate()
    }
}
