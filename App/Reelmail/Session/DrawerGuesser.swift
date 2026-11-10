import Foundation

/// Rule-based drawer suggestions. Drawer memory always wins over these; Apple Intelligence (step 3)
/// fills in only when these say nothing. Pure.
enum DrawerGuesser {
    static let orderWords = ["your order", "order confirmation", "order #", "order number", "has shipped", "out for delivery",
                             "was delivered", "has been delivered", "tracking number", "track your package", "return label",
                             "refund has been"]
    static let travelWords = ["itinerary", "boarding pass", "reservation confirmed", "your reservation", "booking confirmation",
                              "your booking", "your flight", "flight confirmation", "check-in", "check in for your", "hotel", "rental car",
                              "confirmation number"]
    static let moneyWords = ["statement is ready", "estatement", "e-statement", "statement is available", "your statement",
                             "your bill", "bill is ready", "invoice", "payment received", "payment confirmation", "autopay",
                             "auto pay", "receipt", "tax document", "tax form", "1099", "w-2", "deposit", "balance", "brokerage",
                             "credit card", "bank"]
    static let houseWords = ["utility", "utilities", "electric", "water bill", "sewer", "trash pickup", "gas bill", "energy",
                             "internet service", "lease", "rent", "landlord", "hoa", "homeowners", "maintenance request",
                             "work order", "pest control", "hvac", "plumbing", "mortgage", "home insurance", "renters insurance"]
    static let schoolWords = ["school", "pta", "pto", "teacher", "classroom", "principal", "student", "parents and guardians",
                              "families", "report card", "field trip", "band", "orchestra", "lacrosse", "soccer", "cross country",
                              "practice", "tournament", "game day", "team parents", "booster"]
    /// Sending platforms that mean school or youth activities.
    static let schoolDomains = ["infinitecampus", "parentsquare", "schoolmessenger", "remind.com", "classdojo", "procaresoftware",
                                "gomotionapp", "teamsnap", "sportsengine", "k12", ".edu"]

    static let accountWords = ["verification code", "one-time code", "one-time passcode", "security code", "sign-in code", "your code",
                               "new device", "verify your new device", "new login", "password reset", "reset your password",
                               "account has been unlocked", "trusted device", "two-factor", "2-step"]
    static let projectWords = ["testflight", "app store connect", "beta testing", "apple developer", "developer program",
                               "github", "pull request", "api key", "api credits", "domain", "dns", "hosting", "registered agent",
                               "annual report"]
    static let projectDomains = ["github.com", "vercel.com", "squarespace", "anthropic.com", "perplexity.ai", "openai.com",
                                 "x.ai", "cloudflare.com", "netlify", "northcarolinaregisteredagent"]
    static let workWords = ["onboarding", "new hire", "background check", "background verification", "payroll", "pay stub",
                            "job alert", "recruiter", "interview", "offer letter", "orientation"]
    static let workDomains = ["hireright.com", "myisolved.com", "linkedin.com", "indeed.com", "workday", "adp.com", "gusto.com"]
    static let travelDomains = ["aa.com", "delta.com", "united.com", "southwest.com", "alaskaair.com", "hilton.com", "marriott.com",
                                "hyatt.com", "ihg.com", "airbnb.com", "uber.com", "lyft.com", "expedia.com", "booking.com"]
    static let mortgageWords = ["mortgage", "escrow", "home loan", "loan servicing", "homeowners insurance", "home warranty",
                                "garage door", "exterminat", "pest control", "backflow", "hoa", "property tax"]

    // Nov 9 categories: insurance and loans go with what they cover.
    static let lifeWords = ["life insurance", "term life", "whole life", "beneficiary", "annuity", "life policy"]
    static let legalWords = ["estate plan", "last will", "living trust", "revocable trust", "power of attorney", "probate",
                             "attorney at law", "notarized"]
    static let autoWords = ["auto insurance", "car insurance", "auto policy", "vehicle", "auto loan", "car loan", "registration renewal",
                            "dmv", "oil change", "recall notice", "service appointment", "lexus financial", "toyota financial",
                            "nc quick pass", "e-zpass", "toll bill", "tire rotation", "dealership"]
    static let homeCoverWords = ["home policy", "homeowners", "homeowner", "dwelling", "renters insurance", "property insurance",
                                 "flood insurance", "home insurance"]
    static let phoneWords = ["starlink", "verizon", "t-mobile", "at&t", "wireless bill", "cell phone", "phone bill", "spectrum",
                             "xfinity", "internet bill"]
    static let governmentWords = ["veterans affairs", "va benefits", "disability compensation", "retired pay", "mypay", "dfas",
                                  "social security", "internal revenue service", "passport", "gi bill"]
    static let governmentDomains = [".gov", ".mil", "va.gov", "irs.gov", "ssa.gov", "dfas.mil"]
    static let petWords = ["veterinary", "vet appointment", "animal hospital", "pet insurance", "trupanion", "chewy", "rabies vaccine"]

    struct Input {
        var fromAddress: String
        var fromName: String
        var subject: String
        /// The author's own words (quotes and footers removed).
        var text: String
        var category: PostCategory
        var isPerson: Bool
        var isHealth: Bool = false
    }

    /// The best rule guess, or nil when the rules are not sure. A guess for a hidden category is dropped.
    static func guess(_ m: Input, kids: [KidProfile], settings: CategorySettings = .current) -> DrawerGuess? {
        guard let g = rawGuess(m, kids: kids), !settings.isHidden(g.choice.drawer) else { return nil }
        return g
    }

    /// The rule: the specific thing wins over the kind of mail. Car insurance is Auto, a school fee is Family,
    /// a Farm Bureau home policy is Home. Health always wins (it never goes to cloud engines).
    static func rawGuess(_ m: Input, kids: [KidProfile]) -> DrawerGuess? {
        let haystack = (m.subject + "\n" + String(m.text.prefix(2000))).lowercased()
        let domain = InsightText.domain(of: m.fromAddress.lowercased())
        let kid = matchKid(haystack: haystack, kids: kids)
        let schoolish = schoolDomains.contains(where: domain.contains) || m.category == .school || hasAny(haystack, schoolWords)
        func g(_ d: Drawer, child: String? = nil, _ why: String) -> DrawerGuess {
            DrawerGuess(choice: DrawerChoice(d, child: child), confidence: .rule, reason: why)
        }

        if m.isHealth { return g(.health, "Health") }
        if m.isPerson {
            if let kid { return g(.family, child: kid.name, "About \(kid.name)") }
            if schoolish { return g(.family, "School or activities") }
            return g(.community, "Mail from a person")
        }
        if hasAny(haystack, accountWords) { return g(.accounts, "Login or account notice") }
        if let kid { return g(.family, child: kid.name, "Mentions \(kid.name)'s school or activities") }
        if schoolish { return g(.family, child: kids.count == 1 ? kids[0].name : nil, "School or activities") }
        if projectDomains.contains(where: domain.contains) || hasAny(haystack, projectWords) {
            return g(.projects, "Projects: developer, hosting or company mail")
        }
        if workDomains.contains(where: domain.contains) || hasAny(haystack, workWords) { return g(.work, "Work or career") }
        if governmentDomains.contains(where: { domain.hasSuffix($0) }) || hasAny(haystack, governmentWords) {
            return g(.government, "Government: VA, pay, IRS or passports")
        }
        if travelDomains.contains(where: { domain.hasSuffix($0) }) || m.category == .travel || hasAny(haystack, travelWords) {
            return g(.travel, "Travel")
        }
        // Insurance goes with what it covers.
        if hasAny(haystack, lifeWords) || hasAny(haystack, legalWords) { return g(.lifeLegal, "Life insurance or legal papers") }
        if hasAny(haystack, petWords) { return g(.pets, "Pets") }
        if hasAny(haystack, autoWords) { return g(.auto, "Auto: car insurance, loan or service") }
        if hasAny(haystack, homeCoverWords) || hasAny(haystack, mortgageWords) || hasAny(haystack, houseWords) || hasAny(haystack, phoneWords) {
            return g(.home, "Home: insurance, utilities, phone or services")
        }
        // Orders before finance: an order receipt is an order, not a statement. An appliance delivery is an order.
        if DeliveryNotice.hasPhrase(haystack) || hasAny(haystack, orderWords) { return g(.shopping, "Order or shipping") }
        if m.category == .money || hasAny(haystack, moneyWords) { return g(.finance, "Finance: bank, card, loan or statement") }
        return nil
    }

    /// A kid whose school, teacher or activity appears in the mail. Names alone are too common to trust.
    static func matchKid(haystack: String, kids: [KidProfile]) -> KidProfile? {
        let hits = kids.filter { kid in
            let terms = ([kid.school] + kid.teacherNames + kid.activities)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { $0.count >= 4 }
            return terms.contains { containsWord(haystack, $0) }
        }
        // Two kids at the same school: the parent Kids drawer is the honest answer, so no single match.
        return hits.count == 1 ? hits[0] : nil
    }

    /// Whole-word matching, so "rent" does not match "parent" or "current", and "band" not "husband".
    static func hasAny(_ text: String, _ words: [String]) -> Bool { words.contains { containsWord(text, $0) } }

    static func containsWord(_ text: String, _ word: String) -> Bool {
        guard let first = word.first, let last = word.last else { return false }
        let lead = first.isLetter || first.isNumber ? #"\b"# : ""
        let trail = last.isLetter || last.isNumber ? #"\b"# : ""
        let pattern = lead + NSRegularExpression.escapedPattern(for: word) + trail
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
