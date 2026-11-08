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

/// Home filter pills. `all` is the digest (Waiting, New, People, Organizations, Earlier);
/// the others list their sections in priority order.
enum FeedFilter: String, CaseIterable, Identifiable {
    case all, waiting, notes, people, organizations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .waiting: return "Waiting"
        case .notes: return "Notes to self"
        case .people: return "People"
        case .organizations: return "Organizations"
        }
    }
    func includes(_ section: FeedSection) -> Bool {
        switch self {
        case .all: return true
        case .waiting: return section == .waiting
        case .notes: return section == .notes
        case .people: return section == .people || section == .waiting
        case .organizations: return section == .dated || section == .updates || section == .reading
        }
    }
}

/// The Home "All" view: what needs you, what's new, the people you hear from, organizations grouped by sender,
/// and everything older folded into one row. Pure, so it is tested without views.
struct HomeDigest {
    /// Read mail older than this folds into Earlier. Waiting and unread mail never do.
    static let recentWindow: TimeInterval = 14 * 86_400
    /// Unread this long gets "Still need this?".
    static let staleAfter: TimeInterval = 30 * 86_400

    struct OrganizationGroup: Identifiable, Equatable {
        let id: String
        let name: String
        let posts: [Post]
        var latest: Date { posts.map(\.email.date).max() ?? .distantPast }
        /// The company's domain, for its logo. Nil for groups by name.
        var domain: String? { OrganizationKey.domain(ofKey: id) }
        /// Each sending address and how many messages it sent, most first.
        var senders: [(address: String, count: Int)] {
            var counts: [String: Int] = [:]
            for p in posts { counts[p.email.from.email.lowercased(), default: 0] += 1 }
            return counts.map { ($0.key, $0.value) }.sorted { $0.count == $1.count ? $0.address < $1.address : $0.count > $1.count }
        }

        /// Groups posts by organization key, newest group first.
        static func group(_ posts: [Post], key: (Post) -> String) -> [OrganizationGroup] {
            var byKey: [String: [Post]] = [:]
            for post in posts { byKey[key(post), default: []].append(post) }
            return byKey.map { k, v in
                OrganizationGroup(id: k, name: OrganizationKey.displayName(for: v.map(\.email.from), key: k),
                                  posts: v.sorted { $0.email.date > $1.email.date })
            }
            .sorted { $0.latest == $1.latest ? $0.name < $1.name : $0.latest > $1.latest }
        }
        static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.posts.map(\.id) == b.posts.map(\.id) }
    }

    var waiting: [Post] = []
    var notes: [Post] = []
    /// Unread mail, oldest first: your to-do list. Unread means you weren't ready to act on it yet.
    var todo: [Post] = []
    var people: [Post] = []
    var organizations: [OrganizationGroup] = []
    var earlier: [Post] = []

    /// `isOrganization`: automated mail, or a list sent as a blind copy.
    static func make(active: [Post], section: (Post) -> FeedSection, isOrganization: (Post) -> Bool,
                     groupKey: ((Post) -> String)? = nil, now: Date) -> HomeDigest {
        var d = HomeDigest()
        var orgPosts: [Post] = []
        for post in active.sorted(by: { $0.email.date > $1.email.date }) {
            let s = section(post)
            if s == .waiting { d.waiting.append(post); continue }
            if post.email.isUnread { d.todo.append(post); continue }
            let recent = now.timeIntervalSince(post.email.date) <= recentWindow
            if s == .notes, recent { d.notes.append(post); continue }
            if !recent { d.earlier.append(post); continue }
            if isOrganization(post) || s != .people {
                orgPosts.append(post)
            } else {
                d.people.append(post)
            }
        }
        d.todo.reverse()
        d.organizations = OrganizationGroup.group(orgPosts, key: groupKey ?? { OrganizationKey.key(for: $0.email.from, overrides: [:]) })
        return d
    }

    /// How long a message has waited, short: "today", "3 days", "2 weeks", "4 months".
    static func age(of date: Date, now: Date) -> String {
        let days = Int(max(0, now.timeIntervalSince(date)) / 86_400)
        switch days {
        case 0: return "today"
        case 1: return "1 day"
        case 2..<14: return "\(days) days"
        case 14..<60: return "\(days / 7) weeks"
        default: return "\(days / 30) months"
        }
    }

    /// The sender's display name, or its domain when the name is only an address.
    static func organizationName(_ person: Person) -> String {
        let name = person.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, !name.contains("@") { return name }
        let domain = person.email.split(separator: "@").last.map(String.init) ?? person.email
        let parts = domain.split(separator: ".")
        return parts.count >= 2 ? String(parts[parts.count - 2]).capitalized : domain
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
        // Out-of-office and other automatic replies are never a person asking something, and never an answer.
        if email.isAutoReply { return TriageAssessment(section: .updates, reason: "Automatic reply") }
        // A delivery phrase plus an automated signal or a shipping sender (a person saying "it was delivered" is not one).
        if !email.isPromotional, DeliveryNotice.isDeliveryNotice(email) { return TriageAssessment(section: .updates, reason: "Delivery update") }
        // A newsletter needs list evidence: Gmail's signals (tab, list headers, bulk precedence, system address) or a
        // list footer in the text. A person's mail that merely mentions a newsletter is not one.
        if post.summary.category == .newsletter, email.isAutomated || ReplySignals.hasListFooter(email.body) { return TriageAssessment(section: .reading, reason: "Newsletter or mailing list") }
        if let why = automatedReason(email) {
            let text = email.subject + "\n" + email.body
            if email.isPromotional { return TriageAssessment(section: .reading, reason: "Gmail filed this under Promotions") }
            if MailKind.isMarketing(text) { return TriageAssessment(section: .reading, reason: "Promotion or marketing mail") }
            if MailKind.isShipping(text) { return TriageAssessment(section: .updates, reason: why + "; shipping or delivery") }
            if MailKind.isReceipt(text) { return TriageAssessment(section: .updates, reason: why + "; a receipt or finished service") }
            // Bulk mail with a list footer ("You are receiving this email because...") is reading, even when it names days,
            // unless it is school, travel or plans mail.
            if email.bulk, ReplySignals.hasListFooter(email.body), ![.school, .travel, .events].contains(post.summary.category) {
                return TriageAssessment(section: .reading, reason: "Newsletter or mailing list")
            }
            let dated = !post.summary.dates.isEmpty || MailKind.mentionsDay(text)
                || [.school, .travel, .events].contains(post.summary.category)
            return TriageAssessment(section: dated ? .dated : .updates, reason: dated ? why + ". Mentions a date" : why)
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
        if email.bulk { return "From a mailing list or automated sender" }
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
                               // Plain asks without a question mark (Sprint 2).
                               "i need the", "remind me", "keep me posted", "let us know", "see if you have",
                               "see if you had", "touch base",
                               // A business asking you to act on its site counts as waiting on you (owner's call, Nov 2).
                               "please log", "log onto", "log on to", "esign", "please complete", "please fill", "please pay"]

    /// Sentences that sound like asks but are courtesy or rhetoric: "Let me know if you have any questions",
    /// "Feel free to call me", "Can you believe this weather".
    private static let courtesy = [#"let (me|us) know if you (have any questions|need anything|need any)"#,
                                   #"let (me|us) know if (there is|there's) anything"#, #"if you have any questions"#,
                                   #"feel free to"#, #"(don't|do not) hesitate"#, #"if anything comes up"#,
                                   #"can you believe"#, #"would you believe"#, #"who knew"#, #"guess what"#,
                                   #"any (additional|further|other) questions"#, #"feel welcome to"#,
                                   #"let (me|us) know if (you need|there's|there is) anything( else)?"#]

    static func isCourtesy(_ sentence: String) -> Bool {
        let lower = normalizeQuotes(sentence).lowercased()
        return courtesy.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    /// Curly quotes and apostrophes to straight ones, so "don’t" matches "don't" in every phrase rule.
    static func normalizeQuotes(_ text: String) -> String {
        var out = text
        for (curly, straight) in [("\u{2019}", "'"), ("\u{2018}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\"")] {
            out = out.replacingOccurrences(of: curly, with: straight)
        }
        return out
    }

    /// True when a "From:" line opens an Outlook-style header block: "Sent:", "Date:", "To:" or "Subject:"
    /// follows within the next three lines.
    private static func opensHeaderBlock(_ lines: [String], at index: Int) -> Bool {
        guard lines[index].hasPrefix("From:") else { return false }
        let following = lines.dropFirst(index + 1).prefix(3)
        return following.contains { line in
            ["Sent:", "Date:", "To:", "Subject:"].contains { line.hasPrefix($0) }
        }
    }

    /// Where the author's own words end: signatures, quoted replies, forwards, reactions.
    private static func endsAuthoredText(_ lines: [String], at index: Int, kept: Int) -> Bool {
        let line = lines[index]
        if line == "--" || line == "-- " || line.hasPrefix("\u{2014}") && line.count < 4 { return true }
        if line.range(of: #"^On .+ wrote:$"#, options: .regularExpression) != nil { return true }
        // Gmail wraps long attributions: "On Mon, Nov 2, 2026 at 3:00 PM Dana <dana@x.example>" then "wrote:".
        if line.hasPrefix("On "), index + 1 < lines.count, lines[index + 1].hasPrefix("wrote:") { return true }
        if line.hasPrefix("-----Original Message-----") || line.hasPrefix("From: ") && kept > 2 { return true }
        // Outlook: a line of underscores, then From / Sent / To / Subject.
        if line.range(of: #"^_{10,}"#, options: .regularExpression) != nil { return true }
        if opensHeaderBlock(lines, at: index) { return true }
        // "Dana reacted to your message:" is followed by the quoted message.
        if line.range(of: #"^.{1,60}\s+reacted (to|with) .*(message|text)"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // A forwarded message is someone else's words (Gmail and Apple Mail markers).
        if line.range(of: #"^-{2,}\s*Forwarded message\s*-{2,}"#, options: .regularExpression) != nil
            || line == "Begin forwarded message:" { return true }
        return false
    }

    /// The author's own words, quotes and signatures removed, links and unsubscribe lines kept.
    /// Summaries use this so a newsletter still reads as one.
    static func authoredBody(_ body: String) -> String {
        authoredLines(body, dropLinks: false)
    }

    private static func authoredLines(_ body: String, dropLinks: Bool) -> String {
        let lines = body.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var kept: [String] = []
        for index in lines.indices {
            let line = lines[index]
            if endsAuthoredText(lines, at: index, kept: kept.count) { break }
            if line.hasPrefix(">") { continue }
            if dropLinks {
                let lower = line.lowercased()
                if lower.contains("unsubscribe") || lower.contains("http://") || lower.contains("https://") { continue }
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    /// The author's own words: no quoted earlier mail, no signature block, no link-heavy footer lines.
    static func authoredText(_ body: String) -> String {
        authoredLines(body, dropLinks: true)
    }

    /// What a summarizer reads: the author's words, or the whole body when they wrote almost nothing
    /// (a bare forward, "FYI").
    static func summaryBody(_ body: String) -> String {
        let own = authoredBody(body)
        return own.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 ? body : own
    }

    /// Phrases that mark machine-sent mail even when the sender address looks personal
    /// (portals, schools, HOAs, booking systems).
    // "Out of office" is not here: AutoReply decides that (a header, a subject, or two phrases), because a person can write
    // "I'll be out of the office Friday, can you cover?" and that is an ask.
    private static let machinePhrases = [
        "do not reply", "do-not-reply", "please don't reply", "please do not respond", "this is an automated",
        "automatically generated", "auto-generated", "this mailbox is not monitored", "unmonitored", "not monitored",
        "you have a new message", "you have received a new", "new private message", "you have a new private",
        "log in to view", "login to view", "sign in to view", "click here to view", "view this message",
        "to view the message", "view it online", "reply above this line", "you are receiving this",
        "you received this email because", "manage your notification", "notification settings",
        "verification code", "security code", "one-time code", "your code is", "passcode",
        "automatic reply", "auto-reply", "autoreply",
        "has been scheduled for", "you are scheduled for",
        "this is a group email", "please reply to sender only",
    ]
    private static let listFooterPhrases = ["unsubscribe", "view this email in your browser", "view in browser", "view it in your browser",
                                            "update preferences", "manage preferences", "you are receiving this", "you received this email because"]

    /// True when the text carries a mailing-list footer ("Unsubscribe", "View this email in your browser").
    static func hasListFooter(_ body: String) -> Bool {
        let lower = normalizeQuotes(body).lowercased()
        return listFooterPhrases.contains { lower.contains($0) }
    }

    /// Calendar auto-responses: "Accepted: Sprint review".
    private static let machineSubjectPrefixes = ["accepted:", "declined:", "tentative:", "new time proposed:", "invitation:"]
    /// Booking systems: "Reply C to confirm", "Reply Y to confirm or N to cancel".
    private static let replyCode = #"\breply [a-z]{1,3} to (confirm|cancel)"#

    static func isMachineText(subject: String, body: String) -> Bool {
        let lower = normalizeQuotes(subject + "\n" + authoredText(body)).lowercased()
        let head = subject.trimmingCharacters(in: .whitespaces).lowercased()
        if machineSubjectPrefixes.contains { head.hasPrefix($0) } { return true }
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
            let lower = normalizeQuotes(sentence).lowercased()
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
        let lower = normalizeQuotes(text).lowercased()
        if asks.contains(where: { lower.contains($0) }) { return true }
        // A question mark counts only when it ends a sentence the author wrote.
        return text.range(of: #"[A-Za-z][^.!?\n]{2,}\?(\s|$)"#, options: .regularExpression) != nil
    }
}
