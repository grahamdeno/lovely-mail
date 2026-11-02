import Foundation
import Observation

enum LocalMailDestination: String, Codable {
    case inbox, reading, filtered
}

struct LocalTriageDecision: Equatable {
    let destination: LocalMailDestination
    let reason: String
}

/// Explicit user rules only. No Gmail mutations or learned classification.
/// The caller must supply a stable account ID; demo and each real account need separate IDs.
/// Persists routing metadata in local preferences, not email bodies or credentials.
@MainActor
@Observable
final class LocalTriageRules {
    private struct State: Codable {
        var messages: [String: LocalMailDestination] = [:]
        var senders: [String: LocalMailDestination] = [:]
        /// "Not waiting on me" corrections. Added after v1; older saved state decodes with these empty.
        var notWaitingMessages: Set<String> = []
        var notWaitingSenders: Set<String> = []
        /// Your other addresses, declared by you. Mail from them is "Notes to self". Never inferred from names.
        var otherAddresses: Set<String> = []

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            messages = try c.decodeIfPresent([String: LocalMailDestination].self, forKey: .messages) ?? [:]
            senders = try c.decodeIfPresent([String: LocalMailDestination].self, forKey: .senders) ?? [:]
            notWaitingMessages = try c.decodeIfPresent(Set<String>.self, forKey: .notWaitingMessages) ?? []
            notWaitingSenders = try c.decodeIfPresent(Set<String>.self, forKey: .notWaitingSenders) ?? []
            otherAddresses = try c.decodeIfPresent(Set<String>.self, forKey: .otherAddresses) ?? []
        }
    }

    private var state = State()
    private let defaults: UserDefaults
    private let key: String
    private(set) var persistenceError: String?
    /// Bumped on every saved change so derived feed data knows to rebuild.
    private(set) var revision = 0

    init(accountID: String, defaults: UserDefaults = .standard) {
        precondition(!accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.defaults = defaults
        key = "reelmail.triage.v1." + accountID
        if let data = defaults.data(forKey: key) {
            do { state = try JSONDecoder().decode(State.self, from: data) }
            catch { persistenceError = "Saved routing preferences could not be read. They have not been overwritten." }
        }
    }

    func decision(messageID: String, sender: String) -> LocalTriageDecision {
        if let route = state.messages[messageID] {
            return LocalTriageDecision(destination: route, reason: "Your decision for this message")
        }
        if let route = state.senders[Self.normalize(sender)] {
            return LocalTriageDecision(destination: route, reason: "Your saved rule for this sender")
        }
        return LocalTriageDecision(destination: .inbox, reason: "No saved rule; kept visible")
    }

    /// True when you said this message, or anything from this sender, is not waiting on you.
    func isNotWaiting(messageID: String, sender: String) -> Bool {
        state.notWaitingMessages.contains(messageID) || state.notWaitingSenders.contains(Self.normalize(sender))
    }

    var notWaitingSenderCount: Int { state.notWaitingSenders.count }

    /// Addresses you said are yours (besides the signed-in account).
    var otherAddresses: [String] { state.otherAddresses.sorted() }

    @discardableResult
    @discardableResult
    func setOtherAddress(_ address: String, _ value: Bool) -> Bool {
        let key = Self.normalize(address)
        guard Self.looksLikeAddress(key) else { return false }
        var next = state
        if value { next.otherAddresses.insert(key) } else { next.otherAddresses.remove(key) }
        return save(next)
    }

    @discardableResult
    func setNotWaiting(messageID: String, _ value: Bool) -> Bool {
        guard !messageID.isEmpty else { return false }
        var next = state
        if value { next.notWaitingMessages.insert(messageID) } else { next.notWaitingMessages.remove(messageID) }
        return save(next)
    }

    @discardableResult
    func setNotWaiting(sender: String, _ value: Bool) -> Bool {
        let key = Self.normalize(sender)
        guard !key.isEmpty else { return false }
        var next = state
        if value { next.notWaitingSenders.insert(key) } else { next.notWaitingSenders.remove(key) }
        return save(next)
    }

    @discardableResult
    func setMessage(_ id: String, destination: LocalMailDestination?) -> Bool {
        guard !id.isEmpty else { return false }
        var next = state
        next.messages[id] = destination
        return save(next)
    }

    @discardableResult
    func setSender(_ address: String, destination: LocalMailDestination?) -> Bool {
        let sender = Self.normalize(address)
        guard !sender.isEmpty else { return false }
        var next = state
        next.senders[sender] = destination
        return save(next)
    }

    private func save(_ next: State) -> Bool {
        guard persistenceError == nil else { return false }
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: key)
            state = next
            revision += 1
            return true
        } catch {
            persistenceError = "Routing preferences could not be encoded. No decision was changed."
            return false
        }
    }

    /// Something before and after one "@", and a dot in the domain.
    static func looksLikeAddress(_ value: String) -> Bool {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
            && !value.contains(" ")
    }

    private static func normalize(_ sender: String) -> String {
        sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
