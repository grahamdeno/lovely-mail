import XCTest
@testable import Reelmail

final class FallbackSummarizerTests: XCTestCase {
    private let summarizer = FallbackSummarizer()

    private func summary(_ id: String) throws -> EmailSummary {
        let email = try XCTUnwrap(SampleData.emails.first { $0.id == id })
        return summarizer.summarizeSync(SummaryInput(email: email))
    }

    func testHeadlineAndBlurbRespectWordLimits() {
        for email in SampleData.emails {
            let s = summarizer.summarizeSync(SummaryInput(email: email))
            XCTAssertLessThanOrEqual(TextClamp.wordCount(s.headline), FallbackSummarizer.headlineMaxWords, email.id)
            XCTAssertLessThanOrEqual(TextClamp.wordCount(s.blurb), FallbackSummarizer.blurbMaxWords, email.id)
            XCTAssertFalse(s.headline.isEmpty, email.id)
            XCTAssertFalse(s.blurb.isEmpty, email.id)
            XCTAssertEqual(s.engine, .fallback)
        }
    }

    func testBlurbSkipsGreetingAndTakesFirstSentence() throws {
        let s = try summary("e13")
        XCTAssertEqual(s.blurb, "It's been ages!")
    }

    func testStripsReplyPrefixFromHeadline() throws {
        XCTAssertEqual(try summary("e19").headline, "Saturday hike?")
    }

    func testNeedsReplyForPeopleAskingQuestions() throws {
        XCTAssertTrue(try summary("e01").needsReply)   // "Want to join?"
        XCTAssertTrue(try summary("e02").needsReply)   // "Please confirm"
        XCTAssertTrue(try summary("e10").needsReply)   // "Can you bring a dessert?"
    }

    func testNoReplyForAutomatedOrInformational() throws {
        XCTAssertFalse(try summary("e05").needsReply)  // receipt
        XCTAssertFalse(try summary("e06").needsReply)  // newsletter
        XCTAssertFalse(try summary("e07").needsReply)  // photos, no question
        XCTAssertFalse(try summary("e14").needsReply)  // verification code
    }

    func testCategories() throws {
        XCTAssertEqual(try summary("e05").category, .money)
        XCTAssertEqual(try summary("e06").category, .newsletter)
        XCTAssertEqual(try summary("e08").category, .travel)
        XCTAssertEqual(try summary("e03").category, .school)
        XCTAssertEqual(try summary("e15").category, .work)
        XCTAssertEqual(try summary("e13").category, .people)
        XCTAssertEqual(try summary("e12").category, .updates)
    }

    func testSensitive() throws {
        XCTAssertTrue(try summary("e14").sensitive)
        XCTAssertFalse(try summary("e01").sensitive)
    }

    func testDateExtraction() {
        XCTAssertEqual(FallbackSummarizer.dates(in: "Final is on Nov 7, photos Nov 7, trip March 24."), ["Nov 7", "Mar 24"])
        XCTAssertEqual(FallbackSummarizer.dates(in: "No dates here."), [])
    }

    func testPastedTextParsesHeaders() {
        let input = SummaryInput(pasted: SampleData.labPasteExample)
        XCTAssertEqual(input.sender, "Jordan Lee")
        XCTAssertEqual(input.subject, "Book club moved to Thursday")
        let s = summarizer.summarizeSync(input)
        XCTAssertTrue(s.needsReply)
        XCTAssertEqual(s.dates, ["Nov 13"])
    }

    func testClampAddsEllipsis() {
        XCTAssertEqual(TextClamp.words("one two three four", max: 2), "one two…")
        XCTAssertEqual(TextClamp.words("one two", max: 2), "one two")
    }
}
