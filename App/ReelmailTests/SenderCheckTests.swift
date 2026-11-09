import XCTest
@testable import Reelmail

/// Fictional senders only.
final class SenderCheckTests: XCTestCase {
    func testRealBrandMailPasses() {
        XCTAssertEqual(SenderCheck.check(name: "PayPal", address: "service@paypal.com", replyTo: nil,
                                         authResults: "mx.google.com; spf=pass; dkim=pass; dmarc=pass", known: false).level, .ok)
        XCTAssertEqual(SenderCheck.check(name: "Apple", address: "no_reply@email.apple.com", replyTo: nil, authResults: nil, known: false).level, .ok)
    }

    func testFailedAuthenticationWarns() {
        let v = SenderCheck.check(name: "Neighborhood News", address: "news@example-town.org", replyTo: nil,
                                  authResults: "mx.google.com; spf=fail; dkim=none; dmarc=fail", known: false)
        XCTAssertEqual(v.level, .warning)
        let lenient = SenderCheck.check(name: "Club List", address: "list@example-club.org", replyTo: nil,
                                        authResults: "mx.google.com; dkim=pass; spf=pass; dmarc=fail (p=NONE sp=NONE dis=NONE)", known: false)
        XCTAssertEqual(lenient.level, .caution)
    }

    func testBrandFromPersonalAddressWarns() {
        XCTAssertEqual(SenderCheck.check(name: "PayPal Support", address: "paypal.help.desk@gmail.com", replyTo: nil, authResults: nil, known: false).level, .warning)
    }

    func testLookalikeDomainsWarn() {
        XCTAssertEqual(SenderCheck.check(name: "Billing", address: "billing@paypa1.com", replyTo: nil, authResults: nil, known: false).level, .warning)
        XCTAssertEqual(SenderCheck.check(name: "Account", address: "a@amazon-secure-billing.com", replyTo: nil, authResults: nil, known: false).level, .warning)
        XCTAssertEqual(SenderCheck.check(name: "Shop", address: "hi@xn--pple-43d.com", replyTo: nil, authResults: nil, known: false).level, .warning)
    }

    func testAddressInNameWarns() {
        let v = SenderCheck.check(name: "support@apple.com", address: "x@mailer-zone.biz", replyTo: nil, authResults: nil, known: false)
        XCTAssertEqual(v.level, .warning)
    }

    func testPeopleAndLocalBusinessesAreNotFlagged() {
        XCTAssertEqual(SenderCheck.check(name: "Chase Miller", address: "chase.miller@gmail.com", replyTo: nil, authResults: nil, known: false).level, .ok)
        XCTAssertEqual(SenderCheck.check(name: "Apple Valley Dental", address: "office@applevalleydental.com", replyTo: nil, authResults: nil, known: false).level, .ok)
        XCTAssertEqual(SenderCheck.check(name: "Sam Rivera", address: "sam@riverafamily.net", replyTo: "sam.rivera@gmail.com", authResults: nil, known: true).level, .ok)
    }

    func testRepliesToPersonalAddressIsCaution() {
        let v = SenderCheck.check(name: "Prize Desk", address: "winners@prize-center.com", replyTo: "claims.office@gmail.com", authResults: nil, known: false)
        XCTAssertEqual(v.level, .caution)
    }
}
