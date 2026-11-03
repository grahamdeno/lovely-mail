import Foundation

/// Where a message sits in the feed. Order is the feed's priority, top to bottom.
enum FeedSection: Int, CaseIterable, Identifiable, Comparable {
    /// A person asked something and no reply from you is newer than the ask.
    case waiting
    /// Mail you sent yourself from another address of yours, to move information around.
    case notes
    /// Mail from people, with nothing open.
    case people
    /// Automated mail that carries a date: forms, appointments, travel, bills.
    case dated
    /// Receipts, shipping, account notices.
    case updates
    /// Newsletters and anything you routed to Reading.
    case reading

    var id: Int { rawValue }
    static func < (a: FeedSection, b: FeedSection) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .waiting: return "Waiting on you"
        case .notes: return "Notes to self"
        case .people: return "People"
        case .dated: return "Coming up"
        case .updates: return "Updates"
        case .reading: return "Reading"
        }
    }
}

/// Home filter pills. `all` shows every section in priority order.
enum FeedFilter: String, CaseIterable, Identifiable {
    case all, waiting, notes, people, updates, reading
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .waiting: return "Waiting on you"
        case .notes: return "Notes to self"
        case .people: return "People"
        case .updates: return "Updates"
        case .reading: return "Reading"
        }
    }
    func includes(_ section: FeedSection) -> Bool {
        switch self {
        case .all: return true
        case .waiting: return section == .waiting
        case .notes: return section == .notes
        case .people: return section == .people || section == .waiting
        case .updates: return section == .updates || section == .dated
        case .reading: return section == .reading
        }
    }
}

/// What triage knows about you: your addresses and names (from your sent mail), your replies, and the time.
struct TriageContext {
    /// An ask older than this drops out of "Waiting on you" into People. The list stays short and current.
    static let waitingWindow: TimeInterval = 14 * 86_400
    /// Mail sent to more people than this is a group announcement, not a question to you.
    static let maxDirectRecipients = 6

    var myAddresses: Set<String>
    /// Other addresses you declared as yours. Mail from them is a note to self.
    var otherAddresses: Set<String>
    var replies: [String: Date]
    var now: Date

    init(myAddresses: Set<String> = [], otherAddresses: Set<String> = [], replies: [String: Date] = [:], now: Date = Date()) {
        self.myAddresses = Set(myAddresses.map(Self.canonical))
        self.otherAddresses = Set(otherAddresses.map(Self.canonical))
        self.replies = replies
        self.now = now
    }

    /// Builds the context from the signed-in account. Identity is the address only; a display name proves nothing,
    /// and mail you send yourself from another account is a person asking you for something.
    init(account: String?, sent: [Email], otherAddresses: [String] = [], now: Date) {
        var addresses = Set(sent.filter(\.isFromMe).map { $0.from.email.lowercased() })
        if let account, !account.isEmpty { addresses.insert(account.lowercased()) }
        self.init(myAddresses: addresses, otherAddresses: Set(otherAddresses), replies: FeedTriage.latestReplies(in: sent), now: now)
    }

    /// Gmail ignores dots and anything after "+" in the part before the @, so graham.denoyer@gmail.com
    /// and grahamdenoyer@gmail.com are the same inbox. Other providers are compared as written.
    static func canonical(_ address: String) -> String {
        let lower = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = lower.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[1] == "gmail.com" || parts[1] == "googlemail.com" else { return lower }
        let local = parts[0].split(separator: "+", maxSplits: 1).first.map(String.init) ?? parts[0]
        return local.replacingOccurrences(of: ".", with: "") + "@gmail.com"
    }

    func isMine(_ email: Email) -> Bool {
        email.isFromMe || myAddresses.contains(Self.canonical(email.from.email))
    }

    /// From another address you declared yours.
    func isNoteToSelf(_ email: Email) -> Bool {
        !isMine(email) && otherAddresses.contains(Self.canonical(email.from.email))
    }

    /// `blindCopy`: no visible recipients, or addressed only to the sender itself (a list sent as a blind copy).
    enum Addressing: Equatable { case direct, copied, group, blindCopy }

    func addressing(of email: Email) -> Addressing {
        let to = email.to.map(Self.canonical)
        if to.isEmpty || to == [Self.canonical(email.from.email)] { return .blindCopy }
        if myAddresses.isEmpty { return to.count > Self.maxDirectRecipients ? .group : .direct }
        if to.contains(where: myAddresses.contains) { return to.count > Self.maxDirectRecipients ? .group : .direct }
        if email.cc.map(Self.canonical).contains(where: myAddresses.contains) { return .copied }
        // You are not visible on the message: a forwarding alias (one recipient) or a blind copy to many.
        return to.count == 1 ? .direct : .group
    }
}

/// Where a message goes and the plain-language reason, shown to you.
struct TriageAssessment: Equatable {
    let section: FeedSection
    let reason: String
    /// The sentence that asks you something, when there is one.
    var ask: String? = nil
}

/// Pure sorting rules. Views never decide these.
enum FeedTriage {
    /// The newest message you sent in each thread, by thread id.
    static func latestReplies(in sent: [Email]) -> [String: Date] {
        var out: [String: Date] = [:]
        for email in sent where email.isFromMe {
            if let existing = out[email.threadId], existing >= email.date { continue }
            out[email.threadId] = email.date
        }
        return out
    }

    /// "Waiting on you" is deliberately strict. Every condition must hold:
    /// a person (not a system) wrote it, it is not from you, it asks you something in their own words,
    /// Apple Intelligence (when it ran) agrees it needs a reply, you have not replied since,
    /// it was sent to you directly (not a cc or a group), it is under two weeks old,
    /// and you have not marked it (or the sender) as not waiting.
    static func assess(_ post: Post, route: LocalMailDestination, routeReason: String = "Your rule",
                       notWaiting: Bool = false, context: TriageContext) -> TriageAssessment {
        let email = post.email
        if route == .reading { return TriageAssessment(section: .reading, reason: routeReason) }
        // Mail you sent yourself, from this address or one you declared, is a note even when it is a forwarded
        // newsletter or receipt.
        if context.isMine(email) { return TriageAssessment(section: .notes, reason: "You sent this to yourself") }
        if context.isNoteToSelf(email) { return TriageAssessment(section: .notes, reason: "From your other address, " + email.from.email) }
        if post.summary.category == .newsletter { return TriageAssessment(section: .reading, reason: "Newsletter or mailing list") }
        if let why = automatedReason(email) {
            let text = email.subject + "\n" + email.body
            if MailKind.isMarketing(text) { return TriageAssessment(section: .reading, reason: "Promotion or marketing mail") }
            if MailKind.isShipping(text) { return TriageAssessment(section: .updates, reason: why + "; shipping or delivery") }
            if MailKind.isReceipt(text) { return TriageAssessment(section: .updates, reason: why + "; a receipt or finished service") }
            let dated = !post.summary.dates.isEmpty || MailKind.mentionsDay(text)
                || [.school, .travel, .events].contains(post.summary.category)
            return TriageAssessment(section: dated ? .dated : .updates, reason: dated ? why + "; it mentions a date" : why)
        }
        let first = email.from.firstName
        guard let ask = ReplySignals.askSentence(in: email.body) else {
            return TriageAssessment(section: .people, reason: "From \(first). Nothing asked of you.")
        }
        if post.summary.engine == .appleIntelligence, !post.summary.needsReply {
            return TriageAssessment(section: .people, reason: "From \(first). Apple Intelligence found no request.", ask: ask)
        }
        if let reply = context.replies[email.threadId], reply > email.date {
            return TriageAssessment(section: .people, reason: "You replied " + relativeAge(of: reply, now: context.now) + ".", ask: ask)
        }
        if notWaiting { return TriageAssessment(section: .people, reason: "You marked this as not waiting.", ask: ask) }
        switch context.addressing(of: email) {
        case .copied: return TriageAssessment(section: .people, reason: "You were copied, not asked directly.", ask: ask)
        case .group: return TriageAssessment(section: .people, reason: "Sent to a group of \(email.to.count).", ask: ask)
        case .blindCopy: return TriageAssessment(section: .people, reason: "Sent to a list as a blind copy, not to you directly.", ask: ask)
        case .direct: break
        }
        let age = context.now.timeIntervalSince(email.date)
        if age > TriageContext.waitingWindow {
            return TriageAssessment(section: .people, reason: "\(first) asked " + relativeAge(of: email.date, now: context.now) + ". Older asks leave Waiting after two weeks.", ask: ask)
        }
        return TriageAssessment(section: .waiting, reason: "\(first) asked " + relativeAge(of: email.date, now: context.now), ask: ask)
    }

    static func section(for post: Post, route: LocalMailDestination, context: TriageContext) -> FeedSection {
        assess(post, route: route, context: context).section
    }

    /// Why a message counts as automated, or nil when a person wrote it.
    static func automatedReason(_ email: Email) -> String? {
        if email.bulk { return "Automated or bulk mail (Gmail tab or list headers)" }
        if email.from.isAutomated { return "Sent from a system address" }
        if ReplySignals.isMachineText(subject: email.subject, body: email.body) { return "Automated notice (do-not-reply or portal message)" }
        return nil
    }

    /// "today", "yesterday", "3 days ago", "2 weeks ago".
    static func relativeAge(of date: Date, now: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default: return "\(days / 30) months ago"
        }
    }
}

/// Keyword signals for automated mail. Only used after a message is already known to be automated.
enum MailKind {
    private static let marketing = ["shop now", "% off", "limited time", "promo code", "use code", "new arrivals", "sitewide"]
    private static let shipping = ["shipped", "arriving", "out for delivery", "delivered", "tracking", "track it", "your package"]
    /// A weekday, "tomorrow", or a numeric date like 11/19. Month names are covered by the summary's dates.
    private static let dayPattern = #"\b(mon|tues|wednes|thurs|fri|satur|sun)day\b|\btomorrow\b|\b\d{1,2}/\d{1,2}\b"#

    static func isMarketing(_ text: String) -> Bool { let l = text.lowercased(); return marketing.contains { l.contains($0) } }
    /// Shipping and delivery notices carry dates, but nothing you need to show up for.
    static func isShipping(_ text: String) -> Bool { let l = text.lowercased(); return shipping.contains { l.contains($0) } }
    private static let receipt = ["receipt", "completed service", "has been paid", "payment received", "received your payment",
                                  "thank you for your payment", "refund"]
    /// Receipts and finished services name past days ("on Wednesday (10/28)"); they are not coming up.
    static func isReceipt(_ text: String) -> Bool { let l = text.lowercased(); return receipt.contains { l.contains($0) } }
    static func mentionsDay(_ text: String) -> Bool {
        text.lowercased().range(of: dayPattern, options: .regularExpression) != nil
    }
}

/// Reply detection that ignores the parts of an email no one is asking you about.
enum ReplySignals {
    private static let asks = ["let me know", "can you", "could you", "would you", "please confirm", "rsvp",
                               "are you free", "please reply", "your thoughts", "what do you think", "any word",
                               "did you", "do you", "will you", "wondering if", "thoughts?",
                               "if you could", "if you can", "if you're able", "if you are able", "are you available",
                               "available next", "available on", "email me back", "email me", "get back to me",
                               "write back", "reply to me", "call me", "text me", "give me a call", "send me",
                               "i need you", "i need your", "need your help", "need some help", "help me",
                               "some help", "can we", "could we", "when can", "when are you", "please send",
                               "please let", "please call", "please review", "please sign", "please respond",
                               "hoping you could", "hoping you can", "was hoping you", "would love your",
                               "would appreciate", "could use your",
                               // A business asking you to act on its site counts as waiting on you (owner's call, Nov 2).
                               "please log", "log onto", "log on to", "esign", "please complete", "please fill", "please pay"]

    /// Sentences that sound like asks but are courtesy or rhetoric: "Let me know if you have any questions",
    /// "Feel free to call me", "Can you believe this weather".
    private static let courtesy = [#"let me know if you (have any questions|need anything|need any)"#,
                                   #"let me know if (there is|there's) anything"#, #"if you have any questions"#,
                                   #"feel free to"#, #"(don't|do not) hesitate"#, #"if anything comes up"#,
                                   #"can you believe"#, #"would you believe"#, #"who knew"#, #"guess what"#]

    static func isCourtesy(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return courtesy.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    /// The author's own words: no quoted earlier mail, no signature block, no link-heavy footer lines.
    static func authoredText(_ body: String) -> String {
        var kept: [String] = []
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "--" || line == "-- " || line.hasPrefix("—") && line.count < 4 { break }
            if line.range(of: #"^On .+ wrote:$"#, options: .regularExpression) != nil { break }
            if line.hasPrefix("-----Original Message-----") || line.hasPrefix("From: ") && kept.count > 2 { break }
            // A forwarded message is someone else's words (Gmail and Apple Mail markers).
            if line.range(of: #"^-{2,}\s*Forwarded message\s*-{2,}"#, options: .regularExpression) != nil
                || line == "Begin forwarded message:" { break }
            if line.hasPrefix(">") { continue }
            let lower = line.lowercased()
            if lower.contains("unsubscribe") || lower.contains("http://") || lower.contains("https://") { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    /// Phrases that mark machine-sent mail even when the sender address looks personal
    /// (portals, schools, HOAs, booking systems).
    private static let machinePhrases = [
        "do not reply", "do-not-reply", "please don't reply", "please do not respond", "this is an automated",
        "automatically generated", "auto-generated", "this mailbox is not monitored", "unmonitored", "not monitored",
        "you have a new message", "you have received a new", "new private message", "you have a new private",
        "log in to view", "login to view", "sign in to view", "click here to view", "view this message",
        "to view the message", "view it online", "reply above this line", "you are receiving this",
        "you received this email because", "manage your notification", "notification settings",
        "verification code", "security code", "one-time code", "your code is", "passcode",
        "automatic reply", "auto-reply", "autoreply", "out of office", "out of the office",
        "has been scheduled for", "you are scheduled for",
    ]
    /// Booking systems: "Reply C to confirm", "Reply Y to confirm or N to cancel".
    private static let replyCode = #"\breply [a-z]{1,3} to (confirm|cancel)"#

    static func isMachineText(subject: String, body: String) -> Bool {
        let lower = (subject + "\n" + authoredText(body)).lowercased()
        return machinePhrases.contains { lower.contains($0) } || lower.range(of: replyCode, options: .regularExpression) != nil
    }

    /// The first sentence in the author's own words that asks you something, trimmed for display.
    static func askSentence(in body: String) -> String? {
        let text = authoredText(body)
        // Line breaks end sentences too, and a greeting line ("Hi Pat,") is never the ask.
        var candidates: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || FallbackSummarizer.isGreeting(trimmed) { continue }
            var current = ""
            for ch in trimmed {
                current.append(ch)
                if ".!?".contains(ch) { candidates.append(current); current = "" }
            }
            if !current.trimmingCharacters(in: .whitespaces).isEmpty { candidates.append(current) }
        }
        for raw in candidates {
            let sentence = raw.trimmingCharacters(in: .whitespaces)
            guard sentence.count >= 6, !isCourtesy(sentence) else { continue }
            let lower = sentence.lowercased()
            let asks = sentence.hasSuffix("?") && sentence.range(of: #"[A-Za-z][^.!?]{2,}\?$"#, options: .regularExpression) != nil
            if asks || Self.asks.contains(where: { lower.contains($0) }) {
                return sentence.count > 140 ? String(sentence.prefix(137)) + "…" : sentence
            }
        }
        return nil
    }

    static func needsReply(body: String, automated: Bool, category: PostCategory) -> Bool {
        guard !automated, category != .newsletter else { return false }
        let text = authoredText(body)
        let lower = text.lowercased()
        if asks.contains(where: { lower.contains($0) }) { return true }
        // A question mark counts only when it ends a sentence the author wrote.
        return text.range(of: #"[A-Za-z][^.!?\n]{2,}\?(\s|$)"#, options: .regularExpression) != nil
    }
}
