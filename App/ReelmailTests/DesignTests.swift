import XCTest
@testable import Reelmail

final class DesignTests: XCTestCase {
    func testNestedRadiiFollowOuterEqualsInnerPlusPadding() {
        XCTAssertEqual(RM.Radius.nested(inner: 8, padding: 8), 16)
        XCTAssertEqual(RM.Radius.button, 8)
        XCTAssertEqual(RM.Radius.card, RM.Radius.button + RM.Radius.cardPadding)
        XCTAssertEqual(RM.Radius.card, 16)
        XCTAssertEqual(RM.Radius.sheet, RM.Radius.card + RM.Radius.sheetPadding)
        XCTAssertEqual(RM.Radius.sheet, 24)
        XCTAssertEqual(RM.Radius.activeTab, 12)
        XCTAssertEqual(RM.Radius.tabBar, RM.Radius.activeTab + RM.Radius.tabBarPadding)
        XCTAssertEqual(RM.Radius.tabBar, 18)
    }

    func testAvatarsAreRoundedSquaresAtQuarterSize() {
        XCTAssertEqual(RM.Radius.avatar(size: 56), 14)
        XCTAssertEqual(RM.Radius.avatar(size: 40), 10)
        XCTAssertEqual(RM.Radius.avatarRing(size: 56, gap: 3), 17)
    }

    func testTabIndicatorFitsBarPaddingAndRollsAQuarterTurnPerTab() {
        XCTAssertEqual(RollingTabBar.indicatorSize + RM.Radius.tabBarPadding * 2, RollingTabBar.barHeight)
        XCTAssertEqual(RollingTabBar.rotation(forIndex: 0), 0)
        XCTAssertEqual(RollingTabBar.rotation(forIndex: 3), 270)
    }

    func testTabOrderIsRightThumbFirst() {
        XCTAssertEqual(AppTab.allCases, [.profile, .search, .new, .people, .home])
    }
}
