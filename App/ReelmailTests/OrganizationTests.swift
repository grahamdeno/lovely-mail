import XCTest
@testable import Reelmail

final class OrganizationTests: XCTestCase {
    private func person(_ name: String, _ email: String) -> Person { Person(id: email, name: name, email: email, hue: 0.3) }

    func testSendersGroupByCompanyDomain() {
        XCTAssertEqual(OrganizationKey.domain(of: "fidelityinvestments@mail.fidelity.com"), "fidelity.com")
        XCTAssertEqual(OrganizationKey.domain(of: "x@shareholderdocs.fidelity.com"), "fidelity.com")
        XCTAssertEqual(OrganizationKey.domain(of: "videoappointment@va.gov"), "va.gov")
        XCTAssertEqual(OrganizationKey.domain(of: "news@shop.co.uk"), "shop.co.uk")
        let a = person("Fidelity Investments", "fidelityinvestments@mail.fidelity.com")
        let b = person("Fidelity Investments Email", "fidelityinvestmentsemail@shareholderdocs.fidelity.com")
        XCTAssertEqual(OrganizationKey.key(for: a, overrides: [:]), OrganizationKey.key(for: b, overrides: [:]))
    }

    func testSharedServicesGroupByName() {
        XCTAssertNil(OrganizationKey.domain(of: "invoice@privaterelay.appleid.com"))
        XCTAssertNil(OrganizationKey.domain(of: "pisa.recreation@gmail.com"))
        XCTAssertNil(OrganizationKey.domain(of: "irs@service.govdelivery.com"))
        let league = person("PISA Recreation", "pisa.recreation@gmail.com")
        let other = person("Garden Club", "garden.club@gmail.com")
        XCTAssertNotEqual(OrganizationKey.key(for: league, overrides: [:]), OrganizationKey.key(for: other, overrides: [:]))
    }

    func testMergeAndSplitOverridesWin() {
        let a = person("Schwab Funds", "funds@schwab.example")
        XCTAssertEqual(OrganizationKey.key(for: a, overrides: ["funds@schwab.example": "d:fidelity.com"]), "d:fidelity.com")
        XCTAssertEqual(OrganizationKey.key(for: a, overrides: ["funds@schwab.example": OrganizationKey.splitKey(for: "Funds@Schwab.example")]),
                       "s:funds@schwab.example")
    }

    func testGroupNameIsTheMostCommonDisplayName() {
        let senders = [person("Fidelity Investments", "a@mail.fidelity.com"), person("Fidelity Investments", "a@mail.fidelity.com"),
                       person("Fidelity Investments Email", "b@shareholderdocs.fidelity.com")]
        XCTAssertEqual(OrganizationKey.displayName(for: senders, key: "d:fidelity.com"), "Fidelity Investments")
    }

    @MainActor
    func testOverridesPersistAndOldStateDecodes() throws {
        let suite = "lovely.org-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"messages":{},"senders":{}}"#.utf8), forKey: "reelmail.triage.v1.acct")
        let rules = LocalTriageRules(accountID: "acct", defaults: defaults)
        XCTAssertTrue(rules.organizationOverrides.isEmpty)
        XCTAssertTrue(rules.setOrganization(sender: "Funds@Schwab.example", groupKey: "d:fidelity.com"))
        XCTAssertEqual(LocalTriageRules(accountID: "acct", defaults: defaults).organizationOverrides, ["funds@schwab.example": "d:fidelity.com"])
    }
}
