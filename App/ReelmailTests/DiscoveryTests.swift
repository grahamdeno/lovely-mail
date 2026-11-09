import XCTest
@testable import Reelmail

/// Proposing children and properties from fictional mail, with evidence. Never assumed, only offered.
final class DiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func mail(_ subject: String, _ text: String, daysAgo: Double = 1) -> Discovery.Mail {
        Discovery.Mail(subject: subject, text: text, fromAddress: "office@school.example", date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    func testChildrenFromSchoolAndCareMail() {
        let mails = [
            mail("Attendance", "Dear parent of Milo, the school noticed an absence."),
            mail("Invoice", "Invoice for Milo Parker, tuition for March."),
            mail("Report cards", "Juniper's report card is ready in the student portal."),
            mail("Field trip", "Juniper's permission slip for the class field trip is due."),
            mail("Gift shipped", "Your gift for Oliver has shipped."),           // no kid context: ignored
            mail("Team news", "Coach Dana Parker says practice moves to Thursday."),  // owner's last name, but only once
        ]
        let found = Discovery.kids(in: mails, ownerName: "Pat Parker", known: [])
        XCTAssertEqual(found.map(\.name), ["Juniper", "Milo"])
        XCTAssertEqual(found.first { $0.name == "Milo" }?.count, 2)
        XCTAssertTrue(Discovery.kids(in: mails, ownerName: "Pat Parker", known: ["milo", "Juniper"]).isEmpty, "Already added")
    }

    func testOwnersOwnNameAndGreetingsAreNeverChildren() {
        let mails = [mail("Class", "Dear Parents, Pat Parker signed up. Student: Pat"), mail("Class", "Student: Pat. Dear Families")]
        XCTAssertTrue(Discovery.kids(in: mails, ownerName: "Pat Parker", known: []).isEmpty)
    }

    func testPropertiesFromHomeMailNotShipping() {
        let mails = [
            mail("Mortgage statement", "Property: 12 Maple Court, Springfield. Escrow balance attached."),
            mail("Electric bill", "Service address 12 Maple Ct. Amount due $120."),
            mail("Your order has shipped", "Ship to 77 Birch Lane, out for delivery today."),
            mail("Order delivered", "Delivered to 77 Birch Lane, utility closet."),
            mail("Closing", "Final docs for the sale of 88 Spruce Lane are ready. Title company attached.", daysAgo: 400),
            mail("Homeowners policy", "Policy for 88 Spruce Lane cancelled; we no longer own it.", daysAgo: 390),
        ]
        let found = Discovery.properties(in: mails, known: [], now: now)
        XCTAssertEqual(Set(found.map(\.name)), ["12 Maple", "88 Spruce"])
        XCTAssertEqual(found.first { $0.name == "88 Spruce" }?.looksPast, true)
        XCTAssertEqual(found.first { $0.name == "12 Maple" }?.looksPast, false)
    }
}
