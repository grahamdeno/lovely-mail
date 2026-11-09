import XCTest
@testable import Reelmail

final class LaunchAnimationTests: XCTestCase {
    func testMarkGeometryMatchesTheIcon() {
        let size: CGFloat = 160
        // The stroke starts low-left and ends right of center; the dot sits up and to the right of the end.
        let start = LaunchAnimation.Mark.point(LaunchAnimation.Mark.icon(27, 72), in: size)
        let end = LaunchAnimation.Mark.point(LaunchAnimation.Mark.strokeEnd, in: size)
        let dot = LaunchAnimation.Mark.point(LaunchAnimation.Mark.dotCenter, in: size)
        XCTAssertTrue(start.x < end.x && start.y > 0 && start.y < size)
        XCTAssertTrue(dot.x > end.x && dot.y < end.y)
        XCTAssertTrue((0...size).contains(dot.x) && (0...size).contains(dot.y), "The dot is inside the launch mark")
        XCTAssertLessThan(LaunchAnimation.Mark.apex.y, LaunchAnimation.Mark.dotCenter.y, "The hop goes up before it lands")
        XCTAssertEqual(LaunchAnimation.Mark.strokeWidth(in: size), 7.5 * 1.1 / (724.0 / 10.24) * size, accuracy: 0.001)
    }

    func testOnByDefaultAndCanBeTurnedOff() {
        let key = LaunchAnimation.settingKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(LaunchAnimation.isOn)
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(LaunchAnimation.isOn)
    }
}
