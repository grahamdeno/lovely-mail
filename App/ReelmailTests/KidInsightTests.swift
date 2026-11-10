import XCTest
@testable import Reelmail

final class KidInsightTests: XCTestCase {
    private func post(_ id: String, from: String = "Office <office@school.example>", subject: String, body: String = "") -> Post {
        let email = Email(id: id, threadId: id, from: Person(id: from, name: from, email: "office@school.example", hue: 0.5), to: ["me@example.com"],
                          subject: subject, date: Date(), body: body)
        return Post(email: email, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: email)))
    }

    private let kid = KidProfile(id: "k", name: "Alex", school: "Maple Middle", teacherNames: ["Ms. Rivera"], activities: ["trumpet", "soccer"])

    func testNameOrSchoolOrTeacherMatchesAlone() {
        let posts = [post("1", subject: "Alex needs a form signed"), post("2", subject: "Maple Middle picture day"),
                     post("3", subject: "Note from Ms. Rivera"), post("4", subject: "Lunch menu")]
        XCTAssertEqual(Set(KidInsights.mail(for: kid, in: posts).map(\.id)), ["1", "2", "3"])
    }

    func testActivityNeedsASecondReason() {
        let lone = post("5", subject: "Soccer sign-ups open")
        XCTAssertTrue(KidInsights.mail(for: kid, in: [lone]).isEmpty)
        let both = post("6", subject: "Soccer sign-ups open", body: "Bring trumpet cases to the gym too.")
        XCTAssertEqual(KidInsights.mail(for: kid, in: [both]).count, 1)
    }

    func testChunksRespectLimitAndKeepEverything() {
        let paragraph = String(repeating: "word ", count: 200)
        let body = (0..<6).map { _ in paragraph }.joined(separator: "\n\n")
        let chunks = NewsletterChunker.chunks(body, limit: 2_500)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 2_500 })
        XCTAssertEqual(chunks.joined(separator: "\n\n").split(whereSeparator: { $0.isWhitespace }).count, 1_200)
        let huge = String(repeating: "abc ", count: 2_000)
        XCTAssertTrue(NewsletterChunker.chunks(huge).allSatisfy { $0.count <= 2_500 })
    }

    func testMergeDedupesAndCapsAtFive() {
        let merged = NewsletterChunker.merge([["Picture day Nov 5", "Bring form"], ["picture day nov 5!", "A", "B", "C", "D"]])
        XCTAssertEqual(merged.count, 5)
        XCTAssertEqual(merged.filter { $0.lowercased().contains("picture day") }.count, 1)
    }

    func testNextShowsSoonestUpcomingDate() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 19))!
        func dated(_ id: String, _ subject: String, _ body: String) -> KidMail {
            let email = Email(id: id, threadId: id, from: Person(id: "o", name: "Office", email: "office@school.example", hue: 0.5),
                              to: ["me@example.com"], subject: subject, date: now.addingTimeInterval(-3_600), body: body)
            return KidMail(post: Post(email: email, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: email))), reasons: ["Names Alex"])
        }
        let mail = [dated("a", "Band concert", "The concert is on Nov 20 at 7 PM."),
                    dated("b", "Busch Gardens Trip Reminder", "The trip is on Nov 12. Bring lunch."),
                    dated("c", "Lunch menu", "Pizza is popular.")]
        let next = KidInsights.next(for: kid, mail: mail, now: now, calendar: cal)
        XCTAssertEqual(next?.postID, "b", "The soonest date wins, not the newest mail")
        XCTAssertEqual(next?.what, "Busch Gardens Trip", "Reminder is dropped from the title")
        XCTAssertNil(KidInsights.next(for: kid, mail: [mail[2]], now: now, calendar: cal), "No date, nothing coming up")
    }

    func testShortTitleCutsAtAWord() {
        XCTAssertEqual(KidInsights.shortTitle("Reminder: Picture day"), "Picture day")
        let long = KidInsights.shortTitle("High School Specialty Programs Information Night")
        XCTAssertTrue(long.count <= 29 && long.hasSuffix("\u{2026}"), long)
        XCTAssertFalse(long.contains("Informat\u{2026}"), "Never cuts mid-word")
    }
}
