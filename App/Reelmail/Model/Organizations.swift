import Foundation

/// Which organization a sender belongs to. Senders group by their company's domain
/// (mail.fidelity.com and shareholderdocs.fidelity.com are both fidelity.com). Shared sending services
/// (Gmail, Apple's Hide My Email relay, newsletter and form platforms) say nothing about the company,
/// so those group by display name. Your own merges and splits win. Pure, so it is tested.
enum OrganizationKey {
    /// Domains many unrelated senders share.
    static let sharedDomains: Set<String> = [
        "gmail.com", "googlemail.com", "yahoo.com", "hotmail.com", "outlook.com", "live.com", "icloud.com", "me.com",
        "mac.com", "aol.com", "proton.me", "protonmail.com", "privaterelay.appleid.com", "sendgrid.net",
        "mailchimpapp.net", "mcsv.net", "mcdlv.net", "amazonses.com", "govdelivery.com", "applyresponse.com",
        "aptleasing.info", "mailgun.org", "sparkpostmail.com", "constantcontact.com", "hubspotemail.net",
        "exacttarget.com", "mktomail.com", "zendesk.com", "freshdesk.com", "intercom-mail.com", "substack.com",
        "beehiiv.com", "convertkit.com", "squarespace-mail.com", "shopifyemail.com", "klaviyomail.com",
        "narvar.com", "dashplatform.com", "infinitecampus.org", "procaresoftware.com", "gomotionapp.com",
    ]
    /// Two-part public suffixes, so example.co.uk stays example.co.uk.
    static let twoPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.nz", "co.jp", "com.br", "com.mx",
        "co.in", "co.za", "com.sg", "com.cn",
    ]

    /// The company's own domain ("fidelity.com"), or nil for a shared service or a bad address.
    static func domain(of address: String) -> String? {
        let parts = address.lowercased().split(separator: "@")
        guard parts.count == 2 else { return nil }
        let labels = parts[1].split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let registrable = twoPartSuffixes.contains(lastTwo) && labels.count >= 3 ? labels.suffix(3).joined(separator: ".") : lastTwo
        // A shared service sends from its own subdomains too (em.substack.com, mail.app.supabase.io is fine).
        if sharedDomains.contains(registrable) || sharedDomains.contains(parts[1].description) { return nil }
        if sharedDomains.contains(where: { parts[1].hasSuffix("." + $0) }) { return nil }
        return registrable
    }

    /// The group a sender belongs to: your override, else "d:<domain>", else "n:<name>".
    static func key(for person: Person, overrides: [String: String]) -> String {
        if let override = overrides[person.email.lowercased()] { return override }
        if let domain = domain(of: person.email) { return "d:" + domain }
        return "n:" + HomeDigest.organizationName(person).lowercased()
    }

    /// "Split this sender out": a group of its own.
    static func splitKey(for address: String) -> String { "s:" + address.lowercased() }

    /// The domain behind a group key, when there is one (used for the logo).
    static func domain(ofKey key: String) -> String? { key.hasPrefix("d:") ? String(key.dropFirst(2)) : nil }

    /// The name shown for a group: its most common display name, else its domain's main label.
    static func displayName(for senders: [Person], key: String) -> String {
        var counts: [String: Int] = [:]
        for p in senders { counts[HomeDigest.organizationName(p), default: 0] += 1 }
        if let best = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key { return best }
        return domain(ofKey: key) ?? "Organization"
    }
}

/// Person or organization, for senders whose mail isn't plainly automated (Gmail files plenty of company mail
/// as personal). Pure, so it is tested.
enum PersonSignals {
    /// Words that mark a company, office or group rather than a person.
    static let organizationWords: Set<String> = [
        "group", "inc", "inc.", "llc", "llc.", "ltd", "co", "co.", "company", "corp", "corporation", "bank", "insurance",
        "services", "service", "support", "team", "reserve", "apartments", "apartment", "residences", "academy",
        "school", "schools", "clinic", "church", "store", "shop", "office", "admissions", "health", "center", "centre",
        "foundation", "association", "club", "league", "recreation", "department", "university", "college", "county",
        "city", "the", "customer", "billing", "orders", "news", "newsletter", "hoa", "pta", "district", "agency",
        "partners", "studio", "studios", "media", "app", "family", "families", "community", "program", "camp",
    ]
    static let freeMail: Set<String> = ["gmail.com", "googlemail.com", "yahoo.com", "hotmail.com", "outlook.com", "live.com",
                                        "icloud.com", "me.com", "mac.com", "aol.com", "proton.me", "protonmail.com", "msn.com"]

    /// You've written to them, or their name reads like a person's (or they write from a personal mailbox).
    static func looksLikePerson(name: String, email: String, youWrote: Bool) -> Bool {
        if youWrote { return true }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let words = trimmed.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        if words.contains(where: organizationWords.contains) { return false }
        let domain = email.lowercased().split(separator: "@").last.map(String.init) ?? ""
        if trimmed.isEmpty || trimmed.contains("@") { return freeMail.contains(domain) }
        if freeMail.contains(domain) { return true }
        // "Amy Hand", "James Brendle", "Hand, Amy": two to four capitalized words.
        let original = trimmed.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        return (2...4).contains(original.count) && original.allSatisfy { $0.first?.isUppercase == true }
    }

    /// "julia denoyer" for a two-to-four word name, used to treat one person's two addresses as one.
    static func mergeKey(for name: String) -> String? {
        let words = name.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard (2...4).contains(words.count), !name.contains("@") else { return nil }
        return words.sorted().joined(separator: " ")
    }
}
