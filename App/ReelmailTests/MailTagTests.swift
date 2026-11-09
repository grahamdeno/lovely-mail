import XCTest
@testable import Reelmail

/// Categories plus tags (owner, Nov 9, 2026). Fictional households, kids and mail.
final class MailTagTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)   // May 2033
    private var context: TagContext {
        TagContext(households: [
            Household(id: "h1", name: "12 Maple Court", endsOn: nil, payeeDomains: []),
            Household(id: "h2", name: "Harbor View Apartments", endsOn: nil, payeeDomains: ["utilitybilling.example"]),
            Household(id: "h3", name: "88 Spruce Lane", endsOn: Date(timeIntervalSince1970: 1_000_000_000), payeeDomains: []),
        ], kids: [KidProfile(id: "k1", name: "Avery", school: "Pine Ridge", teacherNames: [], activities: []),
                  KidProfile(id: "k2", name: "Rowan", school: "", teacherNames: [], activities: [])], now: now)
    }

    private func tags(_ category: Drawer, _ subject: String, _ text: String = "", from: String = "billing@company.example",
                      date: Date? = nil) -> [String] {
        MailTagger.tags(for: .init(category: category, fromAddress: from, subject: subject, text: text, date: date ?? now), context: context)
            .map(\.labelName)
    }

    func testElectricBillForTheHouse() {
        XCTAssertEqual(tags(.home, "Your electric bill is ready", "Service address: 12 Maple Court. Amount due $148."),
                       ["Lovely/Tag/Bill", "Lovely/Topic/Electric", "Lovely/Property/12 Maple Court"])
    }

    func testMortgageAndLinkedSender() {
        XCTAssertTrue(tags(.home, "Mortgage payment received", "Loan for 12 Maple Court").contains("Lovely/Topic/Mortgage"))
        XCTAssertTrue(tags(.home, "Monthly statement", from: "no-reply@utilitybilling.example").contains("Lovely/Property/Harbor View Apartments"),
                      "A sender linked to the property in Settings")
    }

    func testPropertyNeverFromAShippingAddressOrAPastHome() {
        XCTAssertFalse(tags(.orders, "Your order has shipped", "Ship to: 12 Maple Court").contains { $0.contains("Property") })
        XCTAssertFalse(tags(.home, "Closing documents", "Sale of 88 Spruce Lane").contains { $0.contains("Property") },
                       "Past properties are not suggested for new mail")
    }

    func testPeopleOnlyWhereNamesMeanTheChildren() {
        XCTAssertTrue(tags(.kids, "Avery's field trip", "Permission slip for Avery").contains("Lovely/Person/Avery"))
        XCTAssertTrue(tags(.money, "Rowan's account is active").contains("Lovely/Person/Rowan"))
        XCTAssertFalse(tags(.orders, "Gift for Avery shipped").contains("Lovely/Person/Avery"), "Names in shopping mail are gifts")
    }

    func testTaxYear() {
        let cal = Calendar(identifier: .gregorian)
        let feb = cal.date(from: DateComponents(year: 2026, month: 2, day: 10))!
        let dec = cal.date(from: DateComponents(year: 2025, month: 12, day: 16))!
        XCTAssertEqual(MailTagger.taxYear(hay: "your 1099-r is available", date: feb), 2025, "Jan to Apr: last year")
        XCTAssertEqual(MailTagger.taxYear(hay: "year end tax statement for 2025", date: dec), 2025)
        XCTAssertEqual(MailTagger.taxYear(hay: "form 1098 for tax year 2025", date: feb), 2025)
        XCTAssertNil(MailTagger.taxYear(hay: "your order has shipped", date: feb))
        XCTAssertTrue(tags(.money, "Car loan interest paid – tax related information", date: dec).contains("Lovely/Taxes/2025"))
    }

    func testTagsCarriedThroughThePlanAndKidChoiceAddsPerson() {
        let m = SessionMessage(id: "m", threadId: "t", fromName: "Pine Ridge", fromAddress: "office@pineridge.example",
                               subject: "Band concert Thursday", date: now, text: "The band concert is Thursday at 6:30.",
                               section: .updates, category: .school, isPerson: false, ask: nil, isHealth: false,
                               isFirstTimeSender: false, asksForAction: false, hasDates: true)
        let plan = SessionPlanner.plan([m], memory: DrawerMemory(), kids: context.kids, households: context.households)
        XCTAssertEqual(plan.items[0].drawer?.choice.drawer, .kids)
        let withChild = SessionPlanner.tags(for: m, choice: DrawerChoice(.kids, child: "Rowan"), context: context)
        XCTAssertTrue(withChild.contains(MailTag(group: .person, name: "Rowan")))
        XCTAssertTrue(withChild.contains(MailTag(group: .topic, name: "Band")))
    }

    func testOldDrawerNamesStillDecode() throws {
        let data = Data(#"{"byAddress":{"a@x.example":{"drawer":"house"},"b@y.example":{"drawer":"people"}},"byDomain":{}}"#.utf8)
        let memory = try JSONDecoder().decode(DrawerMemory.self, from: data)
        XCTAssertEqual(memory.recall("a@x.example"), DrawerChoice(.home))
        XCTAssertEqual(memory.recall("b@y.example"), DrawerChoice(.personal))
    }

    func testEverydayWordsMapToCategories() {
        XCTAssertEqual(SessionCommandValidator.drawer(named: "house", kids: []), DrawerChoice(.home))
        XCTAssertEqual(SessionCommandValidator.drawer(named: "shopping", kids: []), DrawerChoice(.orders))
        XCTAssertNil(SessionCommandValidator.drawer(named: "misc", kids: []))
    }
}
