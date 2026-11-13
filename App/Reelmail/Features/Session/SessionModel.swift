import Foundation
import Observation

/// What happened to each item in a session, for the wrap-up.
enum SessionOutcome: Equatable, Sendable {
    case replied
    case filed(DrawerChoice)
    case archived
    case trashed
    case leftUnread
}

/// The state of one inbox session: the plan, where the owner is, and what happened. The rules are in Session/;
/// this decides which screen comes next. One decision per screen.
@MainActor
@Observable
final class SessionModel {
    enum Phase: Equatable {
        case start
        case item(String)
        case batch
        case reading
        case wrap
    }

    private(set) var plan: SessionPlan
    private(set) var progress: SessionProgress
    private(set) var phase: Phase = .start
    private(set) var outcomes: [String: SessionOutcome] = [:]
    private(set) var datesAdded = 0

    /// Batch screen edits: a different drawer for a row, or a row left out (stays unread).
    var batchDrawers: [String: DrawerChoice] = [:]
    var batchLeftOut: Set<String> = []
    /// Per-row choices other than its category: keep 2 weeks, archive, trash. A row with none is filed.
    var batchFates: [String: BatchFate] = [:]
    /// What he chose for each sender before (address, lowercased): a row starts there, so Lovely learns his habits.
    var rememberedFates: [String: BatchFate] = [:]
    /// Batch rows he marked "Always": the row's choice becomes a Gmail filter for that sender when he taps Do.
    var alwaysRows: Set<String> = []

    /// "Always" makes sense for filing, 2 weeks and Trash (Trash becomes Screen out: future mail skips the inbox).
    static func alwaysAllowed(_ fate: BatchFate) -> Bool { fate == .file || fate == .keepTwoWeeks || fate == .trash }

    /// Lovely suggests "Always" when he picks the same thing for a sender he picked it for last time.
    func suggestsAlways(_ item: SessionItem, reading: Bool = false) -> Bool {
        let fate = batchFate(item, reading: reading)
        guard Self.alwaysAllowed(fate), !item.message.isPerson else { return false }
        return rememberedFates[item.message.fromAddress.lowercased()] == fate
    }

    /// The rows marked Always whose current choice still allows it.
    func alwaysItems(_ items: [SessionItem], reading: Bool = false) -> [SessionItem] {
        items.filter { alwaysRows.contains($0.id) && Self.alwaysAllowed(batchFate($0, reading: reading)) }
    }
    /// Reading screen: rows kept unread.
    var readingKept: Set<String> = []

    /// Older read mail rather than new mail.
    let backlog: Bool

    init(plan: SessionPlan, backlog: Bool = false) {
        self.backlog = backlog
        self.plan = plan
        self.progress = SessionProgress(plan: plan)
    }

    var isEmpty: Bool { plan.count == 0 }

    func start() { advance() }

    /// Start with one group (tapped on the start screen); the rest follow in the usual order afterwards.
    func start(with group: SessionGroup) {
        let open = plan.items.filter(isOpen)
        // One workflow (owner, Nov 12, 2026): every email is a card, whatever its group.
        if let first = open.first(where: { $0.group == group }) { phase = .item(first.id) } else { advance() }
    }

    /// A better plan arrived before the owner started (Apple Intelligence drawer suggestions). Ignored once started.
    func replacePlanBeforeStart(_ newPlan: SessionPlan) {
        guard phase == .start, Set(newPlan.items.map(\.id)) == Set(plan.items.map(\.id)) else { return }
        plan = newPlan
        progress = SessionProgress(plan: newPlan)
    }

    private func isOpen(_ item: SessionItem) -> Bool {
        !progress.handled.contains(item.id) && !progress.leftUnread.contains(item.id)
    }

    /// One workflow (owner, Nov 12, 2026): every email is a card, the ones needing a decision first, then the quick
    /// ones, then newsletters; then anything skipped, then the wrap-up. No batch screens.
    func advance(skipping skippedNow: String? = nil) {
        let open = SessionGroup.allCases.flatMap { g in plan.items.filter { $0.group == g && isOpen($0) } }
        if let next = open.first(where: { !progress.skipped.contains($0.id) }) { phase = .item(next.id); return }
        // Back to skipped ones, but never straight back to the one just skipped: with only it left, Skip looked broken
        // (it reopened the same email). Then the session wraps up and leaves it in the inbox.
        let skipped = open.filter { $0.id != skippedNow }
        if let i = open.firstIndex(where: { $0.id == skippedNow }),
           let after = skipped.first(where: { s in (open.firstIndex { $0.id == s.id } ?? 0) > i }) ?? skipped.first {
            phase = .item(after.id); return
        }
        if let first = skipped.first { phase = .item(first.id); return }
        phase = .wrap
    }

    func item(_ id: String) -> SessionItem? { plan.items.first { $0.id == id } }

    /// The quick items on the current batch page (at most `SessionPlanner.batchPageSize`).
    var batchPage: [SessionItem] {
        Array(plan.items.filter { $0.group == .quick && isOpen($0) }.prefix(SessionPlanner.batchPageSize))
    }

    var readingItems: [SessionItem] { plan.items.filter { $0.group == .reading && isOpen($0) } }

    /// The drawer a batch row will use: the owner's change, else the suggestion.
    func batchDrawer(_ item: SessionItem) -> DrawerChoice? { batchDrawers[item.id] ?? item.drawer?.choice }

    /// Tags for a batch row. If the owner changed the category, only tags that do not depend on it are kept
    /// (type, person, tax year); topics and property belong to the suggested category.
    func batchTags(_ item: SessionItem) -> [MailTag] {
        guard let changed = batchDrawers[item.id], changed != item.drawer?.choice else { return item.tags }
        var tags = item.tags.filter { [.type, .person, .taxes].contains($0.group) }
        if let child = changed.child, !tags.contains(MailTag(group: .person, name: child)) { tags.append(MailTag(group: .person, name: child)) }
        return tags.sorted()
    }

    /// What happens to one row when he taps the button: his choice on this screen, else what he chose for this
    /// sender before, else the suggestion (file in its category; newsletters archive).
    func batchFate(_ item: SessionItem, reading: Bool = false) -> BatchFate {
        if batchLeftOut.contains(item.id) { return .unread }
        if let fate = batchFates[item.id] { return fate }
        if let fate = rememberedFates[item.message.fromAddress.lowercased()], fate != .unread, fate != .block {
            return fate == .file && batchDrawer(item) == nil ? .archive : fate
        }
        return reading || batchDrawer(item) == nil ? .archive : .file
    }

    func setBatchFate(_ fate: BatchFate, for item: SessionItem) {
        batchLeftOut.remove(item.id)
        switch fate {
        case .unread: batchLeftOut.insert(item.id); batchFates[item.id] = nil
        case .file: batchFates[item.id] = nil
        default: batchFates[item.id] = fate
        }
    }

    /// Moves for a page: filed rows with their category and tags, and archived rows (no category).
    func moves(_ items: [SessionItem], reading: Bool = false) -> [SessionMove] {
        items.compactMap { item in
            switch batchFate(item, reading: reading) {
            case .file: return batchDrawer(item).map { SessionMove(messageID: item.id, drawer: $0, tags: batchTags(item)) }
            case .archive: return SessionMove(messageID: item.id, drawer: nil)
            default: return nil
            }
        }
    }
    func ids(_ items: [SessionItem], _ fate: BatchFate, reading: Bool = false) -> [String] {
        items.filter { batchFate($0, reading: reading) == fate }.map(\.id)
    }
    /// Each sender's choice on this page, to remember for next time (leaving one unread is not a habit).
    func fatesToRemember(_ items: [SessionItem], reading: Bool = false) -> [String: BatchFate] {
        var out: [String: BatchFate] = [:]
        for item in items { let f = batchFate(item, reading: reading); if f != .unread, f != .block { out[item.message.fromAddress.lowercased()] = f } }
        return out
    }

    var batchMoves: [SessionMove] { moves(batchPage) }
    var batchKeepTwoWeeksIDs: [String] { ids(batchPage, .keepTwoWeeks) }
    var batchTrashIDs: [String] { ids(batchPage, .trash) }

    var readingMoves: [SessionMove] { moves(readingItems, reading: true) }

    // MARK: Recording what happened

    func record(_ id: String, _ outcome: SessionOutcome) {
        outcomes[id] = outcome
        if outcome == .leftUnread { progress.markLeftUnread(id) } else { progress.markHandled(id) }
    }

    func recordMoves(_ moves: [SessionMove]) {
        for move in moves { record(move.messageID, move.drawer.map(SessionOutcome.filed) ?? .archived) }
    }

    /// After the batch page is confirmed: rows left out stay unread on purpose.
    func finishBatchPage(_ moves: [SessionMove], keptTwoWeeks: [String] = [], trashed: [String] = [], blocked: [String] = []) {
        recordMoves(moves)
        for id in blocked { record(id, .archived) }
        for id in keptTwoWeeks { record(id, .archived) }
        for id in trashed { record(id, .trashed) }
        let handled = Set(moves.map(\.messageID) + keptTwoWeeks + trashed + blocked)
        for item in batchPage where !handled.contains(item.id) { record(item.id, .leftUnread) }
        batchLeftOut.removeAll(); batchDrawers.removeAll(); batchFates.removeAll()
        advance()
    }

    func finishReading(_ moves: [SessionMove], keptTwoWeeks: [String] = [], trashed: [String] = [], blocked: [String] = []) {
        recordMoves(moves)
        for id in blocked { record(id, .archived) }
        for id in keptTwoWeeks { record(id, .archived) }
        for id in trashed { record(id, .trashed) }
        let handled = Set(moves.map(\.messageID) + keptTwoWeeks + trashed + blocked)
        for item in readingItems where !handled.contains(item.id) { record(item.id, .leftUnread) }
        readingKept.removeAll(); batchLeftOut.removeAll(); batchDrawers.removeAll(); batchFates.removeAll()
        advance()
    }

    func skip(_ id: String) { progress.markSkipped(id); advance(skipping: id) }

    /// Undo of a flick up (skip for now): the email is open again and back on screen.
    func returnTo(_ id: String) {
        guard item(id) != nil else { return }
        outcomes[id] = nil
        progress.undo(id)
        phase = .item(id)
    }

    func addedDate() { datesAdded += 1 }

    /// Undo or a Gmail refusal brought these back: they are open again, and the session returns to them if it had finished.
    func reopen(_ ids: [String]) {
        for id in ids { outcomes[id] = nil; progress.undo(id) }
        if phase == .wrap || phase == .start { advance() }
    }

    // MARK: Wrap-up

    /// Emails not yet handled or left unread, the current one included.
    var remaining: Int { plan.items.filter(isOpen).count }
    var replies: Int { outcomes.values.filter { $0 == .replied }.count }
    var filed: Int { outcomes.values.filter { if case .filed = $0 { return true } else { return false } }.count }
    var archived: Int { outcomes.values.filter { $0 == .archived }.count }
    var trashed: Int { outcomes.values.filter { $0 == .trashed }.count }
    var leftUnread: [SessionItem] { plan.items.filter { outcomes[$0.id] == .leftUnread } }

    /// "Money 3 · Kids 2": where things went.
    var drawerSummary: String {
        var counts: [String: Int] = [:]
        for case .filed(let d) in outcomes.values { counts[d.drawer.title, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }
}

extension SessionModel {
    /// The mail is gone (deleted elsewhere, or already handled): count it and move on.
    func drop(_ id: String) { progress.markHandled(id); advance() }
}

/// One batch row's choice.
enum BatchFate: String, Hashable, CaseIterable, Codable, Sendable {
    case file, keepTwoWeeks, archive, trash, unread
    /// Screen out the sender: a Gmail filter sends their mail to Lovely/Screened Out, skipping the inbox, and their
    /// inbox mail goes there now. Nothing is deleted (owner, Nov 10, 2026: block from the batch screens).
    case block

    var title: String {
        switch self {
        case .file: return "File"
        case .keepTwoWeeks: return "2 weeks"
        case .archive: return "Archive"
        case .trash: return "Trash"
        case .unread: return "Unread"
        case .block: return "Block"
        }
    }
}
