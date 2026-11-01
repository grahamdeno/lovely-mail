import Foundation
import FoundationModels

/// Whether the on-device Apple Intelligence model can run right now.
enum ModelStatus: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown

    static var current: ModelStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unknown
            }
        }
    }

    var isAvailable: Bool { self == .available }

    var title: String {
        switch self {
        case .available: return "Apple Intelligence ready"
        case .deviceNotEligible: return "This device can't run Apple Intelligence"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off"
        case .modelNotReady: return "Model is still downloading"
        case .unknown: return "Model unavailable"
        }
    }

    var detail: String {
        switch self {
        case .available: return "Summaries run on this iPhone. Nothing is sent anywhere."
        case .deviceNotEligible: return "Needs an iPhone 15 Pro or newer. Using the fallback summarizer."
        case .appleIntelligenceNotEnabled: return "Turn it on in Settings › Apple Intelligence & Siri. Using the fallback for now."
        case .modelNotReady: return "Try again in a few minutes. Using the fallback for now."
        case .unknown: return "Using the fallback summarizer."
        }
    }
}

/// Structured output the on-device model fills in for one email.
@Generable
struct PostSummary {
    @Guide(description: "A short, plain headline for the email, at most 8 words. No emoji, no clickbait.")
    var headline: String

    @Guide(description: "One or two plain sentences saying what the email is about and what, if anything, the reader should do. At most 25 words.")
    var blurb: String

    @Guide(description: "True only if a real person is asking the reader a question or for a decision or confirmation. False for receipts, newsletters, notifications and automated mail.")
    var needsReply: Bool

    @Guide(description: "The best single category.", .anyOf(["people", "school", "work", "money", "travel", "events", "newsletter", "updates"]))
    var category: String

    @Guide(description: "2 to 4 generic words for a calm stock photo that fits the email, for example 'park trail' or 'coffee cup'. Never names or personal details.")
    var imageQuery: String

    @Guide(description: "True if the email contains passwords, verification codes, account numbers, medical or legal details.")
    var sensitive: Bool

    @Guide(description: "Dates mentioned in the email, short form like 'Nov 7'. Empty if none.")
    var dates: [String]
}

/// Summarizes with the on-device Foundation Models framework. Never touches the network.
struct AppleIntelligenceSummarizer: EmailSummarizer {
    var engine: SummaryEngine { .appleIntelligence }

    /// The on-device model has a small context window; keep the prompt well inside it.
    static let maxBodyCharacters = 2_500

    static let instructions = """
    You turn one email into a short post for a calm, social-style inbox feed.
    Be factual and neutral. Never invent details that are not in the email.
    Write the headline in at most 8 words and the blurb in at most 25 words.
    Do not repeat codes, passwords or account numbers; if the email has them, mark it sensitive.
    """

    func summarize(_ input: SummaryInput) async throws -> EmailSummary {
        // A fresh session per email keeps each request independent and the context small.
        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = """
        From: \(input.sender)
        Subject: \(input.subject)

        \(String(input.body.prefix(Self.maxBodyCharacters)))
        """
        let response = try await session.respond(
            to: prompt,
            generating: PostSummary.self,
            options: GenerationOptions(temperature: 0.2)
        )
        let s = response.content
        return EmailSummary(
            headline: TextClamp.words(s.headline, max: FallbackSummarizer.headlineMaxWords),
            blurb: TextClamp.words(s.blurb, max: FallbackSummarizer.blurbMaxWords),
            needsReply: s.needsReply && !input.senderIsAutomated,
            category: PostCategory(rawValue: s.category.lowercased()) ?? .updates,
            imageQuery: s.imageQuery,
            sensitive: s.sensitive,
            dates: s.dates,
            engine: .appleIntelligence
        )
    }

    /// Loads the model ahead of the first request.
    static func prewarm() {
        guard ModelStatus.current.isAvailable else { return }
        LanguageModelSession(instructions: instructions).prewarm()
    }
}
