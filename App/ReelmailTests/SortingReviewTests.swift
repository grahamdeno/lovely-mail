import XCTest
@testable import Reelmail

@MainActor
final class SortingReviewTests: XCTestCase {
    func testVerdictsPersistPerAccount() throws {
        let suite = "lovely.review-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let review = SortingReview(accountID: "a", defaults: defaults)
        review.mark("m1", shown: .waiting, correct: .waiting)
        review.mark("m2", shown: .people, correct: .waiting)
        let reloaded = SortingReview(accountID: "a", defaults: defaults)
        XCTAssertEqual(reloaded.verdict(for: "m1")?.isRight, true)
        XCTAssertEqual(reloaded.verdict(for: "m2")?.correct, FeedSection.waiting.rawValue)
        XCTAssertTrue(SortingReview(accountID: "b", defaults: defaults).verdicts.isEmpty, "Accounts never share verdicts")
        reloaded.clear("m1")
        XCTAssertNil(SortingReview(accountID: "a", defaults: defaults).verdict(for: "m1"))
    }

    func testSummaryHidesNamesAddressesAndSubjectsByDefault() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let miss = SortingReview.Verdict(shown: FeedSection.people.rawValue, correct: FeedSection.waiting.rawValue, reviewedAt: now)
        let hit = SortingReview.Verdict(shown: FeedSection.updates.rawValue, correct: FeedSection.updates.rawValue, reviewedAt: now)
        let items = [
            SortingReviewSummary.Item(verdict: miss, reason: "From Dana. Nothing asked of you.", senderFirstName: "Dana",
                                      senderAddress: "dana@mail.example", subject: "Signed form"),
            SortingReviewSummary.Item(verdict: hit, reason: "Sent from a system address", senderFirstName: "Fabrikam",
                                      senderAddress: "orders@fabrikam.example", subject: "Shipped"),
        ]
        let text = SortingReviewSummary.text(items, includeSubjects: false, date: now)
        XCTAssertTrue(text.contains("Reviewed 2, right 1 (50%)"), text)
        XCTAssertTrue(text.contains("Shown in People, belongs in Waiting on you. Reason: From Sender. Nothing asked of you."), text)
        XCTAssertFalse(text.contains("Dana"))
        XCTAssertFalse(text.contains("Signed form"))
        XCTAssertTrue(SortingReviewSummary.text(items, includeSubjects: true, date: now).contains("Subject: Signed form"))
    }
}
