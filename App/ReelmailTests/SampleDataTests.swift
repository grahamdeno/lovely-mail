import XCTest
@testable import Reelmail

final class SampleDataTests: XCTestCase {
    func testAboutTwentyUniqueEmails() {
        let emails = SampleData.emails
        XCTAssertGreaterThanOrEqual(emails.count, 18)
        XCTAssertLessThanOrEqual(emails.count, 25)
        XCTAssertEqual(Set(emails.map(\.id)).count, emails.count)
    }

    func testAllAddressesAreFake() {
        for email in SampleData.emails + SampleData.sentByMe {
            XCTAssertTrue(email.from.email.hasSuffix(".example"), email.from.email)
        }
    }

    func testNewestFirst() {
        let dates = SampleData.emails.map(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testSampleMixFeedsEveryLens() {
        let fallback = FallbackSummarizer()
        let posts = SampleData.emails.map { Post(email: $0, summary: fallback.summarizeSync(SummaryInput(email: $0))) }
        for lens in Lens.allCases {
            XCTAssertFalse(posts.filter(lens.includes).isEmpty, "\(lens) is empty")
        }
        XCTAssertGreaterThanOrEqual(posts.filter(\.summary.needsReply).count, 3)
    }
}
