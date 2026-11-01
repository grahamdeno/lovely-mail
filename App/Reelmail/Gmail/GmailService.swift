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
        case notConfigured, cancelled, badCallback, http(Int), notSignedIn

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Gmail isn't set up yet. Add a Google iOS client ID to Config/Local.xcconfig."
            case .cancelled: return "Sign-in was cancelled."
            case .badCallback: return "Google returned an unexpected sign-in response."
            case .http(let code): return "Gmail returned HTTP \(code)."
            case .notSignedIn: return "Not signed in to Gmail."
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

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw GmailError.badCallback }

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

    /// Message ids in the inbox, newest first.
    func listMessageIDs(maxResults: Int = 30, query: String = "in:inbox") async throws -> [String] {
        var c = URLComponents(string: Self.api + "/messages")!
        c.queryItems = [URLQueryItem(name: "maxResults", value: String(maxResults)),
                        URLQueryItem(name: "q", value: query)]
        let list: GmailListResponse = try await get(c.url!)
        log.info("Listed \(list.messages?.count ?? 0, privacy: .public) messages")
        return list.messages?.map(\.id) ?? []
    }

    /// One message with its full payload, parsed to plain text.
    func getMessage(id: String) async throws -> Email {
        var c = URLComponents(string: Self.api + "/messages/" + id)!
        c.queryItems = [URLQueryItem(name: "format", value: "full")]
        let message: GmailMessage = try await get(c.url!)
        return GmailMessageParser.email(from: message)
    }

    func fetchInbox(maxResults: Int = 30) async throws -> [Email] {
        var emails: [Email] = []
        for id in try await listMessageIDs(maxResults: maxResults) {
            emails.append(try await getMessage(id: id))
        }
        return emails.sorted { $0.date > $1.date }
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer " + (try await accessToken()), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            log.error("Gmail GET failed with HTTP \(code, privacy: .public)")
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
