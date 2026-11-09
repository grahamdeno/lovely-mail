import Foundation

// Sprint 7 inbox session. Drawers are Lovely-owned Gmail labels; putting mail away files it in one,
// marks it read and takes it out of the inbox. Pure, so it is tested. See docs/sprint7-design.md.

/// The fixed set of drawers. Claude and Apple Intelligence choose from these; they never invent one.
enum Drawer: String, CaseIterable, Codable, Sendable {
    case money, house, kids, orders, travel, people, reference

    static let parent = "Lovely"

    var title: String {
        switch self {
        case .money: return "Money"
        case .house: return "House"
        case .kids: return "Kids"
        case .orders: return "Orders"
        case .travel: return "Travel"
        case .people: return "People"
        case .reference: return "Reference"
        }
    }
}

/// A drawer, plus a child's sub-drawer for Kids ("Lovely/Kids/Heidi").
struct DrawerChoice: Hashable, Codable, Sendable {
    var drawer: Drawer
    var child: String?

    init(_ drawer: Drawer, child: String? = nil) {
        self.drawer = drawer
        let name = child?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Only Kids has sub-drawers; a name with a slash would make a deeper label, so it is dropped.
        self.child = drawer == .kids && !name.isEmpty && !name.contains("/") ? name : nil
    }

    /// The Gmail label name.
    var labelName: String {
        let base = Drawer.parent + "/" + drawer.title
        return child.map { base + "/" + $0 } ?? base
    }

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
