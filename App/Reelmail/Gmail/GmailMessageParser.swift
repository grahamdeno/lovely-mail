import Foundation

/// Gmail API message resource, the subset Reelmail reads (format=full).
struct GmailMessage: Decodable {
    struct Header: Decodable { let name: String; let value: String }
    struct Body: Decodable { let size: Int?; let data: String? }
    struct Part: Decodable {
        let mimeType: String?
        let headers: [Header]?
        let body: Body?
        let parts: [Part]?
    }

    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let internalDate: String?
    let payload: Part?
}

/// users/me/threads/{id}?format=metadata. Read-only.
struct GmailThreadResponse: Decodable {
    let messages: [GmailMessage]?
}

struct GmailListResponse: Decodable {
    struct Ref: Decodable { let id: String; let threadId: String }
    let messages: [Ref]?
    let nextPageToken: String?
}

/// users/me/profile. Only the address is used, to tell outgoing mail from incoming.
struct GmailProfile: Decodable {
    let emailAddress: String
}

enum GmailMessageParser {
    static func header(_ name: String, in message: GmailMessage) -> String? {
        message.payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// A text/plain part shorter than this is often a stub ("View this email in your browser") beside a real HTML body.
    static let stubLimit = 200

    /// Plain text body: the text/plain part, else text/html with tags stripped, else the snippet.
    /// When the plain part is only a stub and the HTML says more, the HTML wins.
    static func plainText(of message: GmailMessage) -> String {
        if let p = message.payload {
            let plain = firstPart(in: p, mimeType: "text/plain").flatMap(decode)
            let html = firstPart(in: p, mimeType: "text/html").flatMap(decode).map(stripHTML)
            return preferred(plain: plain, html: html) ?? message.snippet ?? ""
        }
        return message.snippet ?? ""
    }

    static func preferred(plain: String?, html: String?) -> String? {
        guard let plain else { return html }
        guard let html, plain.trimmingCharacters(in: .whitespacesAndNewlines).count < stubLimit,
              html.count > plain.trimmingCharacters(in: .whitespacesAndNewlines).count else { return plain }
        return html
    }

    private static func firstPart(in part: GmailMessage.Part, mimeType: String) -> GmailMessage.Part? {
        if part.mimeType?.lowercased() == mimeType, part.body?.data != nil { return part }
        for child in part.parts ?? [] {
            if let found = firstPart(in: child, mimeType: mimeType) { return found }
        }
        return nil
    }

    private static func decode(_ part: GmailMessage.Part) -> String? {
        guard let raw = part.body?.data, let data = Data(base64URLEncoded: raw) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func stripHTML(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"(?is)<(script|style|head)[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</tr>|</li>|</h[1-6]>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#8217;": "’", "&rsquo;": "’", "&zwnj;": "", "&zwj;": ""]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Maya Chen <maya@example.com>" -> Person. Without a display name the name comes from the address.
    static func person(fromHeader value: String) -> Person {
        var name = value
        var rawAddress = value
        if let lt = value.firstIndex(of: "<"), let gt = value.firstIndex(of: ">"), lt < gt {
            rawAddress = String(value[value.index(after: lt)..<gt])
            name = String(value[..<lt]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        }
        rawAddress = rawAddress.trimmingCharacters(in: .whitespaces)
        let address = rawAddress.lowercased()
        if name.isEmpty || name == value { name = displayName(fromAddress: rawAddress) } else { name = firstLast(name) }
        return Person(id: address, name: name, email: address, hue: stableHue(address))
    }

    /// Local parts that say nothing about who sends: the company's domain names the sender instead.
    private static let genericLocalParts: Set<String> = [
        "noreply", "no-reply", "donotreply", "do-not-reply", "info", "admin", "notifications", "notification",
        "mail", "hello", "support", "team", "news",
    ]

    /// A readable name from an address with no display name. "DFAS-SmartDocs@x.example" -> "DFAS SmartDocs",
    /// "pisa.recreation@x.example" -> "Pisa Recreation", "noreply@psu650nc.mg.infinitecampus.org" -> "Infinitecampus".
    static func displayName(fromAddress address: String) -> String {
        let parts = address.split(separator: "@", maxSplits: 1).map(String.init)
        let local = parts.first.map { $0.split(separator: "+", maxSplits: 1).first.map(String.init) ?? $0 } ?? address
        if genericLocalParts.contains(local.lowercased()), parts.count == 2, let label = registrableLabel(of: parts[1]) {
            return label.prefix(1).uppercased() + String(label.dropFirst()).lowercased()
        }
        let words = local.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." }).map(String.init)
        guard !words.isEmpty else { return address }
        return words.map { (word: String) -> String in
            word.contains(where: { $0.isUppercase }) ? word : word.prefix(1).uppercased() + String(word.dropFirst())
        }.joined(separator: " ")
    }

    /// The label before the public suffix: "mg.infinitecampus.org" -> "infinitecampus", "mail.example.co.uk" -> "example".
    static func registrableLabel(of domain: String) -> String? {
        let labels = domain.lowercased().split(separator: ".").map(String.init)
        guard let last = labels.last else { return nil }
        if labels.count >= 3, OrganizationKey.twoPartSuffixes.contains(labels.suffix(2).joined(separator: ".")) {
            return labels[labels.count - 3]
        }
        return labels.count >= 2 ? labels[labels.count - 2] : last
    }

    /// "Brooks, Dana" -> "Dana Brooks". Only a person-shaped "Last, First": one comma, two parts of one or two
    /// words, no organization words, no address.
    static func firstLast(_ name: String) -> String {
        let pieces = name.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard pieces.count == 2, !name.contains("@") else { return name }
        let last = pieces[0].split(separator: " ").map(String.init)
        let first = pieces[1].split(separator: " ").map(String.init)
        guard (1...2).contains(last.count), (1...2).contains(first.count) else { return name }
        let suffixes: Set<String> = ["jr", "jr.", "sr", "sr.", "ii", "iii", "iv", "md", "phd", "esq", "esq."]
        let all = (last + first).map { $0.lowercased() }
        if all.contains(where: { PersonSignals.organizationWords.contains($0) || suffixes.contains($0) }) { return name }
        return pieces[1] + " " + pieces[0]
    }

    /// Deterministic across launches (Swift's hashValue is randomized per process).
    static func stableHue(_ text: String) -> Double {
        var h: UInt32 = 2166136261
        for b in text.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return Double(h % 1000) / 1000
    }

    /// Address list header -> lowercase addresses only.
    static func addresses(in headerValue: String?) -> [String] {
        guard let headerValue, !headerValue.isEmpty else { return [] }
        return headerValue.components(separatedBy: ",").compactMap { part in
            let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { return nil }
            if let lt = p.firstIndex(of: "<"), let gt = p.firstIndex(of: ">"), lt < gt {
                return String(p[p.index(after: lt)..<gt]).lowercased()
            }
            return p.lowercased()
        }
    }

    /// `account` is the signed-in address from users/me/profile; never inferred from display names.
    static func email(from message: GmailMessage, account: String? = nil) -> Email {
        let millis = Double(message.internalDate ?? "") ?? 0
        let from = person(fromHeader: header("From", in: message) ?? "Unknown")
        let labels = message.labelIds ?? []
        let hasList = header("List-Unsubscribe", in: message) != nil || header("List-Id", in: message) != nil
        let mine = account.map { $0.lowercased() == from.email } ?? false
        let autoReply = !mine && AutoReply.isAutoReply(autoSubmitted: header("Auto-Submitted", in: message),
                                                        xAutoreply: header("X-Autoreply", in: message),
                                                        xAutorespond: header("X-Autorespond", in: message))
        return Email(
            id: message.id,
            threadId: message.threadId,
            from: from,
            to: addresses(in: header("To", in: message)),
            cc: addresses(in: header("Cc", in: message)),
            subject: header("Subject", in: message) ?? "(no subject)",
            date: Date(timeIntervalSince1970: millis / 1000),
            body: plainText(of: message),
            isUnread: labels.contains("UNREAD"),
            isFromMe: mine,
            bulk: !mine && SenderSignals.isBulk(labelIds: labels, hasListHeaders: hasList,
                                                precedence: header("Precedence", in: message), address: from.email),
            promotional: !mine && labels.contains("CATEGORY_PROMOTIONS"),
            autoReply: autoReply
        )
    }
}
