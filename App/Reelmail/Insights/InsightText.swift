import Foundation

/// Small regex helpers. Pure.
enum Rx {
    /// Capture groups of the first match; index 0 is the whole match. Nil when nothing matches.
    static func groups(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String]? {
        all(pattern, in: text, options: options).first
    }

    /// Capture groups of every match, in order.
    static func all(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    static func test(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// Text cleanup shared by the insight parsers. Pure.
enum InsightText {
    /// Links, markdown links and runs of whitespace removed, so a label sits next to its value.
    static func flatten(_ body: String) -> String {
        var s = body
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<https?://[^>]*>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[\x{00AD}\x{034F}\x{200B}-\x{200F}]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// "1,142.5" or "$4.29" to a number.
    static func money(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// The part after the @, lowercased.
    static func domain(of address: String) -> String {
        guard let at = address.lastIndex(of: "@") else { return "" }
        return String(address[address.index(after: at)...]).lowercased()
    }

    /// "mail.fidelity.com" and "shareholderdocs.fidelity.com" both give "fidelity.com".
    static func registrable(_ domain: String) -> String {
        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return domain }
        let twoLevel: Set<String> = ["co", "com", "org", "net", "gov", "mil", "edu"]
        if parts.count >= 3, let tld = parts.last, tld.count == 2, twoLevel.contains(parts[parts.count - 2]) {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }
}

/// Dates written the way bills and alerts write them. UTC, so a day stays the same day anywhere.
enum InsightDates {
    static let utc = TimeZone(identifier: "UTC")!

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = format
        return f
    }

    static func parse(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["M/d/yyyy", "MMMM d, yyyy", "MMM d, yyyy", "yyyy-MM-dd"] {
            if let d = formatter(format).date(from: t) { return d }
        }
        return nil
    }

    /// "yyyy-MM-dd" in UTC, for tests and keys.
    static func iso(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }

    /// First day of the month named "October 2026".
    static func month(_ name: String, year: String) -> Date? {
        formatter("MMMM d, yyyy").date(from: "\(name) 1, \(year)")
    }

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }
}
