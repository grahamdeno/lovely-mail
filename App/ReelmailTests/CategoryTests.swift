import XCTest
@testable import Reelmail

/// Nov 9 categories: owner-editable, and insurance goes with what it covers.
final class CategoryTests: XCTestCase {
    private func guess(_ subject: String, _ text: String = "", from: String = "billing@company.example",
                       settings: CategorySettings = .default) -> Drawer? {
        DrawerGuesser.guess(.init(fromAddress: from, fromName: "X", subject: subject, text: text, category: .updates, isPerson: false),
                            kids: [], settings: settings)?.choice.drawer
    }

    func testInsuranceGoesWithWhatItCovers() {
        XCTAssertEqual(guess("You have a new bill for Home Policy 6791876"), .home)
        XCTAssertEqual(guess("You have a new bill for Auto Policy 5512"), .auto)
        XCTAssertEqual(guess("Your life insurance beneficiary update"), .lifeLegal)
        XCTAssertEqual(guess("Your Starlink bill is ready"), .home, "Phone and internet are Home")
        XCTAssertEqual(guess("Your retiree account statement", "Retired pay for November", from: "noreply@dfas.mil"), .government)
        XCTAssertEqual(guess("Your credit card statement is ready"), .finance)
    }

    func testHiddenCategoriesAreNeverGuessed() {
        var s = CategorySettings.default
        s.setHidden(.auto, true)
        XCTAssertNil(guess("You have a new bill for Auto Policy 5512", settings: s))
        XCTAssertFalse(s.visible.contains(.auto))
    }

    func testOldNamesMapToNewCategories() throws {
        XCTAssertEqual(Drawer(id: "money"), .finance)
        XCTAssertEqual(Drawer(id: "kids"), .family)
        XCTAssertEqual(Drawer(id: "orders"), .shopping)
        XCTAssertEqual(Drawer(id: "personal"), .community)
        let data = try JSONEncoder().encode(DrawerChoice(.family, child: "Avery"))
        XCTAssertEqual(try JSONDecoder().decode(DrawerChoice.self, from: data), DrawerChoice(.family, child: "Avery"))
        XCTAssertEqual(String(data: try JSONEncoder().encode(Drawer.lifeLegal), encoding: .utf8), "\"lifelegal\"", "Stored as its id")
    }

    func testRememberedMoneySendersAreForgottenSoRulesDecideAgain() throws {
        let data = Data(#"{"byAddress":{"a@bank.example":{"drawer":"money"},"b@school.example":{"drawer":"kids"}},"byDomain":{"bank.example":{"drawer":"money"}}}"#.utf8)
        let memory = try JSONDecoder().decode(DrawerMemory.self, from: DrawerMemory.forgettingMoney(data))
        XCTAssertNil(memory.recall("a@bank.example"), "Money was split, so the old memory no longer says where it goes")
        XCTAssertEqual(memory.recall("b@school.example"), DrawerChoice(.family), "Kids maps one to one and is kept")
    }

    func testStartingSetFollowsTheAnswers() {
        var a = CategorySettings.Answers()
        a.hasCar = false; a.military = true; a.business = true; a.pets = false
        let s = CategorySettings.starting(a)
        XCTAssertFalse(s.visible.contains(.auto))
        XCTAssertTrue(s.visible.contains(.government))
        XCTAssertTrue(s.visible.contains(.projects))
        XCTAssertFalse(s.visible.contains(.pets))
        XCTAssertTrue(s.setupDone)
    }

    func testRenameAddMoveAndSubcategories() {
        var s = CategorySettings.default
        s.rename(.finance, to: "Money/Banks")
        XCTAssertEqual(s.title(for: .finance), "Money-Banks", "A slash would nest the Gmail label")
        s.rename(.finance, to: "")
        XCTAssertEqual(s.title(for: .finance), "Finance", "Empty restores the built-in name")

        let boat = s.add(named: "Boat", meaning: "marina, boat insurance")
        XCTAssertNotNil(boat)
        XCTAssertNil(s.add(named: "boat"), "Names are unique")
        XCTAssertEqual(s.visible.last, boat)
        XCTAssertEqual(s.meaning(for: boat!), "marina, boat insurance")
        s.remove(.home)
        XCTAssertTrue(s.all.contains(.home), "Built-ins can be hidden, not removed")
        s.remove(boat!)
        XCTAssertFalse(s.all.contains(boat!))

        let first = s.entries[0].id
        s.move(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(s.entries[2].id, first)

        s.addSubcategory("Sailboat", to: .community)
        s.addSubcategory("sailboat", to: .community)
        XCTAssertEqual(s.extraSubcategories(for: .community), ["Sailboat"])
        let tags = MailTagger.tags(for: .init(category: .community, fromAddress: "a@club.example", subject: "Sailboat race Saturday", text: "", date: Date()),
                                   context: TagContext(households: [], kids: [], extraSubcategories: s.extraSubcategoryMap))
        XCTAssertTrue(tags.map(\.labelName).contains("Lovely/Topic/Sailboat"), "\(tags.map(\.labelName))")
    }

    func testSettingsRoundTripAndKeepNewBuiltIns() {
        let defaults = UserDefaults(suiteName: "lovely.categories.test")!
        defaults.removePersistentDomain(forName: "lovely.categories.test")
        var s = CategorySettings.default
        s.entries.removeAll { $0.id == "pets" }
        s.save(defaults: defaults)
        let loaded = CategorySettings.load(defaults: defaults)
        XCTAssertTrue(loaded.all.contains(.pets), "A built-in missing from saved settings comes back")
        XCTAssertTrue(loaded.isHidden(.pets))
    }

    func testResortSplitsMoneyAndSkipsUnchanged() {
        let s = CategorySettings.default
        XCTAssertEqual(CategoryResort.target(fromAddress: "billing@ncfb.example", fromName: "NC Farm Bureau", subject: "New bill for Home Policy 6791876",
                                             text: "", isHealth: false, kids: [], settings: s), DrawerChoice(.home))
        XCTAssertEqual(CategoryResort.target(fromAddress: "a@b.example", fromName: "A", subject: "Hello", text: "", isHealth: false,
                                             kids: [], settings: s), DrawerChoice(.finance), "Unsure Money mail goes to Finance")
        let groups = CategoryResort.groups([
            .init(id: "1", from: "Lovely/Money", to: DrawerChoice(.home), subject: "Home policy"),
            .init(id: "2", from: "Lovely/Money", to: DrawerChoice(.home), subject: "Escrow"),
            .init(id: "3", from: "Lovely/Money", to: DrawerChoice(.finance), subject: "Statement"),
            .init(id: "4", from: "Lovely/Finance", to: DrawerChoice(.finance), subject: "Same label"),
        ])
        XCTAssertEqual(groups.map(\.title), ["Money \u{203A} Home", "Money \u{203A} Finance"])
        XCTAssertEqual(groups[0].messageIDs, ["1", "2"])
        XCTAssertEqual(CategoryResort.query(for: "Lovely/Money"), "label:lovely-money")
        XCTAssertEqual(CategoryResort.preview(groups[0]).kind, .label)
    }
}
