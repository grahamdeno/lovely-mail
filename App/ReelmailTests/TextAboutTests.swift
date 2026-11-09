import XCTest
@testable import Reelmail

final class TextAboutTests: XCTestCase {
    func testDraftSummarizesAndOpensAConversation() {
        let d = TextAbout.draft(fromName: "Infinitecampus", subject: "High School Specialty Programs",
                                blurb: "Three parent nights on high school programs, all at 6 PM.", sensitive: false, dateLabel: "Mon, Nov 9")
        XCTAssertTrue(d.hasPrefix("Got an email from Infinitecampus about \u{201C}High School Specialty Programs\u{201D}."))
        XCTAssertTrue(d.contains("Three parent nights"))
        XCTAssertTrue(d.contains("Date: Mon, Nov 9."))
        XCTAssertTrue(d.hasSuffix("Want to talk about it?"))
    }

    func testSensitiveMailGetsNoSummary() {
        let d = TextAbout.draft(fromName: "Clinic", subject: "Your results", blurb: "Private details", sensitive: true, dateLabel: "Tue")
        XCTAssertFalse(d.contains("Private details"))
        XCTAssertFalse(d.contains("Date:"))
    }

    func testDraftStaysShort() {
        let d = TextAbout.draft(fromName: "A", subject: "B", blurb: String(repeating: "word ", count: 200), sensitive: false, dateLabel: nil)
        XCTAssertLessThanOrEqual(d.count, TextAbout.maxLength + 2)
        XCTAssertTrue(d.hasSuffix("Want to talk about it?"))
    }

    func testRecipientsMostRecentFirstAndCapped() {
        let defaults = UserDefaults(suiteName: "TextAboutTests")!
        defaults.removePersistentDomain(forName: "TextAboutTests")
        let store = TextRecipients(defaults: defaults)
        for i in 1...7 { store.remember(TextRecipient(name: "Person \(i)", phone: "+1 555 000 000\(i)")) }
        store.remember(TextRecipient(name: "Person 3", phone: "+15550000003"))
        XCTAssertEqual(store.all.count, TextRecipients.max)
        XCTAssertEqual(store.all.first?.name, "Person 3", "Most recent first, no duplicates by number")
        store.forget(store.all[0])
        XCTAssertFalse(store.all.contains { $0.name == "Person 3" })
        XCTAssertEqual(TextAboutSheet.smsURL(phone: "+1 (555) 000-0001", body: "Hi there")?.absoluteString, "sms:+15550000001?body=Hi%20there")
    }

    /// The email screen's "…" menu names the last person he texted about an email.
    func testMenuNamesTheLastPersonTexted() {
        XCTAssertEqual(OpenEmailView.textAboutTitle(nil), "Text someone about this")
        XCTAssertEqual(OpenEmailView.textAboutTitle(TextRecipient(name: "Sam Rivera", phone: "+15550100")), "Text Sam about this")
    }
}
