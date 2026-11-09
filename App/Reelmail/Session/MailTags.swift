import Foundation

// Tags beside the one primary category (owner, Nov 9, 2026): what an email is, what it is about, which property,
// which person, which tax year. Gmail labels under Lovely/, from fixed lists, so a search like
// `label:lovely-tag-bill label:lovely-property-5206-lone-eagle` finds every bill for that house. Pure, so it is tested.

struct MailTag: Hashable, Codable, Sendable, Comparable {
    enum Group: String, Codable, Sendable, CaseIterable {
        case type = "Tag", topic = "Topic", property = "Property", person = "Person", taxes = "Taxes"
    }
    var group: Group
    var name: String

    /// "Lovely/Tag/Bill", "Lovely/Property/5206 Lone Eagle", "Lovely/Person/Silas", "Lovely/Taxes/2026".
    var labelName: String { Drawer.parent + "/" + group.rawValue + "/" + name }

    /// What a chip shows.
    var title: String { group == .taxes ? "Taxes " + name : name }

    static func < (a: MailTag, b: MailTag) -> Bool {
        let order = Group.allCases
        let ia = order.firstIndex(of: a.group)!, ib = order.firstIndex(of: b.group)!
        return ia == ib ? a.name < b.name : ia < ib
    }
}

/// The people and places the owner set up in Settings, Households and kids.
struct TagContext: Sendable {
    var households: [Household]
    var kids: [KidProfile]
    var now: Date = Date()

    static let empty = TagContext(households: [], kids: [])
}

enum MailTagger {
    // MARK: Fixed lists

    /// Type tags: what the email is. First match wins for each tag; several may apply.
    static let types: [(String, [String])] = [
        ("Bill", ["your bill", "bill is ready", "amount due", "payment due", "statement balance", "minimum payment", "past due", "is due"]),
        ("Statement", ["statement is ready", "statement is available", "estatement", "e-statement", "monthly statement", "account statement", "shareholder report"]),
        ("Receipt", ["receipt", "order confirmed", "order confirmation", "thank you for your order", "thanks for your order", "sales receipt"]),
        ("Payment", ["payment received", "we received your payment", "payment confirmation", "thank you for your payment", "payment is processing", "payment has been scheduled", "payment submitted", "autopay"]),
        ("Invoice", ["invoice"]),
        ("Appointment", ["appointment", "you're confirmed", "is confirmed for", "reminder: your visit", "scheduled for"]),
        ("Confirmation", ["confirmation number", "reservation confirmed", "booking confirmed", "trip confirmation", "itinerary"]),
        ("Contract", ["docusign", "please sign", "esign", "e-sign", "signature", "agreement executed", "lease agreement"]),
        ("Notice", ["important information", "policy update", "updates to our", "disclosure", "notice"]),
    ]

    /// Topic tags, per category, from the owner's mail (Nov 9, 2026 sample) and common to most households.
    static let topics: [Drawer: [(String, [String])]] = [
        .home: [
            ("Mortgage", ["mortgage", "escrow", "loan servicing", "crosscountry"]),
            ("Rent", ["rent payment", "your rent", "rent is due", "bilt"]),
            ("Lease", ["lease", "move-in", "renewal offer"]),
            ("Electric", ["electric", "duke energy", "kwh", "power outage"]),
            ("Water", ["water bill", "public utility", "cfpua", "sewer"]),
            ("Utilities", ["utility", "utilities", "conservice"]),
            ("Internet", ["internet", "starlink", "broadband", "wi-fi service", "fiber"]),
            ("Trash", ["trash", "garbage", "recycling", "turtletrash"]),
            ("Pest control", ["pest", "exterminat", "termite"]),
            ("Repairs", ["repair", "inspection", "estimate", "service call", "garage door", "plumb", "hvac", "backflow"]),
            ("Appliance", ["washer", "dryer", "dishwasher", "refrigerator", "appliance"]),
            ("Home warranty", ["home warranty", "home buyers warranty"]),
            ("Insurance", ["homeowners", "renters insurance", "ho4", "dwelling", "policy documents", "insurance binder"]),
            ("Real estate", ["closing", "title company", "escrow officer", "offer for", "sale of", "realty"]),
            ("Energy", ["energy snapshot", "energy report", "sense"]),
        ],
        .money: [
            ("Bank", ["bank", "checking", "savings account", "deposit"]),
            ("Credit card", ["credit card", "card payment", "card account", "apple card", "card ending"]),
            ("Investments", ["brokerage", "trade confirmation", "shareholder", "prospectus", "fidelity", "schwab", "allocation"]),
            ("Retirement", ["401(k)", "401k", "retirement", "pension", "ira", "tsp"]),
            ("Kids' accounts", ["trump account", "529", "custodial"]),
            ("Insurance", ["life insurance", "premium", "annuity", "policy"]),
            ("Pay", ["mypay", "dfas", "payroll", "direct deposit", "retired pay"]),
            ("Car loan", ["auto loan", "car loan", "lexus financial", "vehicle loan"]),
            ("Crypto", ["crypto", "bitcoin", "coinbase", "ethereum"]),
        ],
        .kids: [
            ("School", ["school", "teacher", "classroom", "report card", "student", "principal", "newsletter"]),
            ("Childcare", ["preschool", "daycare", "childcare", "procare"]),
            ("Sports", ["soccer", "lacrosse", "football", "cross country", "hockey", "practice", "game day", "tournament"]),
            ("Band", ["band", "orchestra", "concert", "music"]),
            ("Trips", ["field trip", "overnight trip", "permission slip"]),
            ("Military", ["usmc", "battalion", "unit newsletter", "academy", "challenge academy"]),
        ],
        .health: [
            ("Appointment", ["appointment", "visit", "session is confirmed", "reminder"]),
            ("Portal message", ["patient portal", "secure message", "new message from"]),
            ("Insurance", ["eob", "explanation of benefits", "tricare", "coverage", "claim"]),
            ("Invoice", ["invoice", "balance", "what you owe", "statement"]),
        ],
        .work: [
            ("Onboarding", ["onboarding", "new hire", "orientation", "welcome to"]),
            ("Payroll", ["payroll", "pay stub", "paystub", "isolved", "w-2"]),
            ("Benefits", ["benefits", "401(k)", "enrollment"]),
            ("Background check", ["background check", "background verification", "hireright"]),
            ("Job search", ["linkedin", "job alert", "application", "recruiter", "interview"]),
        ],
        .projects: [
            ("App review", ["app store connect", "testflight", "beta testing", "app review", "submission"]),
            ("Developer account", ["developer program", "apple developer", "google play console", "github"]),
            ("Subscription", ["subscription", "your receipt from", "renews", "pro plan", "api credits"]),
            ("Domain", ["domain", "dns", "squarespace domains"]),
            ("Company filing", ["annual report", "registered agent", "llc", "articles of"]),
        ],
        .orders: [
            ("Shipping", ["shipped", "on the way", "out for delivery", "delivered", "tracking", "arriving"]),
            ("Return", ["return", "refund"]),
            ("Warranty", ["warranty", "protection plan"]),
        ],
        .travel: [
            ("Flight", ["flight", "boarding pass", "check in", "gate"]),
            ("Hotel", ["hotel", "your stay", "folio", "inn", "suites"]),
            ("Rideshare", ["uber", "lyft", "your trip with"]),
            ("Rewards", ["rewards", "aadvantage", "points", "miles"]),
        ],
        .personal: [
            ("Hockey", ["hockey", "polar ice", "skate"]),
            ("Church", ["church", "umc", "parish", "worship"]),
            ("Family", ["fwd:", "family"]),
        ],
        .accounts: [
            ("Login code", ["verification code", "one-time", "security code", "passcode", "sign-in code", "your code"]),
            ("New device", ["new device", "new login", "signed in", "sign in to"]),
            ("Password", ["password", "reset"]),
        ],
    ]

    /// Words that mean a tax document. These get a Taxes <year> tag in any category.
    static let taxWords = ["1099", "1098", "w-2", "w2 ", "tax document", "tax form", "tax statement", "year end tax", "year-end tax",
                           "tax information", "tax related information", "interest paid", "property tax", "charitable contribution",
                           "form 5498", "1099-r", "k-1", "closing disclosure"]

    // MARK: Tagging

    struct Input {
        var category: Drawer
        var fromAddress: String
        var subject: String
        var text: String
        var date: Date
    }

    /// Every tag that fits, from the fixed lists and the owner's Settings. Order: type, topic, property, person, taxes.
    static func tags(for m: Input, context: TagContext) -> [MailTag] {
        let hay = (m.subject + "\n" + String(m.text.prefix(3_000))).lowercased()
        var out = Set<MailTag>()
        for (name, words) in types where DrawerGuesser.hasAny(hay, words) { out.insert(MailTag(group: .type, name: name)) }
        for (name, words) in topics[m.category] ?? [] where DrawerGuesser.hasAny(hay, words) { out.insert(MailTag(group: .topic, name: name)) }
        // A receipt that is also an order confirmation is a receipt; "Bill" and "Payment" can both be true (paid bill).
        if let p = property(for: m, hay: hay, context: context) { out.insert(MailTag(group: .property, name: p)) }
        for name in people(in: m, hay: hay, context: context) { out.insert(MailTag(group: .person, name: name)) }
        if let year = taxYear(hay: hay, date: m.date) { out.insert(MailTag(group: .taxes, name: String(year))) }
        return out.sorted()
    }

    /// A property tag only on Home mail (or Money mail from a sender linked to a property), never because the
    /// address shows up as a shipping address. Ended (past) properties are never suggested for new mail.
    static func property(for m: Input, hay: String, context: TagContext) -> String? {
        let active = context.households.filter { !$0.isEnded(on: context.now) && !$0.name.isEmpty && !$0.name.contains("/") }
        let domain = InsightText.domain(of: m.fromAddress.lowercased())
        if let linked = active.first(where: { h in h.payeeDomains.contains { !$0.isEmpty && domain.hasSuffix($0.lowercased()) } }) {
            return (m.category == .home || m.category == .money) ? linked.name : nil
        }
        guard m.category == .home else { return nil }
        let named = active.filter { matches(hay, household: $0.name) }
        return named.count == 1 ? named[0].name : nil
    }

    /// "5206 Lone Eagle" matches "5206 Lone Eagle Ct"; a name without a street number matches as a phrase.
    static func matches(_ hay: String, household name: String) -> Bool {
        let n = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard n.count >= 4 else { return false }
        return DrawerGuesser.containsWord(hay, n)
    }

    /// The owner's children named in mail about kids, health, money or travel. Names in shopping or account mail are
    /// usually gift names or greetings, so they are left out there.
    static func people(in m: Input, hay: String, context: TagContext) -> [String] {
        guard [.kids, .health, .money, .travel, .personal].contains(m.category) else { return [] }
        return context.kids.map(\.name).filter { name in
            let n = name.trimmingCharacters(in: .whitespaces)
            return n.count >= 3 && !n.contains("/") && DrawerGuesser.containsWord(hay, n.lowercased())
        }
    }

    /// The tax year a tax document is for: a year written next to tax words, else the year before for mail that
    /// arrives January to April, else the year it arrived. Nil when it is not a tax document.
    static func taxYear(hay: String, date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int? {
        guard taxWords.contains(where: { hay.contains($0) }) else { return nil }
        let received = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        // "2025 Form 1099", "tax year 2025", "for 2025": the most recent year not after the year received.
        let years = hay.matches(of: #/\b(20\d\d)\b/#).compactMap { Int($0.output.1) }.filter { $0 <= received && $0 >= received - 3 }
        if let y = years.max() { return y }
        return month <= 4 ? received - 1 : received
    }
}
