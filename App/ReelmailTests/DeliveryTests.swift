import XCTest
@testable import Reelmail

final class DeliveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private var context: TriageContext { TriageContext(myAddresses: ["pat@lovely.example"], otherAddresses: [], now: now) }

    private func mail(from: String, name: String = "Sender", subject: String, body: String, bulk: Bool = false) -> Email {
        Email(id: UUID().uuidString, threadId: "t", from: Person(id: from, name: name, email: from, hue: 0.3), to: ["pat@lovely.example"],
              subject: subject, date: now.addingTimeInterval(-86_400), body: body, bulk: bulk)
    }
    private func section(_ email: Email) -> FeedSection {
        let post = Post(email: email, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: email)))
        return FeedTriage.assess(post, route: .inbox, context: context).section
    }

    func testShippingSenderWords() {
        XCTAssertTrue(DeliveryNotice.shippingSender("tracking@shipco.example"))
        XCTAssertTrue(DeliveryNotice.shippingSender("orders.desk@shop.example"))
        XCTAssertTrue(DeliveryNotice.shippingSender("order-update@shop.example"))
        XCTAssertFalse(DeliveryNotice.shippingSender("dana.reyes@mail.example"))
    }

    func testPlainTrackingAddressIsUpdates() {
        let email = mail(from: "tracking@shipco.example", name: "ShipCo", subject: "Out for delivery", body: "Your package is out for delivery today.")
        XCTAssertEqual(section(email), .updates)
    }

    func testBulkNoticeIsUpdates() {
        let email = mail(from: "notifications@parcelhub.example", name: "ParcelHub", subject: "Your package",
                         body: "Your order has been delivered. Track your package at the link below.", bulk: true)
        XCTAssertEqual(section(email), .updates)
    }

    func testAPersonSayingDeliveredStaysWithPeople() {
        let email = mail(from: "sam.ortiz@mail.example", name: "Sam Ortiz", subject: "Box", body: "Thanks, the box was delivered this morning. All good.")
        XCTAssertFalse(DeliveryNotice.isDeliveryNotice(email))
        XCTAssertEqual(section(email), .people)
    }

    func testDeliveryNoticeYieldsNoDates() {
        let email = mail(from: "tracking@shipco.example", name: "ShipCo", subject: "Arriving tomorrow", body: "Your package is arriving tomorrow at 2 PM.")
        XCTAssertTrue(MailDates.extract(email, now: now).isEmpty)
    }

    func testBulkNewsletterWithFooterNamingDaysIsReading() {
        let email = mail(from: "menu@dinnernotes.example", name: "Dinner Notes", subject: "Monday menu ideas",
                         body: "Easy dinners for Monday through Friday.\nView this email in your browser.", bulk: true)
        XCTAssertEqual(section(email), .reading)
    }
}
