import Foundation

/// Rules for the open-email screen. Pure, so they can be tested without views.
enum EmailPresentation {
    /// Bodies longer than this get a one-line "In short" summary above them. Short mail is its own summary.
    static let summaryThreshold = 600

    static func showsSummary(_ email: Email) -> Bool {
        email.body.trimmingCharacters(in: .whitespacesAndNewlines).count > summaryThreshold
    }

    /// The address in a header value: "Dana Brooks <dana@x.example>" or "dana@x.example".
    static func address(in value: String) -> String {
        if let open = value.lastIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close {
            return String(value[value.index(after: open)..<close]).trimmingCharacters(in: .whitespaces).lowercased()
        }
        return value.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// True when anyone besides you is on To or Cc. Then the full lists are shown, so group mail keeps its recipients;
    /// mail sent only to you needs no recipient line.
    static func showsRecipients(_ email: Email, mine: Set<String>) -> Bool {
        let me = Set(mine.map(TriageContext.canonical))
        return (email.to + email.cc).contains { !me.contains(TriageContext.canonical(address(in: $0))) }
    }

    /// "Oct 26 · 8 days ago".
    static func dateLine(_ date: Date, now: Date) -> String {
        let day = MailTime.label(date)
        let age = HomeDigest.age(of: date, now: now)
        return age == "today" ? day : day + " · " + age + " ago"
    }

    /// The body with web addresses, email addresses, phone numbers and street addresses made tappable.
    /// Detection runs on the phone; nothing is fetched.
    static func linked(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return out }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = url(for: match, in: ns),
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].link = url
        }
        return out
    }

    private static func url(for match: NSTextCheckingResult, in text: NSString) -> URL? {
        switch match.resultType {
        case .link:
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else { return nil }
            return url
        case .phoneNumber:
            guard let number = match.phoneNumber else { return nil }
            let digits = number.filter { $0.isNumber || $0 == "+" }
            return digits.count >= 7 ? URL(string: "tel:" + digits) : nil
        case .address:
            var c = URLComponents(string: "https://maps.apple.com/")
            c?.queryItems = [URLQueryItem(name: "q", value: text.substring(with: match.range))]
            return c?.url
        default:
            return nil
        }
    }
}
