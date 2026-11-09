import Foundation
import Observation

/// What happened to each item in a session, for the wrap-up.
enum SessionOutcome: Equatable, Sendable {
    case replied
    case filed(DrawerChoice)
    case archived
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

    /// A better plan arrived before the owner started (Apple Intelligence drawer suggestions). Ignored once started.
    func replacePlanBeforeStart(_ newPlan: SessionPlan) {
        guard phase == .start, Set(newPlan.items.map(\.id)) == Set(plan.items.map(\.id)) else { return }
        plan = newPlan
        progress = SessionProgress(plan: newPlan)
    }

    private func isOpen(_ item: SessionItem) -> Bool {
        !progress.handled.contains(item.id) && !progress.leftUnread.contains(item.id)
    }

    /// One at a time first, then the quick batch, then reading, then anything skipped, then the wrap-up.
    func advance() {
        let open = plan.items.filter(isOpen)
        if let next = open.first(where: { $0.group == .oneAtATime && !progress.skipped.contains($0.id) }) { phase = .item(next.id); return }
        if open.contains(where: { $0.group == .quick }) { phase = .batch; return }
        if open.contains(where: { $0.group == .reading }) { phase = .reading; return }
        if let skipped = open.first(where: { $0.group == .oneAtATime }) { phase = .item(skipped.id); return }
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

    /// Moves for the batch page: rows not left out, each with its category and tags.
    var batchMoves: [SessionMove] {
        batchPage.filter { !batchLeftOut.contains($0.id) }.compactMap { item in
            batchDrawer(item).map { SessionMove(messageID: item.id, drawer: $0, tags: batchTags(item)) }
        }
    }

    var readingMoves: [SessionMove] {
        readingItems.filter { !readingKept.contains($0.id) }.map { SessionMove(messageID: $0.id, drawer: nil) }
    }

    // MARK: Recording what happened

    func record(_ id: String, _ outcome: SessionOutcome) {
        outcomes[id] = outcome
        if outcome == .leftUnread { progress.markLeftUnread(id) } else { progress.markHandled(id) }
    }

    func recordMoves(_ moves: [SessionMove]) {
        for move in moves { record(move.messageID, move.drawer.map(SessionOutcome.filed) ?? .archived) }
    }

    /// After the batch page is confirmed: rows left out stay unread on purpose.
    func finishBatchPage(_ moves: [SessionMove]) {
        recordMoves(moves)
        let moved = Set(moves.map(\.messageID))
        for item in batchPage where !moved.contains(item.id) { record(item.id, .leftUnread) }
        batchLeftOut.removeAll(); batchDrawers.removeAll()
        advance()
    }

    func finishReading(_ moves: [SessionMove]) {
        recordMoves(moves)
        let moved = Set(moves.map(\.messageID))
        for item in readingItems where !moved.contains(item.id) { record(item.id, .leftUnread) }
        readingKept.removeAll()
        advance()
    }

    func skip(_ id: String) { progress.markSkipped(id); advance() }

    func addedDate() { datesAdded += 1 }

    /// Undo or a Gmail refusal brought these back: they are open again, and the session returns to them if it had finished.
    func reopen(_ ids: [String]) {
        for id in ids { outcomes[id] = nil; progress.undo(id) }
        if phase == .wrap || phase == .start { advance() }
    }

    // MARK: Wrap-up

    var replies: Int { outcomes.values.filter { $0 == .replied }.count }
    var filed: Int { outcomes.values.filter { if case .filed = $0 { return true } else { return false } }.count }
    var archived: Int { outcomes.values.filter { $0 == .archived }.count }
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
