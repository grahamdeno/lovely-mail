import AuthenticationServices
import Foundation
import os
import UIKit

/// Read-only Gmail client. Signs in with ASWebAuthenticationSession + PKCE (iOS OAuth client,
/// no client secret), keeps tokens in the Keychain, and only lists and reads messages.
/// There is deliberately no code path that sends, drafts or modifies mail.
@MainActor
final class GmailService: NSObject {
    enum GmailError: LocalizedError {
        case notConfigured, cancelled, badCallback, denied(String), http(Int), notSignedIn, sessionExpired

        /// True when the only fix is signing in again.
        var needsReconnect: Bool {
            switch self {
            case .sessionExpired, .notSignedIn: return true
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
            case .notSignedIn: return "Not signed in to Gmail."
            case .sessionExpired: return "Google signed you out. Reconnect Gmail in Profile."
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
    func listMessageIDs(query: String, limit: Int) async throws -> (ids: [String], truncated: Bool) {
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
        return (Array(ids.prefix(limit)), pageToken != nil)
    }

    /// One message with its full payload, parsed to plain text.
    func getMessage(id: String, account: String?) async throws -> Email {
        var c = URLComponents(string: Self.api + "/messages/" + id)!
        c.queryItems = [URLQueryItem(name: "format", value: "full")]
        let message: GmailMessage = try await get(c.url!)
        return GmailMessageParser.email(from: message, account: account)
    }

    /// Downloads only messages not already in `known`; a few at a time so an inbox loads in seconds.
    private func messages(ids: [String], account: String, known: [String: Email]) async throws -> [Email] {
        var out: [Email] = []
        var pending: [String] = []
        for id in ids {
            if let cached = known[id] { out.append(cached) } else { pending.append(id) }
        }
        for batch in stride(from: 0, to: pending.count, by: 6).map({ Array(pending[$0..<min($0 + 6, pending.count)]) }) {
            try await withThrowingTaskGroup(of: Email.self) { group in
                for id in batch { group.addTask { try await self.getMessage(id: id, account: account) } }
                for try await email in group { out.append(email) }
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits = .standard) async throws -> MailboxSnapshot {
        let account = try await accountAddress()
        let cache = known?.account == account ? known : nil
        let knownByID = Dictionary(((cache?.inbox ?? []) + (cache?.sent ?? [])).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let inboxList = try await listMessageIDs(query: "in:inbox category:primary", limit: limits.inboxMessages)
        let sentList = try await listMessageIDs(query: "in:sent newer_than:\(limits.sentWindowDays)d", limit: limits.sentMessages)
        let inbox = try await messages(ids: inboxList.ids, account: account, known: knownByID)
        let sent = try await messages(ids: sentList.ids, account: account, known: knownByID)
            .map { var e = $0; e.isFromMe = true; e.bulk = false; return e }
        log.info("Mailbox import complete: \(inbox.count, privacy: .public) inbox, \(sent.count, privacy: .public) sent")
        return MailboxSnapshot(account: account, inbox: inbox, sent: sent, fetchedAt: Date(), inboxTruncated: inboxList.truncated)
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer " + (try await accessToken()), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            log.error("Gmail GET failed with HTTP \(code, privacy: .public)")
            if code == 401 { keychain.delete(); throw GmailError.sessionExpired }
            throw GmailError.http(code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func accessToken() async throws -> String {
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
    }

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
