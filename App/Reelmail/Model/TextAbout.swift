import Foundation

/// "Text someone about this": a short summary of an email to start a conversation, sent from Messages.
/// Lovely never sends it; the owner picks the person and taps Send in Apple's Messages sheet.
/// Nothing assumes who that person is: the first time he picks from Contacts, then Lovely offers the people
/// he texted before, most recent first. Pure here, so it is tested.
enum TextAbout {
    static let maxLength = 320

    /// "text Julia", "Text my wife about this", "send this to Sam": a request to text someone about this email.
    static func isTextRequest(_ said: String) -> Bool {
        let t = said.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = t.split(separator: " ")
        guard let first = words.first, words.count >= 2, words.count <= 8 else { return false }
        if first == "text" || first == "message" { return true }
        return t.hasPrefix("send this to ") || t.hasPrefix("send it to ") || t.hasPrefix("share this with ")
    }

    /// The draft: who it's from, what it's about, the first date in it, and an opener. Sensitive mail gets only
    /// the sender and subject, never the summary.
    static func draft(fromName: String, subject: String, blurb: String, sensitive: Bool, dateLabel: String?) -> String {
        let who = fromName.trimmingCharacters(in: .whitespaces).isEmpty ? "someone" : fromName
        let about = subject.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " about \u{201C}\(subject)\u{201D}"
        var text = "Got an email from \(who)\(about)."
        if !sensitive, !blurb.isEmpty { text += " " + blurb.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let dateLabel, !sensitive { text += " Date: \(dateLabel)." }
        text += " Want to talk about it?"
        if text.count > maxLength {
            text = String(text.prefix(maxLength - 24)).trimmingCharacters(in: .whitespaces) + "\u{2026} Want to talk about it?"
        }
        return text
    }
}

/// Someone he has texted about an email. Kept on this phone only.
struct TextRecipient: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var phone: String
    var id: String { phone }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

/// The people he texts about emails, most recent first (at most 5). On this phone only.
struct TextRecipients {
    static let key = "lovely.textAbout.recipients"
    static let max = 5
    var defaults: UserDefaults = .standard

    var all: [TextRecipient] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([TextRecipient].self, from: data)) ?? []
    }

    func remember(_ r: TextRecipient) {
        let phone = Self.normalized(r.phone)
        guard !phone.isEmpty else { return }
        var list = all.filter { Self.normalized($0.phone) != phone }
        list.insert(TextRecipient(name: r.name, phone: r.phone), at: 0)
        defaults.set(try? JSONEncoder().encode(Array(list.prefix(Self.max))), forKey: Self.key)
    }

    func forget(_ r: TextRecipient) {
        let phone = Self.normalized(r.phone)
        defaults.set(try? JSONEncoder().encode(all.filter { Self.normalized($0.phone) != phone }), forKey: Self.key)
    }

    static func normalized(_ phone: String) -> String { phone.filter { $0.isNumber || $0 == "+" } }
}
