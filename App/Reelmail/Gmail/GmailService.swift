import AuthenticationServices
import Foundation
import os
import UIKit

/// Gmail client. Signs in with ASWebAuthenticationSession + PKCE (iOS OAuth client,
/// no client secret), keeps tokens in the Keychain, lists and reads messages, and can move one message
/// to Trash (and back). There is deliberately no code path that sends, drafts, relabels or permanently deletes.
@MainActor
final class GmailService: NSObject {
    enum GmailError: LocalizedError {
        case notConfigured, cancelled, badCallback, denied(String), http(Int), notSignedIn, sessionExpired, needsTrashPermission, needsActionPermission, mailAccessNotGranted, refused(Int, GmailAPIError)

        /// True when the only fix is signing in again.
        var needsReconnect: Bool {
            switch self {
            case .sessionExpired, .notSignedIn, .needsTrashPermission, .needsActionPermission, .mailAccessNotGranted: return true
            default: return false
            }
        }

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Gmail isn't set up yet. Add a Google iOS client ID to Config/Local.xcconfig."
            case .cancelled: return "Sign-in was cancelled."
            case .badCallback: return "Google returned an unexpected sign-in response."
            case .denied(let reason) where reason == "access_denied":
                return "Google denied access. This Google account may not be on the app's test-user list."
            case .denied(let reason): return "Google declined sign-in (\(reason))."
            case .http(let code): return "Gmail returned HTTP \(code)."
            case .refused(let code, let e):
                return "Gmail refused the request (HTTP \(code), \(e.reason)). \(e.message)"
            case .notSignedIn: return "Not signed in to Gmail."
            case .sessionExpired: return "Google signed you out. Reconnect Gmail in Settings."
            case .needsActionPermission: return "Google hasn't given Lovely permission to do this yet. Reconnect Gmail in Settings and tick every box on Google's screen."
            case .needsTrashPermission: return "Lovely needs your OK to change mail in Gmail (Trash and Done). Reconnect Gmail in Settings and allow it."
            case .mailAccessNotGranted:
                return "Google didn't give Lovely access to your mail. Reconnect Gmail in Settings, and on Google's screen tick the Gmail box (or Select all) before Continue."
            }
        }
    }

    private static let api = "https://gmail.googleapis.com/gmail/v1/users/me"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    /// Logs status and counts only. Never subjects, addresses or bodies.
    private let log = Logger(subsystem: "com.grahamdeno.reelmail", category: "gmail")

    let config: GmailConfig
    private let keychain: KeychainStore
    private var authSession: ASWebAuthenticationSession?

    init(config: GmailConfig = .fromBundle(), keychain: KeychainStore = .googleTokens) {
        self.config = config
        self.keychain = keychain
    }

    var isSignedIn: Bool { storedTokens() != nil }

    // MARK: Sign in

    func signIn() async throws {
        guard config.isConfigured else { throw GmailError.notConfigured }
        let pkce = PKCE.make()
        let state = PKCE.randomState()
        guard let url = config.authorizationURL(pkce: pkce, state: state) else { throw GmailError.badCallback }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: config.redirectScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GmailError.cancelled)
                } else { continuation.resume(throwing: error ?? GmailError.badCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            session.start()
        }
        authSession = nil

        let code: String
        switch config.authorizationCode(from: callback, expectedState: state) {
        case .success(let value): code = value
        case .failure(.denied(let reason)):
            log.error("Google declined sign-in: \(reason, privacy: .public)")
            throw GmailError.denied(reason)
        case .failure(.invalid): throw GmailError.badCallback
        }

        let tokens = try await exchange([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "code_verifier": pkce.verifier,
        ], previousRefreshToken: nil)
        // The Gmail box on Google's consent screen can be left unticked; then every read fails with 403.
        guard GmailScope.canRead(granted: lastGrantedScope) else {
            log.error("Sign-in granted no Gmail scope")
            throw GmailError.mailAccessNotGranted
        }
        store(tokens)
        log.info("Gmail sign-in complete")
    }

    func signOut() {
        keychain.delete()
        log.info("Gmail signed out")
    }

    // MARK: Read

    /// The signed-in address. Used to mark outgoing mail; never inferred from display names.
    func accountAddress() async throws -> String {
        let profile: GmailProfile = try await get(URL(string: Self.api + "/profile")!)
        return profile.emailAddress.lowercased()
    }

    /// Message ids matching a Gmail search, newest first, following pages up to `limit`.
    func listMessageIDs(query: String, limit: Int) async throws -> (ids: [String], truncated: Bool, query: String) {
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var c = URLComponents(string: Self.api + "/messages")!
            c.queryItems = [URLQueryItem(name: "maxResults", value: String(min(100, limit - ids.count))),
                            URLQueryItem(name: "q", value: query)]
            if let pageToken { c.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let list: GmailListResponse = try await get(c.url!)
            ids += list.messages?.map(\.id) ?? []
            pageToken = list.nextPageToken
        } while pageToken != nil && ids.count < limit
        log.info("Listed \(ids.count, privacy: .public) messages")
        return (Array(ids.prefix(limit)), pageToken != nil, query)
    }

    /// One message with its full payload, parsed to plain text.
    func getMessage(id: String, account: String?) async throws -> Email {
        var c = URLComponents(string: Self.api + "/messages/" + id)!
        c.queryItems = [URLQueryItem(name: "format", value: "full")]
        let message: GmailMessage = try await get(c.url!)
        return GmailMessageParser.email(from: message, account: account)
    }

    /// Sender, subject, date and unsubscribe headers for one message. No body. Read-only.
    func getMetadata(id: String) async throws -> MessageStub {
        guard let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !safe.isEmpty else { throw GmailError.badCallback }
        var c = URLComponents(string: Self.api + "/messages/" + safe)!
        c.queryItems = ["From", "Subject", "Date", "List-Unsubscribe", "List-Unsubscribe-Post"].map { URLQueryItem(name: "metadataHeaders", value: $0) }
        c.queryItems?.insert(URLQueryItem(name: "format", value: "metadata"), at: 0)
        let message: GmailMessage = try await get(c.url!)
        let person = GmailMessageParser.person(fromHeader: GmailMessageParser.header("From", in: message) ?? "")
        let millis = Double(message.internalDate ?? "") ?? 0
        return MessageStub(id: message.id, fromName: person.name, fromAddress: person.email.lowercased(),
                           subject: GmailMessageParser.header("Subject", in: message) ?? "",
                           date: Date(timeIntervalSince1970: millis / 1000),
                           listUnsubscribe: GmailMessageParser.header("List-Unsubscribe", in: message),
                           listUnsubscribePost: GmailMessageParser.header("List-Unsubscribe-Post", in: message))
    }

    /// The senders and dates of every message in a thread (headers only, no bodies). Read-only.
    func threadSenders(threadID: String) async throws -> [ThreadSender] {
        guard let id = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !id.isEmpty else { throw GmailError.badCallback }
        var c = URLComponents(string: Self.api + "/threads/" + id)!
        c.queryItems = [URLQueryItem(name: "format", value: "metadata"),
                        URLQueryItem(name: "metadataHeaders", value: "From"),
                        URLQueryItem(name: "metadataHeaders", value: "Date"),
                        URLQueryItem(name: "metadataHeaders", value: "Subject"),
                        URLQueryItem(name: "metadataHeaders", value: "Auto-Submitted"),
                        URLQueryItem(name: "metadataHeaders", value: "X-Autoreply"),
                        URLQueryItem(name: "metadataHeaders", value: "X-Autorespond")]
        let thread: GmailThreadResponse = try await get(c.url!)
        return (thread.messages ?? []).map { message in
            let from = GmailMessageParser.person(fromHeader: GmailMessageParser.header("From", in: message) ?? "").email
            let millis = Double(message.internalDate ?? "") ?? 0
            let auto = AutoReply.subjectIsAutoReply(GmailMessageParser.header("Subject", in: message) ?? "")
                || AutoReply.isAutoReply(autoSubmitted: GmailMessageParser.header("Auto-Submitted", in: message),
                                         xAutoreply: GmailMessageParser.header("X-Autoreply", in: message),
                                         xAutorespond: GmailMessageParser.header("X-Autorespond", in: message))
            return ThreadSender(address: from.lowercased(), date: Date(timeIntervalSince1970: millis / 1000), isAutoReply: auto)
        }
    }

    /// Downloads only messages not already in `known`, a few at a time. If Google's per-minute quota still
    /// refuses a message after waiting, that message is skipped (and fetched on the next refresh) instead of
    /// discarding everything that did load. Returns the emails and how many were skipped.
    private func messages(ids: [String], account: String, known: [String: Email]) async throws -> (emails: [Email], skipped: Int) {
        var out: [Email] = []
        var pending: [String] = []
        var skipped = 0
        for id in ids {
            if let cached = known[id] { out.append(cached) } else { pending.append(id) }
        }
        for batch in stride(from: 0, to: pending.count, by: 4).map({ Array(pending[$0..<min($0 + 4, pending.count)]) }) {
            try await withThrowingTaskGroup(of: Email?.self) { group in
                for id in batch {
                    group.addTask {
                        do { return try await self.getMessage(id: id, account: account) }
                        catch GmailError.refused(let code, let detail) where code == 429 || detail.isRateLimit { return nil }
                    }
                }
                for try await email in group { if let email { out.append(email) } else { skipped += 1 } }
            }
        }
        if skipped > 0 { log.info("Skipped \(skipped, privacy: .public) messages for the rate limit") }
        return (out.sorted { $0.date > $1.date }, skipped)
    }

    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits = .standard) async throws -> MailboxSnapshot {
        let account = try await accountAddress()
        let cache = known?.account == account ? known : nil
        let knownByID = Dictionary(((cache?.inbox ?? []) + (cache?.sent ?? [])).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Primary tab first. Accounts with inbox tabs turned off can return nothing for category:primary,
        // so fall back to the inbox without the Promotions, Social, Updates and Forums tabs, then to the whole inbox.
        var inboxList = try await listMessageIDs(query: "in:inbox category:primary", limit: limits.inboxMessages)
        if inboxList.ids.isEmpty {
            inboxList = try await listMessageIDs(query: "in:inbox -category:promotions -category:social -category:updates -category:forums", limit: limits.inboxMessages)
        }
        if inboxList.ids.isEmpty {
            inboxList = try await listMessageIDs(query: "in:inbox", limit: limits.inboxMessages)
        }
        // Unread is your to-do list, so every unread inbox message is loaded however old it is and whichever
        // inbox tab it is in (bills and statements usually land in Updates, not Primary), and the unread state of
        // every loaded message is re-read from Gmail each time (it changes when you read mail elsewhere).
        let unreadList = try await listMessageIDs(query: "is:unread in:inbox", limit: limits.unreadMessages)
        let listed = Set(inboxList.ids)
        let extraUnread = unreadList.ids.filter { !listed.contains($0) }
        let sentList = try await listMessageIDs(query: "in:sent newer_than:\(limits.sentWindowDays)d", limit: limits.sentMessages)
        let inboxResult = try await messages(ids: inboxList.ids + extraUnread, account: account, known: knownByID)
        let sentResult = try await messages(ids: sentList.ids, account: account, known: knownByID)
        let inbox = Self.applyUnread(inboxResult.emails, unread: Set(unreadList.ids), complete: !unreadList.truncated)
        let sent = sentResult.emails.map { var e = $0; e.isFromMe = true; e.bulk = false; return e }
        log.info("Mailbox import complete: \(inbox.count, privacy: .public) inbox, \(sent.count, privacy: .public) sent")
        // Skipped messages make the inbox incomplete for now; the next refresh fetches only what is missing.
        return MailboxSnapshot(account: account, inbox: inbox, sent: sent, fetchedAt: Date(),
                               inboxTruncated: inboxList.truncated || inboxResult.skipped > 0)
    }

    // MARK: The only changes Lovely makes to Gmail (approved by the owner)
    // 2026-11-01: move one message to Trash and back. 2026-11-02: mark one message read, and unread again for Undo.
    // Nothing else: no sending, no permanent delete, no other labels.

    private enum MessageAction: String {
        case trash, untrash, markRead, markUnread
        var path: String {
            switch self {
            case .trash: return "trash"
            case .untrash: return "untrash"
            case .markRead, .markUnread: return "modify"
            }
        }
        /// The request body. Only ever the UNREAD label, never any other.
        var body: Data? {
            switch self {
            case .trash, .untrash: return nil
            case .markRead: return Data(#"{"removeLabelIds":["UNREAD"]}"#.utf8)
            case .markUnread: return Data(#"{"addLabelIds":["UNREAD"]}"#.utf8)
            }
        }
    }

    /// Moves one message to Gmail's Trash. Recoverable for 30 days. Never a permanent delete.
    func trash(messageID: String) async throws { try await perform(.trash, messageID: messageID) }
    /// Takes one message back out of Trash.
    func untrash(messageID: String) async throws { try await perform(.untrash, messageID: messageID) }
    /// Marks one message read in Gmail ("Done" on your to-do).
    func markRead(messageID: String) async throws { try await perform(.markRead, messageID: messageID) }
    /// Marks one message unread again. Only used to undo "Done".
    func markUnread(messageID: String) async throws { try await perform(.markUnread, messageID: messageID) }

    private func perform(_ action: MessageAction, messageID: String) async throws {
        guard let id = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !id.isEmpty,
              let url = URL(string: Self.api + "/messages/" + id + "/" + action.path) else { throw GmailError.badCallback }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let body = action.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer " + (try await accessToken()), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = GmailAPIError.parse(data)
            log.error("Gmail \(action.rawValue, privacy: .public) failed with HTTP \(code, privacy: .public) \(detail?.reason ?? "", privacy: .public)")
            if code == 401 { keychain.delete(); throw GmailError.sessionExpired }
            // 403 on a sign-in made before changes were approved: the token only holds the read-only scope.
            if code == 403, detail?.isMissingScope ?? true { throw GmailError.needsTrashPermission }
            if let detail { throw GmailError.refused(code, detail) }
            throw GmailError.http(code)
        }
        log.info("Gmail \(action.rawValue, privacy: .public) succeeded")
    }

    /// Sets each message's unread state from Gmail's current unread list. When that list stopped at its limit,
    /// messages outside it keep the state they were downloaded with.
    nonisolated static func applyUnread(_ emails: [Email], unread: Set<String>, complete: Bool) -> [Email] {
        emails.map { email in
            var e = email
            if unread.contains(e.id) { e.isUnread = true } else if complete { e.isUnread = false }
            return e
        }
    }

    // MARK: Plumbing

    /// Waits before retrying a request Google refused for the per-minute quota. The quota refills each minute.
    static let rateLimitWaits: [UInt64] = [20, 40]

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var attempt = 0
        while true {
            do { return try await getOnce(url) }
            catch GmailError.refused(let code, let detail) where (code == 429 || detail.isRateLimit) && attempt < Self.rateLimitWaits.count {
                log.info("Gmail rate limit; waiting \(Self.rateLimitWaits[attempt], privacy: .public)s")
                try await Task.sleep(nanoseconds: Self.rateLimitWaits[attempt] * 1_000_000_000)
                attempt += 1
            }
        }
    }

    private func getOnce<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer " + (try await accessToken()), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = GmailAPIError.parse(data)
            log.error("Gmail GET failed with HTTP \(code, privacy: .public) \(detail?.reason ?? "", privacy: .public)")
            if code == 401 { keychain.delete(); throw GmailError.sessionExpired }
            // Reading is refused because the sign-in lacks Gmail access (box unticked, or access removed).
            if code == 403, detail?.isMissingScope == true { keychain.delete(); throw GmailError.mailAccessNotGranted }
            // Anything else (API turned off in Google Cloud, rate limit, policy): show Google's own reason.
            if let detail { throw GmailError.refused(code, detail) }
            if code == 429 { throw GmailError.refused(429, GmailAPIError(reason: "RATE_LIMIT_EXCEEDED", message: "Too many requests.")) }
            throw GmailError.http(code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func accessToken() async throws -> String {
        guard let tokens = storedTokens() else { throw GmailError.notSignedIn }
        if !tokens.isExpired { return tokens.accessToken }
        guard let refresh = tokens.refreshToken else { throw GmailError.notSignedIn }
        let fresh = try await exchange([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": config.clientID,
        ], previousRefreshToken: refresh)
        store(fresh)
        return fresh.accessToken
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
        let scope: String?
    }

    /// Scopes Google granted in the most recent token exchange.
    private var lastGrantedScope: String?

    private func exchange(_ form: [String: String], previousRefreshToken: String?) async throws -> OAuthTokens {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            log.error("Token exchange failed with HTTP \(code, privacy: .public)")
            // A refresh token Google no longer honors (expired test-user grant, revoked access).
            if previousRefreshToken != nil, code == 400 || code == 401 { keychain.delete(); throw GmailError.sessionExpired }
            throw GmailError.http(code)
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        lastGrantedScope = t.scope
        return OAuthTokens(accessToken: t.access_token,
                           refreshToken: t.refresh_token ?? previousRefreshToken,
                           expiresAt: Date().addingTimeInterval(t.expires_in))
    }

    private func storedTokens() -> OAuthTokens? {
        keychain.load().flatMap { try? JSONDecoder().decode(OAuthTokens.self, from: $0) }
    }

    private func store(_ tokens: OAuthTokens) {
        if let data = try? JSONEncoder().encode(tokens) { keychain.save(data) }
    }
}

extension GmailService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
            if let scene = scenes.first { return UIWindow(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }
}
