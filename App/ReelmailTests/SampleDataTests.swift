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

    func testSampleMixFeedsEverySection() {
        let fallback = FallbackSummarizer()
        let posts = SampleData.emails.map { Post(email: $0, summary: fallback.summarizeSync(SummaryInput(email: $0))) }
        let replies = FeedTriage.latestReplies(in: SampleData.sentByMe)
        let sections = Set(posts.map { FeedTriage.section(for: $0, route: .inbox, replies: replies) })
        for section in FeedSection.allCases {
            XCTAssertTrue(sections.contains(section), "\(section) is empty")
        }
        XCTAssertGreaterThanOrEqual(posts.filter(\.summary.needsReply).count, 3)
    }
}
