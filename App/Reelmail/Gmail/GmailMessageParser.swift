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

struct GmailListResponse: Decodable {
    struct Ref: Decodable { let id: String; let threadId: String }
    let messages: [Ref]?
    let nextPageToken: String?
}

enum GmailMessageParser {
    static func header(_ name: String, in message: GmailMessage) -> String? {
        message.payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Plain text body: the first text/plain part, else text/html with tags stripped, else the snippet.
    static func plainText(of message: GmailMessage) -> String {
        if let p = message.payload {
            if let text = firstPart(in: p, mimeType: "text/plain").flatMap(decode) { return text }
            if let html = firstPart(in: p, mimeType: "text/html").flatMap(decode) { return stripHTML(html) }
        }
        return message.snippet ?? ""
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
        var s = html.replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Maya Chen <maya@example.com>" -> Person.
    static func person(fromHeader value: String) -> Person {
        var name = value
        var address = value
        if let lt = value.firstIndex(of: "<"), let gt = value.firstIndex(of: ">"), lt < gt {
            address = String(value[value.index(after: lt)..<gt])
            name = String(value[..<lt]).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        }
        address = address.trimmingCharacters(in: .whitespaces).lowercased()
        if name.isEmpty || name == value { name = address.split(separator: "@").first.map(String.init) ?? address }
        let hue = Double(abs(address.hashValue % 1000)) / 1000
        return Person(id: address, name: name, email: address, hue: hue)
    }

    static func email(from message: GmailMessage) -> Email {
        let millis = Double(message.internalDate ?? "") ?? 0
        return Email(
            id: message.id,
            threadId: message.threadId,
            from: person(fromHeader: header("From", in: message) ?? "Unknown"),
            to: (header("To", in: message) ?? "").components(separatedBy: ","),
            subject: header("Subject", in: message) ?? "(no subject)",
            date: Date(timeIntervalSince1970: millis / 1000),
            body: plainText(of: message),
            isUnread: message.labelIds?.contains("UNREAD") ?? false
        )
    }
}
