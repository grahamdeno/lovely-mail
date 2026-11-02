import Foundation

struct MailTopic: Identifiable {
    struct ID: Hashable { let thread: String; let sender: String }
    let id: ID
    let posts: [Post]
    let lastReply: Email?
    var latest: Post { posts[0] }
    var origin: Post { posts[posts.count - 1] }
    var person: Person { latest.email.from }
    var updatedAt: Date { max(latest.email.date, lastReply?.date ?? .distantPast) }
    var sensitive: Bool {
        posts.contains { ConversationPresentation.isSensitive($0.email, summary: $0.summary) }
            || lastReply.map { ConversationPresentation.isSensitive($0, summary: nil) } == true
    }
    // A later reply is not evidence that an earlier request was completed.
    var possibleReply: Bool { posts.contains { $0.summary.needsReply } }
    var status: String {
        if let lastReply {
            return latest.email.date > lastReply.date ? "New mail since your last loaded reply" : "Your reply is the latest loaded message"
        }
        return possibleReply ? "Possible request · no reply loaded" : "Latest loaded update"
    }
    var title: String { sensitive ? "Private topic" : origin.summary.headline }
    var preview: ConversationPreview {
        if sensitive { return ConversationPreview(text: "Open the conversation to read private details.", label: nil, concealed: true) }
        // Prefer a possibly unfinished request over a later informational fragment.
        let focus = posts.first { $0.summary.needsReply } ?? latest
        if !focus.summary.needsReply, focus.summary.engine == .appleIntelligence,
           !focus.summary.blurb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ConversationPreview(text: focus.summary.blurb, label: "AI summary", concealed: false)
        }
        let text = Self.sourcePreview(focus.email.body, category: focus.summary.category, automated: focus.email.from.isAutomated)
        return ConversationPreview(text: text.isEmpty ? "Open the source to read this message." : text, label: "Excerpt", concealed: false)
    }
    var replyContext: String? {
        guard !sensitive, let lastReply else { return nil }
        let text = lastReply.body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return "You: " + TextClamp.words(text, max: 18)
    }
    static func sourcePreview(_ body: String, category: PostCategory, automated: Bool) -> String {
        var lines = body.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let first = lines.first, FallbackSummarizer.isGreeting(first), lines.count > 1 { lines.removeFirst() }
        let text = lines.joined(separator: " ")
        guard !text.isEmpty else { return "" }
        let regex = try? NSRegularExpression(pattern: #"[\s\S]+?(?:[.!?](?=\s|$)|$)"#)
        let ns = text as NSString
        let sentences = regex?.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        guard let first = sentences.first else { return TextClamp.words(text, max: 45) }
        let request = sentences.last { FallbackSummarizer.needsReply(body: $0, automated: automated, category: category) }
        if let request, request != first {
            let context = TextClamp.words(first, max: 24)
            let action = TextClamp.words(request, max: 30)
            return context + " " + action
        }
        return TextClamp.words(first, max: 45)
    }
    static func make(posts: [Post], sent: [Email]) -> [MailTopic] {
        let groups = Dictionary(grouping: posts) { post in
            ID(thread: post.email.threadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
               ? "message:" + post.id : post.email.threadId, sender: post.email.from.id)
        }
        return groups.map { key, values in
            let ordered = values.sorted { $0.email.date == $1.email.date ? $0.id < $1.id : $0.email.date > $1.email.date }
            let email = ordered[0].email
            let address = email.from.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let reply = sent.filter {
                $0.isFromMe && !$0.threadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.threadId == email.threadId
                    && $0.to.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == address }
            }.max { $0.date < $1.date }
            return MailTopic(id: key, posts: ordered, lastReply: reply)
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.id.thread != $1.id.thread { return $0.id.thread < $1.id.thread }
            return $0.id.sender < $1.id.sender
        }
    }
}

enum MailTime {
    static func label(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 { return date.formatted(date: .abbreviated, time: .shortened) }
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) hr ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Compact time for a feed row: "3:42 PM", "Yesterday", "Tue", "Oct 26", "10/26/25".
    static func short(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "Yesterday" }
        if days > 1, days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits))
    }
}
