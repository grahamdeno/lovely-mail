import Foundation

/// What one import of the account produced. Everything here is data read from Gmail.
struct MailboxSnapshot: Codable, Equatable {
    /// The signed-in address from users/me/profile.
    var account: String
    /// Primary-tab inbox messages, newest first.
    var inbox: [Email]
    /// Messages the account sent, newest first.
    var sent: [Email]
    var fetchedAt: Date
    /// True when the import stopped at its limit rather than at the end of the mailbox.
    var inboxTruncated: Bool = false

    static let empty = MailboxSnapshot(account: "", inbox: [], sent: [], fetchedAt: .distantPast)
}

/// How much to import. Bounded on purpose; see docs/calm-feed.md.
struct ImportLimits: Equatable {
    var inboxMessages = 120
    /// Unread inbox messages are all loaded, however old, up to this many. Unread is your to-do list.
    var unreadMessages = 300
    var sentMessages = 60
    /// Only sent mail newer than this is imported (days).
    var sentWindowDays = 90

    static let standard = ImportLimits()
}

@MainActor
protocol GmailInboxClient: AnyObject {
    var config: GmailConfig { get }
    var isSignedIn: Bool { get }
    /// Imports the mailbox. `known` lets the client skip downloading messages it already has.
    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits) async throws -> MailboxSnapshot
    /// Moves one message to Gmail's Trash, and back. Approved 2026-11-01.
    func trash(messageID: String) async throws
    func untrash(messageID: String) async throws
    /// Marks one message read ("Done"), and unread again to undo it. Approved 2026-11-02. Only the UNREAD label.
    func markRead(messageID: String) async throws
    func markUnread(messageID: String) async throws
    /// Who wrote each message in a thread and when. Read-only (metadata only, no bodies).
    func threadSenders(threadID: String) async throws -> [ThreadSender]
    /// Message ids matching a Gmail search, newest first. Read-only.
    func listMessageIDs(query: String, limit: Int) async throws -> (ids: [String], truncated: Bool, query: String)
    /// Sender, subject and date only (no body). Read-only.
    func getMetadata(id: String) async throws -> MessageStub
    /// One full message, for mail the insight readers recognise.
    func getMessage(id: String, account: String?) async throws -> Email
    func signIn() async throws
    func signOut()
}

extension GmailInboxClient {
    /// Clients that cannot look a thread up report nothing, which keeps Waiting on them to the mail already loaded.
    func threadSenders(threadID: String) async throws -> [ThreadSender] { [] }
    func listMessageIDs(query: String, limit: Int) async throws -> (ids: [String], truncated: Bool, query: String) { ([], false, query) }
    func getMetadata(id: String) async throws -> MessageStub { throw GmailService.GmailError.refused(0, GmailAPIError(reason: "unsupported", message: "Not supported")) }
    func getMessage(id: String, account: String?) async throws -> Email { throw GmailService.GmailError.refused(0, GmailAPIError(reason: "unsupported", message: "Not supported")) }
}

/// A message's envelope: enough to decide whether it is worth downloading.
struct MessageStub: Equatable, Sendable {
    var id: String
    var fromName: String
    var fromAddress: String
    var subject: String
    var date: Date
    var listUnsubscribe: String?
    var listUnsubscribePost: String?
}

/// One message in a thread, for "has anyone answered?".
struct ThreadSender: Equatable, Sendable {
    var address: String
    var date: Date
    /// An out-of-office or other automatic reply, which is not an answer.
    var isAutoReply: Bool = false
}

extension GmailService: GmailInboxClient {}
