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
    }

    private var state = State()
    private let defaults: UserDefaults
    private let key: String
    private(set) var persistenceError: String?

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
            return true
        } catch {
            persistenceError = "Routing preferences could not be encoded. No decision was changed."
            return false
        }
    }

    private static func normalize(_ sender: String) -> String {
        sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
