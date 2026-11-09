import Foundation

// Sprint 7 inbox session. Drawers are Lovely-owned Gmail labels; putting mail away files it in one,
// marks it read and takes it out of the inbox. Pure, so it is tested. See docs/sprint7-design.md.

/// The fixed primary categories (owner, Nov 9, 2026). Every email put away gets exactly one, plus tags (MailTags).
/// Engines choose from these; they never invent one. The type keeps its old name, Drawer, across the code.
enum Drawer: String, CaseIterable, Codable, Sendable {
    case money, home, kids, health, work, projects, orders, travel, personal, accounts

    static let parent = "Lovely"

    var title: String {
        switch self {
        case .money: return "Money"
        case .home: return "Home"
        case .kids: return "Kids"
        case .health: return "Health"
        case .work: return "Work"
        case .projects: return "Projects"
        case .orders: return "Orders"
        case .travel: return "Travel"
        case .personal: return "Personal"
        case .accounts: return "Accounts"
        }
    }

    /// One line on what goes in, for the playbook and Settings.
    var meaning: String {
        switch self {
        case .money: return "banks, investments, retirement, credit cards, insurance, pay, taxes, loans"
        case .home: return "mortgage, rent, utilities, home services, repairs, appliances, home insurance, leases, real estate"
        case .kids: return "school, childcare, activities, sports, band and anything about the children"
        case .health: return "appointments, patient portals, health insurance statements, medical invoices"
        case .work: return "the job, onboarding, payroll, benefits, background checks, job search"
        case .projects: return "side projects and businesses: developer accounts, app reviews, hosting, domains, company filings"
        case .orders: return "shopping, shipping, returns, warranties"
        case .travel: return "flights, hotels, rides, rewards"
        case .personal: return "people, friends, family, hobbies, community"
        case .accounts: return "login codes, new device checks, password resets, account notices"
        }
    }

    /// Old drawer names from Sprint 7's first build still decode.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "house": self = .home
        case "people", "reference": self = .personal
        default:
            guard let d = Drawer(rawValue: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown drawer \(raw)"))
            }
            self = d
        }
    }
}

/// A category, plus the child it is about for Kids (shown as "Kids · Heidi"; filed as Lovely/Kids plus the Person tag).
struct DrawerChoice: Hashable, Codable, Sendable {
    var drawer: Drawer
    var child: String?

    init(_ drawer: Drawer, child: String? = nil) {
        self.drawer = drawer
        let name = child?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Only Kids has sub-drawers; a name with a slash would make a deeper label, so it is dropped.
        self.child = drawer == .kids && !name.isEmpty && !name.contains("/") ? name : nil
    }

    /// The Gmail label name. A child is a Person tag (MailTags), not a sub-label.
    var labelName: String { Drawer.parent + "/" + drawer.title }

    /// "Kids · Heidi", "Money".
    var title: String { child.map { drawer.title + " · " + $0 } ?? drawer.title }
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
              let m = try? JSONDecoder().decode(DrawerMemory.self, from: data) else { return DrawerMemory() }
        return m
    }

    func save(account: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(account: account)) }
    }
}

extension DrawerChoice {
    /// Every drawer the owner can pick, in order; Kids is followed by one sub-drawer per child.
    static func all(kids: [KidProfile]) -> [DrawerChoice] {
        Drawer.allCases.flatMap { d -> [DrawerChoice] in
            d == .kids ? [DrawerChoice(.kids)] + kids.map { DrawerChoice(.kids, child: $0.name) }.filter { $0.child != nil } : [DrawerChoice(d)]
        }
    }
}
