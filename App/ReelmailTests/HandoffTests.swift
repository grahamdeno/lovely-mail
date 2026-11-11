import XCTest
@testable import Reelmail

final class HandoffTests: XCTestCase {
    func testPlantedSecretsAreRemoved() {
        let text = """
        Your verification code is 483920. Password: Hunter2!x
        Card 4111 1111 1111 1111, SSN 123-45-6789, account number 99887766
        Confirmation #AB12CD34. Reach me at dana@example.com or keep@example.org.
        Open https://pay.example.com/checkout?token=SECRET123&u=1
        """
        let out = Redactor.redact(text, keepEmails: ["keep@example.org"])
        for secret in ["483920", "Hunter2", "4111", "123-45-6789", "99887766", "AB12CD34", "dana@example.com", "SECRET123"] {
            XCTAssertFalse(out.contains(secret), "leaked \(secret)")
        }
        XCTAssertTrue(out.contains("keep@example.org"))
        XCTAssertTrue(out.contains("https://pay.example.com/checkout"))
    }

    func testResetLinksAndLongTokensAreRemoved() {
        let out = Redactor.redact("Reset: https://acct.example.com/reset/AbCdEf0123456789xyz then use eyJhbGciOiJIUzI1NiJ9abc123")
        XCTAssertFalse(out.contains("AbCdEf0123456789xyz"))
        XCTAssertFalse(out.contains("eyJhbGciOiJIUzI1NiJ9abc123"))
        XCTAssertTrue(out.contains("https://acct.example.com/reset/"))
    }

    func testHealthAndSensitiveMailNeverBecomePrompts() {
        XCTAssertFalse(HandoffPrompt.isAllowed(address: "no-reply@exampleclinic.org", subject: "Your appointment", sensitive: false))
        XCTAssertFalse(HandoffPrompt.isAllowed(address: "orders@shop.example", subject: "Your order", sensitive: true))
        XCTAssertTrue(HandoffPrompt.isAllowed(address: "orders@shop.example", subject: "Your order", sensitive: false))
        // A health portal on a subdomain, or named as one, is health mail even when the company domain is not.
        XCTAssertFalse(HandoffPrompt.isAllowed(address: "noreply@mychart.example.org", subject: "New message", sensitive: false))
        XCTAssertFalse(HandoffPrompt.isAllowed(address: "noreply@example.org", name: "Example Pediatrics", subject: "New message", sensitive: false))
    }

    /// One email adds only its sender and subject to a Grok hand-off, redacted, and nothing from health mail.
    func testEmailFactsForGrokAreRedactedAndSkipHealth() {
        let facts = GrokHandoff.facts(from: "Oak Court Leasing", subject: "Code 482913 for your renewal", isHealth: false)
        XCTAssertEqual(facts.count, 1)
        XCTAssertTrue(facts[0].text.contains("Oak Court Leasing"))
        XCTAssertFalse(facts[0].text.contains("482913"))
        XCTAssertTrue(GrokHandoff.facts(from: "Example Pediatrics", subject: "Results", isHealth: true).isEmpty)
    }
}
