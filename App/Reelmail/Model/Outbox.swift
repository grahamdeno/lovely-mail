import Foundation

/// Gmail changes the owner tapped that have not reached Gmail yet. Each is written to the phone the moment he taps and
/// removed once Gmail confirms it, so closing Lovely, a crash or losing signal never silently drops a change.
/// Trash and mark-read finish by themselves the next time Lovely opens; filing and archiving need a fresh tap
/// (an approval lasts 15 minutes), so Home offers "Finish N changes from earlier" or "Put them back".
struct OutboxOp: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case trash, markRead, file, archive }
    var id = UUID().uuidString
    var kind: Kind
    var messageID: String
    /// Lovely/ label names, for file.
    var labels: [String] = []
    /// The action this belongs to (one tap can make many).
    var batch: String
    var created = Date()

    /// Trash and mark-read need no approval; they finish by themselves.
    var finishesByItself: Bool { kind == .trash || kind == .markRead }
}

struct Outbox {
    var account: String
    var defaults: UserDefaults = .standard
    private var key: String { "lovely.outbox." + account.lowercased() }

    var ops: [OutboxOp] {
        guard let d = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([OutboxOp].self, from: d)) ?? []
    }

    private func write(_ ops: [OutboxOp]) { defaults.set(try? JSONEncoder().encode(ops), forKey: key) }

    func add(_ new: [OutboxOp]) { write(ops + new) }
    func remove(id: String) { write(ops.filter { $0.id != id }) }
    func remove(batch: String) { write(ops.filter { $0.batch != batch }) }
    func remove(messageID: String, kind: OutboxOp.Kind) { write(ops.filter { !($0.messageID == messageID && $0.kind == kind) }) }
    func clear() { write([]) }

    static func preview(_ ops: [OutboxOp]) -> ActionPreview {
        let files = ops.filter { $0.kind == .file }.count
        let archives = ops.filter { $0.kind == .archive }.count
        var lines: [String] = []
        if files > 0 { lines.append("Files \(files) under their Lovely labels, marks them read and takes them out of your inbox.") }
        if archives > 0 { lines.append("Marks \(archives) read and takes them out of your inbox.") }
        lines.append("These are changes you made earlier that did not reach Gmail. Nothing is deleted.")
        return ActionPreview(kind: .label, title: "Finish \(ops.count) change\(ops.count == 1 ? "" : "s") from earlier", lines: lines)
    }
}

/// When this run of Lovely started. Changes from before it are "from earlier"; newer ones may still be in flight.
enum AppLaunch { static let at = Date() }
