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
    var possibleReply: Bool {
        posts.contains { $0.summary.needsReply && $0.email.date > (lastReply?.date ?? .distantPast) }
    }
    var status: String {
        if let lastReply {
            return latest.email.date > lastReply.date ? "New mail since your last loaded reply" : "Your reply is the latest loaded message"
        }
        return possibleReply ? "Possible request · no reply loaded" : "Latest loaded update"
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
}
