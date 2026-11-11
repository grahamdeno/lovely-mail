import Foundation
import FoundationModels

/// The on-device answer shape. Empty strings mean "none"; the validator decides what is allowed.
@Generable
struct AppleSessionCommand {
    @Guide(description: "Exactly one of: reply, put_away, add_date, later, leave_unread, archive, trash, skip, handoff, search, unclear.")
    var action: String
    @Guide(description: "For put_away, add_date or reply: a drawer name from the list, else empty.")
    var drawer: String
    @Guide(description: "For reply: the full short reply in the owner's voice, else empty.")
    var reply: String
    @Guide(description: "For later: this evening, tomorrow, this weekend or next week, else empty.")
    var later: String
    @Guide(description: "For handoff: the task for an outside agent, else empty.")
    var task: String
    @Guide(description: "One short sentence for the owner: what will happen, or a question if unsure.")
    var say: String
    @Guide(description: "For search: a Gmail search like to:name@example.com newer_than:30d, else empty.")
    var query: String
}

/// Apple Intelligence on the iPhone. Never touches the network. When it is unsure it says so.
struct AppleSessionEngine: SessionEngine {
    var kind: EngineKind { .apple }
    static let maxCharacters = 2_500

    func interpret(_ request: EngineRequest) async throws -> EngineAnswer {
        guard ModelStatus.current.isAvailable else { throw EngineError.unavailable }
        let session = LanguageModelSession(instructions: request.compact)
        let response = try await session.respond(to: String(request.user.prefix(Self.maxCharacters)), generating: AppleSessionCommand.self,
                                                 options: GenerationOptions(temperature: 0.2))
        let c = response.content
        func opt(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        return EngineAnswer(command: SessionCommand(action: c.action.trimmingCharacters(in: .whitespaces).lowercased(),
                                                    drawer: opt(c.drawer), reply: opt(c.reply), later: opt(c.later),
                                                    task: opt(c.task), say: opt(c.say), query: opt(c.query)),
                            engine: .apple)
    }
}
