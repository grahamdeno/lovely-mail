import Foundation
import FoundationModels

/// A second opinion on the rules for "You said you would" and "Waiting on them".
/// It can only remove an item the rules found, never add one. `nil` means no opinion (model unavailable or failed),
/// and the rules alone decide.
protocol CommitmentVeto: Sendable {
    /// Does this sentence from a mail you sent commit you to a specific thing for the recipient?
    func isCommitment(_ sentence: String) async -> Bool?
    /// Does this mail you sent ask the recipient to answer or do something?
    func asksRecipient(_ body: String) async -> Bool?
}

@Generable
struct CommitmentCheck {
    @Guide(description: "True only if the user commits to doing a specific thing for the recipient later.")
    var isCommitment: Bool
}

@Generable
struct RecipientAskCheck {
    @Guide(description: "True only if the email asks the recipient to answer a question or do something.")
    var asksRecipient: Bool
}

/// Runs on the iPhone with the Foundation Models framework. Never touches the network.
struct AppleIntelligenceVeto: CommitmentVeto {
    static let maxCharacters = 1_500

    private static let commitmentInstructions = """
    The sentence is from an email the user sent. Answer true only if the user commits to doing a specific thing \
    for the recipient later. Answer false for pleasantries, plans about where the user will be, offers that depend \
    on the recipient, and anything already done.
    """
    private static let askInstructions = """
    The text is an email the user sent. Answer true only if it asks the recipient to answer a question or do \
    something. Answer false for thank-you notes, announcements, and mail that only shares information.
    """

    func isCommitment(_ sentence: String) async -> Bool? {
        guard ModelStatus.current.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: Self.commitmentInstructions)
        let response = try? await session.respond(to: String(sentence.prefix(Self.maxCharacters)), generating: CommitmentCheck.self,
                                                  options: GenerationOptions(temperature: 0))
        return response?.content.isCommitment
    }

    func asksRecipient(_ body: String) async -> Bool? {
        guard ModelStatus.current.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: Self.askInstructions)
        let response = try? await session.respond(to: String(ReplySignals.authoredText(body).prefix(Self.maxCharacters)),
                                                  generating: RecipientAskCheck.self, options: GenerationOptions(temperature: 0))
        return response?.content.asksRecipient
    }
}

/// Remembers verdicts so each message is checked once. Keys: "commit-<id>" and "ask-<id>".
struct VerdictCache: Codable, Equatable {
    var verdicts: [String: Bool] = [:]
    static func commitKey(_ id: String) -> String { "commit-" + id }
    static func askKey(_ id: String) -> String { "ask-" + id }
}
