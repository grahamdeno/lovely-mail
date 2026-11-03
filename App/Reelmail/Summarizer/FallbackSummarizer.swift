import Foundation

/// Heuristic summarizer for when Apple Intelligence is unavailable:
/// subject as the headline, the first real sentence as the blurb, keyword rules for the rest.
struct FallbackSummarizer: EmailSummarizer {
    var engine: SummaryEngine { .fallback }

    static let headlineMaxWords = 8
    static let blurbMaxWords = 25

    func summarize(_ input: SummaryInput) async throws -> EmailSummary {
        summarizeSync(input)
    }

    func summarizeSync(_ input: SummaryInput) -> EmailSummary {
        let text = (input.subject + "\n" + input.body).lowercased()
        let category = Self.category(for: text, automated: input.senderIsAutomated)
        return EmailSummary(
            headline: TextClamp.words(Self.cleanSubject(input.subject, fallbackBody: input.body), max: Self.headlineMaxWords),
            blurb: TextClamp.words(Self.firstSentence(of: input.body), max: Self.blurbMaxWords),
            needsReply: Self.needsReply(body: input.body, automated: input.senderIsAutomated, category: category),
            category: category,
            imageQuery: category.defaultImageQuery,
            sensitive: Self.isSensitive(text),
            dates: Self.dates(in: input.subject + "\n" + input.body),
            engine: .fallback
        )
    }

    static func cleanSubject(_ subject: String, fallbackBody: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespaces)
        let prefixes = ["re:", "fwd:", "fw:"]
        var changed = true
        while changed {
            changed = false
            for p in prefixes where s.lowercased().hasPrefix(p) {
                s = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return s.isEmpty ? firstSentence(of: fallbackBody) : s
    }

    /// First sentence after dropping a greeting line like "Hi Graham,".
    static func firstSentence(of body: String) -> String {
        var lines = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = lines.first, isGreeting(first), lines.count > 1 { lines.removeFirst() }
        let text = lines.joined(separator: " ")
        guard !text.isEmpty else { return "" }
        // Take the first break that ends a real sentence: not after "Mr." or "J.", and not before three words.
        var from = text.startIndex
        while let range = text.range(of: #"[.!?](\s|$)"#, options: .regularExpression, range: from..<text.endIndex) {
            let candidate = String(text[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
            if endsSentence(candidate) { return candidate }
            from = range.upperBound
        }
        return text
    }

    private static let abbreviations: Set<String> = ["mr.", "mrs.", "ms.", "dr.", "st.", "jr.", "sr.", "vs.", "e.g.", "i.e."]

    /// A candidate ends a sentence when it has at least three words and does not stop on an abbreviation or an initial.
    private static func endsSentence(_ candidate: String) -> Bool {
        guard TextClamp.wordCount(candidate) >= 3 else { return false }
        guard candidate.hasSuffix("."), let token = candidate.split(separator: " ").last.map(String.init) else { return true }
        let word = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(")).lowercased()
        if abbreviations.contains(word) { return false }
        return token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(")).range(of: #"^[A-Z]\.$"#, options: .regularExpression) == nil
    }

    static func isGreeting(_ line: String) -> Bool {
        let l = line.lowercased()
        let starts = ["hi", "hey", "hello", "dear", "good morning", "good afternoon", "greetings"]
        let short = TextClamp.wordCount(line) <= 4
        return short && (line.hasSuffix(",") || line.hasSuffix("!") || starts.contains { l.hasPrefix($0) })
    }

    static func category(for lower: String, automated: Bool) -> PostCategory {
        func has(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }
        if has(["unsubscribe", "in this issue", "newsletter"]) { return .newsletter }
        if has(["$", "receipt", "statement", "invoice", "amount due", "quote for", "refund"]) { return .money }
        if has(["flight", "check-in", "boarding", "hotel", "trip to", "itinerary"]) { return .travel }
        if has(["school", "teacher", "field trip", "permission form", "grade"]) { return .school }
        if has(["game", "hike", "party", "rsvp", "team photo", "season final"]) { return .events }
        if has(["draft", "meeting", "the call", "a call", "launch", "brochure", "workshop", "deadline"]) { return .work }
        return automated ? .updates : .people
    }

    static func needsReply(body: String, automated: Bool, category: PostCategory) -> Bool {
        ReplySignals.needsReply(body: body, automated: automated, category: category)
    }

    /// Wording that means a secret is in the message. "Temporary password will come in a separate email" is not one.
    private static let secretPhrases = ["verification code", "security code", "one-time code", "your code is", "password reset",
                                        "passcode", "api key", "secret key", "social security", "account number", "routing number"]
    private static let secretPatterns = [
        #"(your|the|a) (temporary |new |one-time )?password (is|:)"#,
        #"(temporary|new) password( is|:)"#,
        #"\bpassword:"#,
        #"\bsk-[a-z0-9_\-]{20,}"#,
    ]

    static func isSensitive(_ lower: String) -> Bool {
        // Real secrets only: codes, passwords, keys and account numbers. Ordinary mail keeps its preview.
        let text = ReplySignals.normalizeQuotes(lower).lowercased()
        if secretPhrases.contains(where: { text.contains($0) }) { return true }
        if secretPatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) { return true }
        // Long ids inside links (tracking, unsubscribe, order pages) are not secrets: check only text outside URLs.
        let outsideLinks = text.replacingOccurrences(of: #"(https?://|www\.)\S+"#, with: " ", options: .regularExpression)
        return hasKeyLikeToken(outsideLinks)
    }

    /// A run of 32 or more letters and digits with both present: an API key, token or hash.
    static func hasKeyLikeToken(_ text: String) -> Bool {
        var search = text.startIndex
        while let r = text.range(of: #"[A-Za-z0-9]{32,}"#, options: .regularExpression, range: search..<text.endIndex) {
            let run = text[r]
            if run.contains(where: { $0.isLetter }) && run.contains(where: { $0.isNumber }) { return true }
            search = r.upperBound
        }
        return false
    }

    private static let datePattern = try! NSRegularExpression(
        pattern: #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})\b"#)

    /// Month-day mentions, normalized like "Nov 7", in order, without duplicates.
    static func dates(in text: String) -> [String] {
        let ns = text as NSString
        var out: [String] = []
        for m in datePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let month = ns.substring(with: m.range(at: 1))
            let day = ns.substring(with: m.range(at: 2))
            let value = "\(month.prefix(3)) \(Int(day) ?? 0)"
            if !out.contains(value) { out.append(value) }
        }
        return out
    }
}
