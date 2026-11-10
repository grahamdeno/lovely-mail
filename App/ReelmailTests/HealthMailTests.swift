import XCTest
@testable import Reelmail

/// Fictional senders only.
final class HealthMailTests: XCTestCase {
    func testCarClaimsAndServiceAppointmentsAreNotHealth() {
        XCTAssertFalse(HealthMail.isHealth(address: "adjuster@example-insurance.com", name: "Claims Team", subject: "Your claim 12-3456"))
        XCTAssertFalse(HealthMail.isHealth(address: "service@example-motors.com", subject: "Your service appointment is confirmed"))
    }

    func testRealHealthMailStillIs() {
        XCTAssertTrue(HealthMail.isHealth(address: "no-reply@exampleclinic.org", subject: "Your appointment"))
        XCTAssertTrue(HealthMail.isHealth(address: "noreply@example.com", subject: "Your lab results are ready"))
        XCTAssertTrue(HealthMail.isHealth(address: "billing@example.com", subject: "Explanation of benefits"))
    }

    func testNotHealthOverride() {
        let d = UserDefaults(suiteName: "health-\(UUID().uuidString)")!
        XCTAssertFalse(HealthOverrides.isNotHealth("Adjuster@Example.com", defaults: d))
        HealthOverrides.markNotHealth("Adjuster@Example.com", defaults: d)
        XCTAssertTrue(HealthOverrides.isNotHealth("adjuster@example.com", defaults: d))
    }
}
