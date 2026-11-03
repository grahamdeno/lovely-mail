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

    func testPeopleVersusOrganizations() {
        XCTAssertTrue(PersonSignals.looksLikePerson(name: "Mattie Pennington", email: "mattie.pennington@nhcs.net", youWrote: true))
        XCTAssertTrue(PersonSignals.looksLikePerson(name: "James Brendle", email: "james.brendle@ncfbins.com", youWrote: false))
        XCTAssertTrue(PersonSignals.looksLikePerson(name: "Julia DeNoyer", email: "denoyer.julia@gmail.com", youWrote: false))
        XCTAssertFalse(PersonSignals.looksLikePerson(name: "National Life Group", email: "admin@nationallife.com", youWrote: false))
        XCTAssertFalse(PersonSignals.looksLikePerson(name: "St. Andrews Reserve", email: "reply@aptleasing.info", youWrote: false))
        XCTAssertFalse(PersonSignals.looksLikePerson(name: "sender@getsongbpm.com", email: "sender@getsongbpm.com", youWrote: false))
        XCTAssertFalse(PersonSignals.looksLikePerson(name: "PISA Recreation", email: "pisa.recreation@gmail.com", youWrote: false))
        XCTAssertEqual(PersonSignals.mergeKey(for: "Julia DeNoyer"), PersonSignals.mergeKey(for: "julia denoyer"))
        XCTAssertNil(PersonSignals.mergeKey(for: "Julia"))
    }

    func testForwardRowTextAndNarrowSecrets() {
        let me = person("Pat", "pat@lovely.example")
        let fwd = Email(id: "f", threadId: "t", from: me, to: ["jess@mail.example"], subject: "Fwd: Your Costco.com order is confirmed!",
                        date: Date(), body: "---------- Forwarded message ---------\nFrom: Costco Orders <orders@costco.example>\nThanks for your order.",
                        isFromMe: true)
        XCTAssertEqual(ConversationPresentation.rowText(fwd, summary: nil), "You forwarded: Your Costco.com order is confirmed!")
        let school = Email(id: "s", threadId: "t2", from: person("Amy Hand", "amy@school.example"), to: ["pat@lovely.example"],
                           subject: "Attendance", date: Date(), body: "Sure, the transcript is attached here.")
        XCTAssertFalse(ConversationPresentation.isSensitive(school, summary: nil))
        let key = Email(id: "k", threadId: "t3", from: person("Song", "sender@song.example"), to: ["pat@lovely.example"],
                        subject: "Your API key", date: Date(), body: "Here is your API key: 1234")
        XCTAssertTrue(ConversationPresentation.isSensitive(key, summary: nil))
    }
}
