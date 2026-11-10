import XCTest
@testable import Reelmail

final class SplitPillTests: XCTestCase {
    func testQuestionsAskLovelyAndWordsSearch() {
        XCTAssertTrue(SplitPillBar.isQuestion("what does Julia need from me?"))
        XCTAssertTrue(SplitPillBar.isQuestion("mail from school this week"))
        XCTAssertFalse(SplitPillBar.isQuestion("julia"))
        XCTAssertFalse(SplitPillBar.isQuestion("costco order"))
    }
}
