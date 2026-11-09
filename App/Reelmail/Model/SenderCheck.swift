import Foundation

/// Is this sender who they say they are? Checked on the phone for every email, from the headers Gmail already returns
/// and the address itself. Nothing is sent anywhere and nothing in Gmail changes; Lovely only shows a warning.
/// Pure, so it is tested.
enum SenderCheck {
    enum Level: Int, Comparable, Sendable {
        case ok, caution, warning
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    struct Verdict: Equatable, Sendable {
        var level: Level
        /// Plain reasons, most serious first ("It failed Gmail's check that it really comes from apple.com").
        var reasons: [String]
        static let ok = Verdict(level: .ok, reasons: [])
        var title: String {
            switch level {
            case .ok: return ""
            case .caution: return "Check this sender"
            case .warning: return "This may not be who it says"
            }
        }
    }

    /// Brands that phishing mail pretends to be, with the domains their real mail comes from.
    static let brands: [(names: [String], domains: [String])] = [
        (["paypal"], ["paypal.com"]),
        (["apple", "icloud", "itunes"], ["apple.com", "icloud.com", "itunes.com", "email.apple.com"]),
        (["amazon"], ["amazon.com", "amazon.co.uk", "amazonses.com", "amazonaws.com"]),
        (["microsoft", "outlook", "office 365", "office365"], ["microsoft.com", "outlook.com", "office.com", "live.com", "microsoftonline.com"]),
        (["google", "gmail"], ["google.com", "gmail.com", "youtube.com"]),
        (["netflix"], ["netflix.com"]),
        (["bank of america"], ["bankofamerica.com", "bofa.com"]),
        (["chase"], ["chase.com", "jpmorgan.com"]),
        (["wells fargo"], ["wellsfargo.com"]),
        (["usps", "postal service"], ["usps.com", "usps.gov"]),
        (["ups"], ["ups.com"]),
        (["fedex"], ["fedex.com"]),
        (["irs", "internal revenue"], ["irs.gov"]),
        (["geek squad"], ["bestbuy.com", "geeksquad.com"]),
        (["norton"], ["norton.com", "nortonlifelock.com", "gen.com"]),
        (["mcafee"], ["mcafee.com"]),
        (["coinbase"], ["coinbase.com"]),
        (["venmo"], ["venmo.com"]),
        (["zelle"], ["zellepay.com"]),
        (["charles schwab", "schwab"], ["schwab.com"]),
        (["robinhood"], ["robinhood.com"]),
        (["docusign"], ["docusign.com", "docusign.net"]),
        (["costco"], ["costco.com"]),
        (["walmart"], ["walmart.com"]),
        (["e-zpass", "ezpass"], ["e-zpassny.com", "e-zpassiag.com", "ncquickpass.com"]),
    ]

    static let freeMail: Set<String> = ["gmail.com", "googlemail.com", "yahoo.com", "outlook.com", "hotmail.com", "live.com",
                                        "aol.com", "icloud.com", "me.com", "mac.com", "proton.me", "protonmail.com", "gmx.com", "mail.com"]

    /// - Parameters:
    ///   - authResults: Gmail's Authentication-Results header (SPF, DKIM, DMARC), when the message has one.
    ///   - known: he has written to this address before, so it is someone he knows.
    static func check(name: String, address: String, replyTo: String?, authResults: String?, known: Bool) -> Verdict {
        let addr = address.lowercased()
        let domain = String(addr.split(separator: "@").last ?? "")
        guard !domain.isEmpty else { return .ok }
        let lowName = name.lowercased()
        var warnings: [String] = []
        var cautions: [String] = []

        // 1. Gmail's own check that the mail really comes from that domain.
        if let auth = authResults?.lowercased() {
            if auth.contains("dmarc=fail") {
                // p=none means the domain asks for no enforcement; mailing lists and forwards often fail that way.
                if auth.contains("p=none") { cautions.append("Gmail could not fully confirm it comes from \(domain).") }
                else { warnings.append("It failed Gmail's check that it really comes from \(domain).") }
            }
            else if auth.contains("spf=fail"), !auth.contains("dkim=pass") { warnings.append("Gmail could not confirm it was sent by \(domain).") }
        }

        // 2. An address in the display name that is not the real address ("support@apple.com" <x@y.ru>).
        if let shown = firstAddress(in: lowName), shown != addr {
            warnings.append("The name shows \(shown), but it was sent from \(addr).")
        }

        // 3. A brand name in the display name, sent from a domain that is not the brand's.
        // Only when the name is the brand itself ("Apple", "PayPal Support"), not a business that shares a word
        // ("Apple Valley Dental") or a person ("Chase Miller").
        for brand in brands where brand.names.contains(where: { impersonates($0, name: lowName) }) {
            if !brand.domains.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) {
                let who = brand.names[0].capitalized
                if freeMail.contains(domain) { warnings.append("It says \(who), but it came from a personal \(domain) address.") }
                else if !known { cautions.append("It says \(who), but it came from \(domain), not \(brand.domains[0]).") }
            }
            break
        }

        // 4. A domain made to look like a brand's (paypa1.com, apple-support-id.com, xn--…).
        if domain.hasPrefix("xn--") || domain.contains(".xn--") {
            warnings.append("The address uses look-alike letters (\(domain)).")
        } else if let look = lookalike(domain) {
            warnings.append("\(domain) looks like \(look) but is not.")
        }

        // 5. Replies go somewhere else, for mail claiming to be a company.
        if let reply = replyTo?.lowercased(), let replyDomain = reply.split(separator: "@").last.map(String.init),
           !replyDomain.isEmpty, registrable(replyDomain) != registrable(domain), !known, freeMail.contains(replyDomain) {
            cautions.append("Replies would go to \(reply), a personal address, not \(domain).")
        }

        if !warnings.isEmpty { return Verdict(level: .warning, reasons: warnings + cautions) }
        if !cautions.isEmpty { return Verdict(level: .caution, reasons: cautions) }
        return .ok
    }

    // MARK: Helpers

    static func firstAddress(in text: String) -> String? {
        guard let r = text.range(of: #"[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}"#, options: .regularExpression) else { return nil }
        return String(text[r])
    }

    static let serviceWords: Set<String> = ["support", "team", "security", "account", "accounts", "billing", "id", "customer",
                                            "service", "services", "notification", "notifications", "alert", "alerts", "inc",
                                            "the", "help", "center", "centre", "noreply", "no-reply", "official", "online",
                                            "bank", "pay", "payments", "store", "prime", "delivery", "verification", "-", "|", "&"]

    /// The display name is just the brand plus service words ("PayPal", "Apple Support", "Chase Bank Alerts").
    static func impersonates(_ brand: String, name: String) -> Bool {
        guard containsWord(brand, in: name) else { return false }
        let rest = name.replacingOccurrences(of: brand, with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .filter { !$0.isEmpty }
        return rest.allSatisfy { serviceWords.contains($0) }
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        text.range(of: "(^|[^a-z])" + NSRegularExpression.escapedPattern(for: word) + "([^a-z]|$)", options: .regularExpression) != nil
    }

    /// "mail.paypal.com" -> "paypal.com" (good enough for .com/.net/.org/.gov style domains).
    static func registrable(_ domain: String) -> String {
        let parts = domain.split(separator: ".")
        guard parts.count > 2 else { return domain }
        let twoLevel: Set<String> = ["co.uk", "com.au", "co.jp"]
        let lastTwo = parts.suffix(2).joined(separator: ".")
        return twoLevel.contains(lastTwo) ? parts.suffix(3).joined(separator: ".") : lastTwo
    }

    /// A brand domain this one imitates: one letter off, digits for letters, or the brand plus extra words.
    static func lookalike(_ domain: String) -> String? {
        let reg = registrable(domain)
        let label = String(reg.split(separator: ".").first ?? "")
        for brand in brands {
            for real in brand.domains {
                let realReg = registrable(real)
                if reg == realReg { return nil }
                let realLabel = String(realReg.split(separator: ".").first ?? "")
                guard realLabel.count >= 5 else { continue }   // short names (ups, irs) match too much
                let unDigited = label.replacingOccurrences(of: "0", with: "o").replacingOccurrences(of: "1", with: "l")
                    .replacingOccurrences(of: "rn", with: "m")
                if unDigited == realLabel, label != realLabel { return realReg }
                if label.count == realLabel.count || abs(label.count - realLabel.count) == 1,
                   editDistance(label, realLabel) == 1 { return realReg }
                if label.contains(realLabel), label != realLabel,
                   ["-", "secure", "support", "verify", "account", "login", "billing", "alert", "service", "id"].contains(where: { label.contains($0) }) {
                    return realReg
                }
            }
        }
        return nil
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
