import Foundation
import FoundationModels

/// Writes a suggested reply. The user copies it or opens Gmail; Reelmail never sends.
protocol ReplyDrafter: Sendable {
    var engine: SummaryEngine { get }
    func draft(replyTo email: Email, myName: String) async throws -> String
}

struct TemplateReplyDrafter: ReplyDrafter {
    var engine: SummaryEngine { .fallback }

    func draft(replyTo email: Email, myName: String) async throws -> String {
        let topic = FallbackSummarizer.cleanSubject(email.subject, fallbackBody: email.body).lowercased()
        let signOff = myName.isEmpty ? "" : "\n\n" + myName
        return "Hi \(email.from.firstName),\n\nThanks for the note about \(topic). I'll get back to you shortly with an answer." + signOff
    }
}

struct AppleIntelligenceReplyDrafter: ReplyDrafter {
    var engine: SummaryEngine { .appleIntelligence }

    func draft(replyTo email: Email, myName: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
        You draft short, warm, plain email replies for the user to edit and send themselves.
        Answer what was asked only if the email makes the answer obvious; otherwise acknowledge and say you'll follow up.
        Keep it under 80 words. \(myName.isEmpty ? "Do not add a signature." : "Sign off with the user's first name.")
        """)
        let prompt = """
        \(myName.isEmpty ? "" : "The user's name: " + myName)
        Reply to this email from \(email.from.name).
        Subject: \(email.subject)

        \(String(email.body.prefix(AppleIntelligenceSummarizer.maxBodyCharacters)))
        """
        return try await session.respond(to: prompt).content
    }
}

enum ReplyDrafterFactory {
    static func best() -> any ReplyDrafter {
        ModelStatus.current.isAvailable ? AppleIntelligenceReplyDrafter() : TemplateReplyDrafter()
    }
}

/// Hands a draft to Gmail's compose screen. The user presses Send there, never us.
enum GmailCompose {
    /// `cc` is comma-separated and left out of the link when empty.
    static func appURL(to: String, cc: String = "", subject: String, body: String) -> URL? {
        var c = URLComponents()
        c.scheme = "googlegmail"
        c.host = "co"
        var items = [URLQueryItem(name: "to", value: to)]
        if !cc.isEmpty { items.append(URLQueryItem(name: "cc", value: cc)) }
        items += [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        c.queryItems = items
        return c.url
    }

    static func webURL(to: String, cc: String = "", subject: String, body: String) -> URL? {
        var c = URLComponents(string: "https://mail.google.com/mail/")
        var items = [URLQueryItem(name: "view", value: "cm"), URLQueryItem(name: "to", value: to)]
        if !cc.isEmpty { items.append(URLQueryItem(name: "cc", value: cc)) }
        items += [URLQueryItem(name: "su", value: subject), URLQueryItem(name: "body", value: body)]
        c?.queryItems = items
        return c?.url
    }

    static func replySubject(_ subject: String) -> String {
        subject.lowercased().hasPrefix("re:") ? subject : "Re: " + subject
    }
}
