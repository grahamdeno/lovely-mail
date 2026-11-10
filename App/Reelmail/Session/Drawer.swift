import Foundation

// Sprint 7 inbox session. Drawers are Lovely-owned Gmail labels; putting mail away files it in one,
// marks it read and takes it out of the inbox. Pure, so it is tested. See docs/sprint7-design.md.

/// A category: the part of the owner's life an email is about (owner, Nov 9, 2026: "insurance belongs inside Home").
/// Every email put away gets exactly one, plus tags (MailTags). The owner can rename, hide, reorder and add
/// categories (CategorySettings); engines choose only from the visible set. The type keeps its old name, Drawer.
///
/// Stored as its id alone, so memories and examples saved under the old fixed set ("money", "kids") still decode.
struct Drawer: Hashable, Codable, Sendable, Identifiable {
    let id: String

    init(id: String) { self.id = Drawer.canonical(id) }

    static let parent = "Lovely"

    // Built-in categories. The rule: the specific thing wins over the kind of mail (car insurance is Auto, not Finance).
    static let home = Drawer(id: "home")
    static let auto = Drawer(id: "auto")
    static let family = Drawer(id: "family")
    static let finance = Drawer(id: "finance")
    static let lifeLegal = Drawer(id: "lifelegal")
    static let health = Drawer(id: "health")
    static let government = Drawer(id: "government")
    static let work = Drawer(id: "work")
    static let travel = Drawer(id: "travel")
    static let shopping = Drawer(id: "shopping")
    static let projects = Drawer(id: "projects")
    static let community = Drawer(id: "community")
    static let pets = Drawer(id: "pets")
    static let accounts = Drawer(id: "accounts")

    // The first fixed set's names, kept so old code paths, tests and saved data read naturally.
    static let money = Drawer.finance
    static let kids = Drawer.family
    static let orders = Drawer.shopping
    static let personal = Drawer.community

    static let builtIns: [Drawer] = [.home, .auto, .family, .finance, .lifeLegal, .health, .government, .work, .travel,
                                     .shopping, .projects, .community, .pets, .accounts]

    /// Old ids from the first fixed set and Sprint 7's first build.
    static func canonical(_ raw: String) -> String {
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch r {
        case "money": return "finance"
        case "kids": return "family"
        case "orders": return "shopping"
        case "personal", "people", "reference": return "community"
        case "house": return "home"
        case "life", "legal", "life & legal", "life and legal": return "lifelegal"
        default: return r
        }
    }

    var rawValue: String { id }
    var isBuiltIn: Bool { Drawer.builtIns.contains(self) }

    /// The visible categories, in the owner's order. Engines pick from these only.
    static var allCases: [Drawer] { CategorySettings.current.visible }

    var title: String { CategorySettings.current.title(for: self) }
    var meaning: String { CategorySettings.current.meaning(for: self) }
    var isHidden: Bool { CategorySettings.current.isHidden(self) }

    var defaultTitle: String {
        switch id {
        case "home": return "Home"
        case "auto": return "Auto"
        case "family": return "Family"
        case "finance": return "Finance"
        case "lifelegal": return "Life and legal"
        case "health": return "Health"
        case "government": return "Government"
        case "work": return "Work"
        case "travel": return "Travel"
        case "shopping": return "Shopping"
        case "projects": return "Projects"
        case "community": return "Community"
        case "pets": return "Pets"
        case "accounts": return "Accounts"
        default: return id.capitalized
        }
    }

    /// One line on what goes in, for the playbook and Settings.
    var defaultMeaning: String {
        switch id {
        case "home": return "the house: mortgage or rent, home insurance, utilities, internet, cell phone, Starlink, repairs, HOA, property tax"
        case "auto": return "cars: car insurance, auto loans, registration, DMV, service, recalls, tolls"
        case "family": return "spouse and children: school, childcare, activities, sports, band, family plans"
        case "finance": return "banks, credit cards, personal loans, investments, retirement accounts, taxes, crypto"
        case "lifelegal": return "life insurance, beneficiaries, wills, trusts, estate and legal papers"
        case "health": return "doctors, appointments, patient portals, health insurance, medical bills"
        case "government": return "VA, military retired pay, IRS notices, Social Security, passports, government benefits"
        case "work": return "the job: onboarding, payroll, benefits, background checks, job search"
        case "travel": return "flights, hotels, car rental, rides, trip plans, rewards programs"
        case "shopping": return "orders, shipping, returns, warranties"
        case "projects": return "side projects and businesses: developer accounts, app reviews, hosting, domains, company filings"
        case "community": return "friends, clubs, church, hobbies like hockey, neighbors"
        case "pets": return "vets, pet insurance, pet supplies"
        case "accounts": return "login codes, new device checks, password resets, account notices"
        default: return ""
        }
    }

    var icon: String {
        switch id {
        case "home": return "house"
        case "auto": return "car"
        case "family": return "figure.2.and.child.holdinghands"
        case "finance": return "building.columns"
        case "lifelegal": return "shield"
        case "health": return "cross.case"
        case "government": return "flag"
        case "work": return "briefcase"
        case "travel": return "airplane"
        case "shopping": return "bag"
        case "projects": return "hammer"
        case "community": return "person.3"
        case "pets": return "pawprint"
        case "accounts": return "key"
        default: return "folder"
        }
    }

    init(from decoder: Decoder) throws {
        self.init(id: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(id)
    }
}

/// A category, plus the person it is about for Family (shown as "Family · Heidi"; filed as Lovely/Family plus the
/// Person tag).
struct DrawerChoice: Hashable, Codable, Sendable {
    var drawer: Drawer
    var child: String?

    init(_ drawer: Drawer, child: String? = nil) {
        self.drawer = drawer
        let name = child?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Only Family has sub-drawers; a name with a slash would make a deeper label, so it is dropped.
        self.child = drawer == .family && !name.isEmpty && !name.contains("/") ? name : nil
    }

    /// The Gmail label name. A child is a Person tag (MailTags), not a sub-label. A renamed category files under
    /// its new name from then on.
    var labelName: String { Drawer.parent + "/" + drawer.title.replacingOccurrences(of: "/", with: "-") }

    /// "Family · Heidi", "Finance".
    var title: String { child.map { drawer.title + " \u{00B7} " + $0 } ?? drawer.title }

    /// "Family/Heidi" or "Finance": how engines name it.
    var engineName: String { child.map { drawer.title + "/" + $0 } ?? drawer.title }
}

/// How sure a drawer suggestion is. Only `remembered`, `rule` and a confident `model` guess may go in a batch.
enum DrawerConfidence: Int, Codable, Sendable, Comparable {
    case model = 1       // Apple Intelligence (step 3)
    case rule = 2        // keyword and sender rules
    case remembered = 3  // the owner filed this sender before

    static func < (a: DrawerConfidence, b: DrawerConfidence) -> Bool { a.rawValue < b.rawValue }
}

struct DrawerGuess: Hashable, Sendable {
    var choice: DrawerChoice
    var confidence: DrawerConfidence
    /// Plain-language why, shown in the session ("You filed Schwab in Money before").
    var reason: String
}

/// Where the owner filed each sender. Address first, then the company domain.
/// Domain memory never applies to public mailbox providers or shared sending services,
/// where one domain covers many unrelated senders.
struct DrawerMemory: Codable, Equatable, Sendable {
    private(set) var byAddress: [String: DrawerChoice] = [:]
    private(set) var byDomain: [String: DrawerChoice] = [:]

    static func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The company domain to remember, or nil when the domain is shared by unrelated senders.
    static func companyDomain(of address: String) -> String? {
        let full = InsightText.domain(of: normalized(address))
        guard !full.isEmpty else { return nil }
        let company = InsightText.registrable(full)
        let shared = OrganizationKey.sharedDomains.union(LocalTriageRules.publicDomains)
        if shared.contains(company) || shared.contains(full) { return nil }
        return company
    }

    mutating func remember(_ choice: DrawerChoice, for address: String) {
        let a = Self.normalized(address)
        guard !a.isEmpty else { return }
        byAddress[a] = choice
        if let d = Self.companyDomain(of: a) { byDomain[d] = choice }
    }

    mutating func forget(_ address: String) {
        byAddress[Self.normalized(address)] = nil
    }

    func recall(_ address: String) -> DrawerChoice? {
        let a = Self.normalized(address)
        if let c = byAddress[a] { return c }
        return Self.companyDomain(of: a).flatMap { byDomain[$0] }
    }

    // MARK: Storage, per account on the phone

    static func key(account: String) -> String { "lovely.session.drawerMemory." + normalized(account) }

    static func load(account: String, defaults: UserDefaults = .standard) -> DrawerMemory {
        guard let data = defaults.data(forKey: key(account: account)),
              let m = try? JSONDecoder().decode(DrawerMemory.self, from: forgettingMoney(data)) else { return DrawerMemory() }
        return m
    }

    /// The old Money category was split by what mail covers (home insurance to Home, car loans to Auto, banks to
    /// Finance), so a sender remembered as Money is forgotten and the rules decide again. Kids, Orders and Personal
    /// map one to one and are kept.
    static func forgettingMoney(_ data: Data) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        for key in ["byAddress", "byDomain"] {
            guard let map = object[key] as? [String: Any] else { continue }
            object[key] = map.filter { (($0.value as? [String: Any])?["drawer"] as? String)?.lowercased() != "money" }
        }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? data
    }

    func save(account: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(account: account)) }
    }
}

extension DrawerChoice {
    /// Every category the owner can pick, in order; Family is followed by one sub-drawer per child.
    static func all(kids: [KidProfile]) -> [DrawerChoice] {
        Drawer.allCases.flatMap { d -> [DrawerChoice] in
            d == .family ? [DrawerChoice(.family)] + kids.map { DrawerChoice(.family, child: $0.name) }.filter { $0.child != nil } : [DrawerChoice(d)]
        }
    }
}
