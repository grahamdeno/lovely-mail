import XCTest
@testable import Reelmail

/// Settings top level shows each topic's current value (Nov 9 redesign).
final class SettingsLayoutTests: XCTestCase {
    func testBriefTimeLabel() {
        XCTAssertEqual(SettingsView.timeLabel(570), "9:30 AM")
        XCTAssertEqual(SettingsView.timeLabel(0), "12:00 AM")
        XCTAssertEqual(SettingsView.timeLabel(19 * 60), "7:00 PM")
    }
}
