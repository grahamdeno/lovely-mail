import Foundation

/// Who understands the owner's words: Apple Intelligence on this iPhone, always (owner, Nov 11, 2026: "Lovely must not
/// call Claude or the Grok API"). Anything Apple cannot do that needs the web is a Hand to Grok task.
enum EngineKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case apple
    var id: String { rawValue }
    var name: String { "Apple Intelligence" }
}

struct EngineRequest: Sendable {
    /// Full playbook (examples included; kept for the scorecard and tests).
    var system: String
    /// Short playbook (Apple).
    var compact: String
    /// The email as data, then what the owner said.
    var user: String
}

struct EngineAnswer: Sendable {
    var command: SessionCommand
    var engine: EngineKind
    var inputTokens = 0
    var outputTokens = 0
}

enum EngineError: LocalizedError, Equatable {
    case unavailable
    case badAnswer

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Intelligence is not available on this iPhone right now."
        case .badAnswer: return "The engine's answer did not make sense, so nothing was done."
        }
    }
}

protocol SessionEngine: Sendable {
    var kind: EngineKind { get }
    func interpret(_ request: EngineRequest) async throws -> EngineAnswer
}

/// The cloud engines were removed on Nov 11, 2026. This forgets what they left on the phone: the two API keys in the
/// Keychain and their settings. Runs at launch; harmless when there is nothing to forget.
enum RetiredCloudEngines {
    static let keychainService = "com.grahamdeno.reelmail.engine"
    static let keychainAccounts = ["claude", "grok"]
    static let defaultsKeys = ["lovely.engine.kind", "lovely.engine.compare", "lovely.engine.claudeModel", "lovely.engine.grokModel",
                               "lovely.engine.lastRoute", "lovely.engine.lastPlan", "lovely.engine.usage", "lovely.owner.details",
                               "lovely.handoff.agent"]

    static func forget(defaults: UserDefaults = .standard, keychain: Bool = true) {
        if keychain { keychainAccounts.forEach { KeychainStore(service: keychainService, account: $0).delete() } }
        defaultsKeys.forEach { defaults.removeObject(forKey: $0) }
    }
}

/// Builds the request for one email. Apple only.
enum EngineRouter {
    static func engine() -> SessionEngine { AppleSessionEngine() }

    static func request(for item: SessionItem, said: String, ownerName: String, kids: [KidProfile],
                        examples: [SessionPlaybook.Example]) -> EngineRequest {
        EngineRequest(system: SessionPlaybook.system(ownerName: ownerName, kids: kids, examples: examples),
                      compact: SessionPlaybook.compact(ownerName: ownerName, kids: kids),
                      user: SessionPlaybook.userMessage(item, said: said))
    }
}
