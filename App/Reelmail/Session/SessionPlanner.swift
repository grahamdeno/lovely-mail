import Foundation

/// One unread message as the session sees it. Built from a Post and its triage by `init(post:...)`,
/// or directly in tests. Pure value.
struct SessionMessage: Identifiable, Hashable, Sendable {
    var id: String
    var threadId: String
    var fromName: String
    var fromAddress: String
    var subject: String
    var date: Date
    /// The author's own words: quotes, signatures and forward headers removed.
    var text: String
    var section: FeedSection
    var category: PostCategory
    /// A real person wrote it (not automated, not you).
    var isPerson: Bool
    /// The sentence that asks you something, when triage found one.
    var ask: String?
    var isHealth: Bool
    /// Nobody you have written to, accepted or heard from before.
    var isFirstTimeSender: Bool
    /// Asks for money, a signature or an action on a website, or reports a payment problem.
    var asksForAction: Bool
    var hasDates: Bool
}

enum SessionGroup: Int, CaseIterable, Sendable, Comparable {
    /// Each item gets its own turn.
    case oneAtATime
    /// Routine items confirmed together as one list.
    case quick
    /// Newsletters, one question at the end.
    case reading

    static func < (a: SessionGroup, b: SessionGroup) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .oneAtATime: return "Need a decision from you"
        case .quick: return "Quick: file and done"
        case .reading: return "Newsletters and notices"
        }
    }
}

/// What the session proposes for an item. The owner can always choose something else.
enum SessionSuggestion: Hashable, Sendable {
    /// Someone is waiting on an answer.
    case reply
    /// Read, file in the drawer, out of the inbox.
    case putAway(DrawerChoice)
    /// Add its dates to the calendar, then put it away.
    case addDatesThenPutAway(DrawerChoice)
    /// Read and out of the inbox, no drawer (skimmed newsletters).
    case archive
    /// Needs the owner's judgment; no default.
    case decide
}

struct SessionItem: Identifiable, Hashable, Sendable {
    var message: SessionMessage
    var group: SessionGroup
    var suggestion: SessionSuggestion
    var drawer: DrawerGuess?
    /// Why it is not in the batch, when it could have been ("Asks you to pay").
    var heldBecause: String?
    var id: String { message.id }
}

/// An open "I'll..." from your sent mail, carried into the session start.
struct CarriedPromise: Hashable, Sendable {
    var id: String
    var recipient: String
    var text: String
    var sent: Date
}

struct SessionPlan: Sendable {
    var items: [SessionItem]
    var carried: [CarriedPromise]

    var oneAtATime: [SessionItem] { items.filter { $0.group == .oneAtATime } }
    var quick: [SessionItem] { items.filter { $0.group == .quick } }
    var reading: [SessionItem] { items.filter { $0.group == .reading } }
    var count: Int { items.count }

    /// About 40 seconds for each decision, 6 for each batch row, rounded up to whole minutes.
    var estimatedMinutes: Int {
        guard !items.isEmpty else { return 0 }
        let seconds = oneAtATime.count * 40 + (quick.count + reading.count) * 6
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }
}

/// Builds a session from unread mail. Pure: same input, same plan.
enum SessionPlanner {
    /// Above this, quick items are split into pages so one confirm never covers a long list.
    static let batchPageSize = 10

    /// `backlog`: read mail still in the inbox. It was already dealt with once, so mail from people and notes to self
    /// may go in a batch; everything else in the never-in-a-batch list still gets its own turn.
    static func plan(_ messages: [SessionMessage], memory: DrawerMemory, kids: [KidProfile],
                     promises: [CarriedPromise] = [], modelGuesses: [String: DrawerGuess] = [:], backlog: Bool = false) -> SessionPlan {
        let items = messages.map { item(for: $0, memory: memory, kids: kids, modelGuess: modelGuesses[$0.id], backlog: backlog) }
        return SessionPlan(items: items.sorted(by: order), carried: promises.sorted { $0.sent < $1.sent })
    }

    /// The drawer for a message: memory, then rules, then a model guess.
    static func drawer(for m: SessionMessage, memory: DrawerMemory, kids: [KidProfile], modelGuess: DrawerGuess? = nil) -> DrawerGuess? {
        if let remembered = memory.recall(m.fromAddress) {
            return DrawerGuess(choice: remembered, confidence: .remembered, reason: "You filed \(m.fromName) in \(remembered.title) before")
        }
        let input = DrawerGuesser.Input(fromAddress: m.fromAddress, fromName: m.fromName, subject: m.subject,
                                        text: m.text, category: m.category, isPerson: m.isPerson)
        return DrawerGuesser.guess(input, kids: kids) ?? modelGuess
    }

    static func item(for m: SessionMessage, memory: DrawerMemory, kids: [KidProfile], modelGuess: DrawerGuess? = nil, backlog: Bool = false) -> SessionItem {
        let guess = drawer(for: m, memory: memory, kids: kids, modelGuess: modelGuess)

        // Reading: newsletters and promotions, archived without a drawer unless the owner says otherwise.
        // Health mail and anything asking for action never hide in Reading.
        if m.section == .reading && !m.isHealth && !m.asksForAction && !m.isPerson {
            return SessionItem(message: m, group: .reading, suggestion: .archive, drawer: guess, heldBecause: nil)
        }

        if let held = holdReason(m, guess: guess, backlog: backlog) {
            let suggestion: SessionSuggestion
            if m.section == .waiting { suggestion = .reply }
            else if m.isPerson || m.asksForAction || m.isHealth || m.isFirstTimeSender { suggestion = .decide }
            else if let g = guess { suggestion = m.hasDates ? .addDatesThenPutAway(g.choice) : .putAway(g.choice) }
            else { suggestion = .decide }
            return SessionItem(message: m, group: .oneAtATime, suggestion: suggestion, drawer: guess, heldBecause: held)
        }

        // Batchable: a confident drawer is guaranteed by holdReason.
        let choice = guess!.choice
        return SessionItem(message: m, group: .quick,
                           suggestion: m.hasDates ? .addDatesThenPutAway(choice) : .putAway(choice),
                           drawer: guess, heldBecause: nil)
    }

    /// Why an item must get its own turn, or nil when it may go in a batch.
    /// Order matters only for the reason shown; any one of these holds it back.
    static func holdReason(_ m: SessionMessage, guess: DrawerGuess?, backlog: Bool = false) -> String? {
        if m.section == .waiting { return m.ask.map { "Asks: \($0)" } ?? "Waiting on your answer" }
        if HandoffPrompt.isReport(subject: m.subject) { return "A report from your agent" }
        if m.isHealth { return "Health mail" }
        if m.asksForAction { return "Asks you to pay, sign or act" }
        if m.section == .notes, !backlog { return "A note you sent yourself" }
        if m.isPerson, !backlog { return "From \(m.fromName)" }
        if m.isFirstTimeSender { return "First mail from this sender" }
        guard let guess else { return "Not sure where this goes" }
        if guess.confidence < .rule { return "Not sure where this goes" }
        return nil
    }

    /// One at a time first (waiting, then action asks, then people, then the rest), then quick, then reading.
    /// Oldest first inside each, because unread is a to-do list and the oldest has waited longest.
    static func order(_ a: SessionItem, _ b: SessionItem) -> Bool {
        if a.group != b.group { return a.group < b.group }
        if a.group == .oneAtATime {
            let pa = priority(a.message), pb = priority(b.message)
            if pa != pb { return pa < pb }
        }
        if a.message.date != b.message.date { return a.message.date < b.message.date }
        return a.id < b.id
    }

    static func priority(_ m: SessionMessage) -> Int {
        if m.section == .waiting { return 0 }
        if m.asksForAction { return 1 }
        if m.isPerson || m.section == .notes { return 2 }
        return 3
    }

    /// Quick items in pages for one confirm each.
    static func batches(_ plan: SessionPlan) -> [[SessionItem]] {
        let quick = plan.quick
        return stride(from: 0, to: quick.count, by: batchPageSize).map { Array(quick[$0 ..< min($0 + batchPageSize, quick.count)]) }
    }
}

/// Where the owner is in a session. Pure value.
struct SessionProgress: Equatable, Sendable {
    var total: Int
    private(set) var handled: Set<String> = []
    private(set) var leftUnread: Set<String> = []
    private(set) var skipped: Set<String> = []

    init(plan: SessionPlan) { total = plan.count }

    mutating func markHandled(_ id: String) { handled.insert(id); leftUnread.remove(id); skipped.remove(id) }
    mutating func markLeftUnread(_ id: String) { leftUnread.insert(id); handled.remove(id); skipped.remove(id) }
    mutating func markSkipped(_ id: String) { skipped.insert(id) }
    mutating func undo(_ id: String) { handled.remove(id); leftUnread.remove(id); skipped.remove(id) }

    /// Left unread on purpose counts as dealt with; skipped does not.
    var dealtWith: Int { handled.count + leftUnread.count }
    var isDone: Bool { total > 0 && dealtWith >= total }
    var fraction: Double { total == 0 ? 0 : min(1, Double(dealtWith) / Double(total)) }

    /// The next item still open, in plan order, skipped items last.
    func next(in plan: SessionPlan) -> SessionItem? {
        let open = plan.items.filter { !handled.contains($0.id) && !leftUnread.contains($0.id) }
        return open.first { !skipped.contains($0.id) } ?? open.first
    }
}

// MARK: From the app's own model

extension SessionMessage {
    static let actionPhrases = ["esign", "e-sign", "sign your", "signature required", "please sign", "please pay",
                                "pay now", "payment due", "action required", "please complete", "please fill",
                                "complete your", "verify your", "please log in", "please log on"]
    // Not "log in to": statements say "log in to view your statement", which is routine filing.

    /// Words that mean the bill pays itself, so "payment due" is a date, not a task.
    static let autopayPhrases = ["autopay", "auto pay", "auto-pay", "automatic payment", "will be automatically", "scheduled payment"]

    /// Money, a signature or an action on a website, or a payment problem.
    static func detectsAction(subject: String, text: String) -> Bool {
        if InsightParsers.hasPaymentProblem(subject: subject, text: text) { return true }
        let lowered = (subject + "\n" + text).lowercased()
        let autopay = autopayPhrases.contains { lowered.contains($0) }
        return actionPhrases.contains { phrase in
            guard lowered.contains(phrase) else { return false }
            return !(autopay && (phrase == "payment due" || phrase == "please pay" || phrase == "pay now"))
        }
    }

    init(post: Post, assessment: TriageAssessment, isFirstTimeSender: Bool) {
        let e = post.email
        let authored = ReplySignals.authoredText(e.body)
        self.init(
            id: e.id, threadId: e.threadId, fromName: e.from.name, fromAddress: e.from.email,
            subject: e.subject, date: e.date, text: authored,
            section: assessment.section, category: post.summary.category,
            isPerson: !e.isAutomated && !e.isFromMe && assessment.section != .notes,
            ask: assessment.ask,
            isHealth: HealthMail.isHealth(address: e.from.email, name: e.from.name, subject: e.subject),
            isFirstTimeSender: isFirstTimeSender,
            asksForAction: Self.detectsAction(subject: e.subject, text: authored),
            hasDates: !MailDates.extract(e, now: Date()).isEmpty)
    }
}

extension CarriedPromise {
    init(_ item: PromiseRules.Item) {
        self.init(id: item.id, recipient: item.recipient, text: item.text, sent: item.email.date)
    }
}
