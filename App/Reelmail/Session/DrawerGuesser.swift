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

    struct Input {
        var fromAddress: String
        var fromName: String
        var subject: String
        /// The author's own words (quotes and footers removed).
        var text: String
        var category: PostCategory
        var isPerson: Bool
    }

    /// The best rule guess, or nil when the rules are not sure.
    static func guess(_ m: Input, kids: [KidProfile]) -> DrawerGuess? {
        if m.isPerson {
            return DrawerGuess(choice: DrawerChoice(.people), confidence: .rule, reason: "Personal mail")
        }
        let haystack = (m.subject + "\n" + String(m.text.prefix(2000))).lowercased()
        let domain = InsightText.domain(of: m.fromAddress.lowercased())

        if let kid = matchKid(haystack: haystack, kids: kids) {
            return DrawerGuess(choice: DrawerChoice(.kids, child: kid.name), confidence: .rule, reason: "Mentions \(kid.name)'s school or activities")
        }
        if schoolDomains.contains(where: domain.contains) || m.category == .school || hasAny(haystack, schoolWords) {
            let only = kids.count == 1 ? kids[0].name : nil
            return DrawerGuess(choice: DrawerChoice(.kids, child: only), confidence: .rule, reason: "School or activities")
        }
        // Order before money: an order receipt is an order, not a statement.
        if DeliveryNotice.hasPhrase(haystack) || hasAny(haystack, orderWords) {
            return DrawerGuess(choice: DrawerChoice(.orders), confidence: .rule, reason: "Order or shipping")
        }
        if m.category == .travel || hasAny(haystack, travelWords) {
            return DrawerGuess(choice: DrawerChoice(.travel), confidence: .rule, reason: "Travel booking")
        }
        if hasAny(haystack, houseWords) {
            return DrawerGuess(choice: DrawerChoice(.house), confidence: .rule, reason: "House or utilities")
        }
        if m.category == .money || hasAny(haystack, moneyWords) {
            return DrawerGuess(choice: DrawerChoice(.money), confidence: .rule, reason: "Money: statement, bill or receipt")
        }
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
