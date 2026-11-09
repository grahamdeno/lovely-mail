import Foundation

/// Senders whose mail the owner moved to Trash in a session. Next time, Lovely offers Trash first for that sender;
/// it still waits for his tap, and Gmail keeps Trash for 30 days. Exact address only, never a whole domain,
/// so one company's receipts never pull in its other mail. Saved per account. Pure apart from save/load, so it is tested.
struct TrashMemory: Equatable, Sendable {
    private(set) var addresses: Set<String> = []

    static func key(account: String) -> String { "lovely.session.trashSenders." + account.lowercased() }

    static func load(account: String, defaults: UserDefaults = .standard) -> TrashMemory {
        TrashMemory(addresses: Set(defaults.stringArray(forKey: key(account: account)) ?? []))
    }

    func save(account: String, defaults: UserDefaults = .standard) {
        defaults.set(addresses.sorted(), forKey: Self.key(account: account))
    }

    func suggestsTrash(for address: String) -> Bool {
        addresses.contains(Self.normalized(address))
    }

    mutating func remember(_ address: String) {
        let a = Self.normalized(address)
        guard a.contains("@") else { return }
        addresses.insert(a)
    }

    /// He put mail from this sender away instead: stop offering Trash.
    mutating func forget(_ address: String) {
        addresses.remove(Self.normalized(address))
    }

    static func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// What he chose for each sender on the batch and newsletter screens (file, 2 weeks, archive, trash), by exact address,
/// per account. Rows from that sender start on the same choice next time; he can still change any row.
struct SenderFateMemory: Equatable, Sendable {
    private(set) var fates: [String: BatchFate] = [:]

    static func key(account: String) -> String { "lovely.session.senderFates." + account.lowercased() }

    static func load(account: String, defaults: UserDefaults = .standard) -> SenderFateMemory {
        let raw = defaults.dictionary(forKey: key(account: account)) as? [String: String] ?? [:]
        return SenderFateMemory(fates: raw.compactMapValues(BatchFate.init(rawValue:)))
    }

    func save(account: String, defaults: UserDefaults = .standard) {
        defaults.set(fates.mapValues(\.rawValue), forKey: Self.key(account: account))
    }

    mutating func remember(_ choices: [String: BatchFate]) {
        for (address, fate) in choices where fate != .unread && address.contains("@") {
            fates[TrashMemory.normalized(address)] = fate
        }
    }
}
