import Foundation

/// Which engine understands the owner's words. Apple only is the default and keeps everything on the phone.
enum EngineKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case apple, claude, grok
    var id: String { rawValue }
    var name: String {
        switch self {
        case .apple: return "Apple only"
        case .claude: return "Claude"
        case .grok: return "Grok"
        }
    }
    var isCloud: Bool { self != .apple }
}

struct EngineRequest: Sendable {
    /// Full playbook (Claude, Grok).
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
    case noKey(EngineKind)
    case http(Int, String)
    case badAnswer
    case notForCloud

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Intelligence is not available on this iPhone right now."
        case .noKey(let k): return "Add your \(k.name) key in Settings, Conversation engine."
        case .http(let code, let message): return "The engine answered \(code). \(message)"
        case .badAnswer: return "The engine's answer did not make sense, so nothing was done."
        case .notForCloud: return "Health mail stays on this iPhone, so Apple handled it."
        }
    }
}

protocol SessionEngine: Sendable {
    var kind: EngineKind { get }
    func interpret(_ request: EngineRequest) async throws -> EngineAnswer
}

typealias EngineTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Settings for the conversation engine. Keys live in the Keychain (this device only), never in UserDefaults.
struct EngineSettings {
    static let engineKey = "lovely.engine.kind"
    static let compareKey = "lovely.engine.compare"
    static let claudeModelKey = "lovely.engine.claudeModel"
    static let grokModelKey = "lovely.engine.grokModel"
    static let defaultClaudeModel = "claude-sonnet-5-5"
    static let defaultGrokModel = "grok-4.6"

    var defaults: UserDefaults = .standard

    var engine: EngineKind {
        get { EngineKind(rawValue: defaults.string(forKey: Self.engineKey) ?? "") ?? .apple }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.engineKey) }
    }
    var compare: Bool {
        get { defaults.bool(forKey: Self.compareKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.compareKey) }
    }
    var claudeModel: String {
        get { nonEmpty(defaults.string(forKey: Self.claudeModelKey)) ?? Self.defaultClaudeModel }
        nonmutating set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Self.claudeModelKey) }
    }
    var grokModel: String {
        get { nonEmpty(defaults.string(forKey: Self.grokModelKey)) ?? Self.defaultGrokModel }
        nonmutating set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Self.grokModelKey) }
    }
    private func nonEmpty(_ s: String?) -> String? { (s?.isEmpty ?? true) ? nil : s }

    static func keychain(_ kind: EngineKind) -> KeychainStore {
        KeychainStore(service: "com.grahamdeno.reelmail.engine", account: kind.rawValue)
    }
    static func key(_ kind: EngineKind) -> String? {
        keychain(kind).load().flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
    }
    static func setKey(_ value: String, for kind: EngineKind) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { keychain(kind).delete() } else { keychain(kind).save(Data(trimmed.utf8)) }
    }
    static func hasKey(_ kind: EngineKind) -> Bool { kind == .apple || key(kind) != nil }
}

/// Which engine answered the last ask in a session, and why Apple did when a cloud engine is chosen. Shown in
/// Settings > AI so a wrong label can be traced. On this phone only; no mail text.
enum EngineRoute {
    static let key = "lovely.engine.lastRoute"
    static func record(_ kind: EngineKind, reason: String?, at date: Date = Date(), defaults: UserDefaults = .standard) {
        let time = date.formatted(date: .abbreviated, time: .shortened)
        defaults.set("\(kind.name) answered, \(time)" + (reason.map { ". \($0)" } ?? ""), forKey: key)
    }
    static func last(defaults: UserDefaults = .standard) -> String? {
        guard let line = defaults.string(forKey: key) else { return nil }
        return line + (defaults.string(forKey: planKey).map { "\n" + $0 } ?? "")
    }

    static let planKey = "lovely.engine.lastPlan"
    /// What Lovely saw when it chose the engine, the moment it chose (Graham saw Apple answer with Claude selected).
    static func recordPlan(_ kinds: [EngineKind], settings: EngineSettings, item: SessionItem, defaults: UserDefaults = .standard) {
        let raw = settings.defaults.string(forKey: EngineSettings.engineKey) ?? "none"
        let line = "Chose \(kinds.map(\.name).joined(separator: " + ")). Setting: \(raw), key: \(EngineSettings.hasKey(settings.engine) ? "yes" : "no"), health: \(item.message.isHealth ? "yes" : "no")"
        defaults.set(line, forKey: planKey)
    }

    /// Why the plan is Apple even though the owner may have chosen a cloud engine. Nil when the chosen engine is used.
    static func appleReason(for item: SessionItem, settings: EngineSettings = EngineSettings()) -> String? {
        let chosen = settings.engine
        guard chosen.isCloud else { return "Apple only is selected" }
        if !EngineRouter.allowsCloud(item) { return "Health mail stays on this iPhone" }
        if !EngineSettings.hasKey(chosen) { return "No \(chosen.name) key could be read from the Keychain" }
        return nil
    }
}

/// Calls and picks per engine, per week, on this phone. Counts only; no mail text.
struct EngineUsage {
    struct Week: Codable, Equatable {
        var calls: [String: Int] = [:]
        var inputTokens: [String: Int] = [:]
        var outputTokens: [String: Int] = [:]
        var picks: [String: Int] = [:]
    }
    static let key = "lovely.engine.usage"
    var defaults: UserDefaults = .standard

    static func weekKey(_ date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }

    private var all: [String: Week] {
        guard let d = defaults.data(forKey: Self.key), let w = try? JSONDecoder().decode([String: Week].self, from: d) else { return [:] }
        return w
    }
    private func save(_ weeks: [String: Week]) {
        let recent = weeks.keys.sorted().suffix(8)
        let kept = weeks.filter { recent.contains($0.key) }
        if let d = try? JSONEncoder().encode(kept) { defaults.set(d, forKey: Self.key) }
    }

    func thisWeek(now: Date = Date()) -> Week { all[Self.weekKey(now)] ?? Week() }

    func recordCall(_ answer: EngineAnswer, now: Date = Date()) {
        var weeks = all; let k = Self.weekKey(now); var w = weeks[k] ?? Week()
        let e = answer.engine.rawValue
        w.calls[e, default: 0] += 1
        w.inputTokens[e, default: 0] += answer.inputTokens
        w.outputTokens[e, default: 0] += answer.outputTokens
        weeks[k] = w; save(weeks)
    }

    func recordPick(_ engine: EngineKind, now: Date = Date()) {
        var weeks = all; let k = Self.weekKey(now); var w = weeks[k] ?? Week()
        w.picks[engine.rawValue, default: 0] += 1
        weeks[k] = w; save(weeks)
    }

    /// Rough US dollars, per million tokens in and out. Shown as an estimate only.
    static let prices: [EngineKind: (input: Double, output: Double)] = [.claude: (3, 15), .grok: (2, 6), .apple: (0, 0)]

    static func estimatedCost(_ week: Week, _ engine: EngineKind) -> Double {
        guard let p = prices[engine] else { return 0 }
        let i = Double(week.inputTokens[engine.rawValue] ?? 0), o = Double(week.outputTokens[engine.rawValue] ?? 0)
        return (i * p.input + o * p.output) / 1_000_000
    }
}

/// Picks the engines for one request and keeps the privacy rules in one place.
enum EngineRouter {
    /// Health mail never goes to a cloud engine, whatever the setting.
    static func allowsCloud(_ item: SessionItem) -> Bool { !item.message.isHealth }

    static func engine(_ kind: EngineKind, settings: EngineSettings = EngineSettings(),
                       transport: @escaping EngineTransport = { try await URLSession.shared.data(for: $0) }) -> SessionEngine {
        switch kind {
        case .apple: return AppleSessionEngine()
        case .claude: return AnthropicEngine(model: settings.claudeModel, key: EngineSettings.key(.claude), transport: transport)
        case .grok: return XAIEngine(model: settings.grokModel, key: EngineSettings.key(.grok), transport: transport)
        }
    }

    /// The engines to ask for this item: the chosen one, plus the other cloud engine in compare mode.
    static func plan(for item: SessionItem, settings: EngineSettings = EngineSettings()) -> [EngineKind] {
        let chosen = settings.engine
        guard chosen.isCloud, allowsCloud(item), EngineSettings.hasKey(chosen) else { return [.apple] }
        guard settings.compare else { return [chosen] }
        let other: EngineKind = chosen == .claude ? .grok : .claude
        return EngineSettings.hasKey(other) ? [chosen, other] : [chosen]
    }

    static func request(for item: SessionItem, said: String, ownerName: String, kids: [KidProfile],
                        examples: [SessionPlaybook.Example]) -> EngineRequest {
        EngineRequest(system: SessionPlaybook.system(ownerName: ownerName, kids: kids, examples: examples),
                      compact: SessionPlaybook.compact(ownerName: ownerName, kids: kids),
                      user: SessionPlaybook.userMessage(item, said: said))
    }
}
