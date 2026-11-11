import Foundation

/// Removes secrets and identifiers from text before it goes into a prompt for Grok Bot. Pure.
/// It errs toward removing too much: a missing detail is easy to add by hand, a leaked code is not.
enum Redactor {
    static func redact(_ text: String, keepEmails: Set<String> = []) -> String {
        var s = text
        func sub(_ pattern: String, _ template: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        // Passwords and codes named in words, in either order.
        sub(#"\b(pass(?:word|code)|pin|otp|one[- ]time (?:code|password)|verification code|security code|access code|login code|code)\s*(?:is|:|=|-)?\s*[A-Za-z0-9!@#$%^&*._-]{4,}"#, "$1 [removed]")
        sub(#"\b\d{4,8}\s+is your\b"#, "[removed] is your")
        // Card, SSN and account-style numbers.
        sub(#"\b(?:\d[ -]?){13,19}\b"#, "[number removed]")
        sub(#"\b\d{3}-\d{2}-\d{4}\b"#, "[number removed]")
        sub(#"\b\d{6,}\b"#, "[number removed]")
        sub(#"(?:account|acct|routing|member|policy|confirmation)\s*(?:number|no\.?|#)?\s*[:#]?\s*[A-Za-z0-9-]{5,}"#, "account [removed]")
        // Links keep their address but lose tokens in the query string, the fragment, and long path segments (reset and sign-in links).
        sub(#"(https?://[^\s?#<>]+)[?#][^\s<>]*"#, "$1")
        sub(#"(https?://[^\s<>]*?)/[A-Za-z0-9_=%.-]{16,}"#, "$1/[removed]", options: [])
        // Long tokens anywhere: letters and digits mixed, 20 or more characters.
        sub(#"\b(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{20,}\b"#, "[removed]", options: [])
        // Email addresses, except ones the owner chose to keep.
        if let re = try? NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#) {
            let ns = s as NSString
            var out = ""; var last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let found = ns.substring(with: m.range)
                out += keepEmails.contains(found.lowercased()) ? found : "[email]"
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            s = out
        }
        return s
    }
}

enum HandoffPrompt {
    /// Health mail, or mail the on-device summary flagged as sensitive, never becomes a prompt.
    static func isAllowed(address: String, name: String = "", subject: String, sensitive: Bool) -> Bool {
        !sensitive && !HealthMail.isHealth(address: address, name: name, subject: subject)
    }

    /// Older agent reports used "[Lovely] H-1234" subjects; the planner still labels any that arrive.
    static func isReport(subject: String) -> Bool { subject.trimmingCharacters(in: .whitespaces).hasPrefix("[Lovely] H-") }
}
