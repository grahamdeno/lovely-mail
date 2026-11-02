import Foundation

/// OAuth scopes. Read-only, on purpose. Reelmail never asks for permission to send.
enum GmailScope {
    static let readOnly = "https://www.googleapis.com/auth/gmail.readonly"
    /// Everything the app requests. Do not add more without a review of the privacy stance.
    static let requested: [String] = [readOnly]
}

/// Client configuration from the xcconfig via Info.plist. No secrets live in the repo.
struct GmailConfig: Equatable {
    let clientID: String

    static func fromBundle(_ bundle: Bundle = .main) -> GmailConfig {
        let raw = bundle.object(forInfoDictionaryKey: "GoogleIOSClientID") as? String ?? ""
        return GmailConfig(clientID: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Shape of a Google OAuth client ID: project number, hyphen, key, Google suffix.
    /// Must stay in step with scripts/gmail_release_config.py, which gates TestFlight uploads.
    static let clientIDPattern = #"^[0-9]+-[A-Za-z0-9_]+\.apps\.googleusercontent\.com$"#

    /// Empty, unexpanded, placeholder or malformed values mean "not set up": the app stays in sample mode.
    var isConfigured: Bool {
        !clientID.hasPrefix("YOUR_")
            && clientID.range(of: Self.clientIDPattern, options: .regularExpression) != nil
    }

    /// iOS OAuth clients redirect to the reversed client ID.
    var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var redirectURI: String { redirectScheme + ":/oauthredirect" }

    enum CallbackError: Error, Equatable {
        /// Google refused, e.g. "access_denied" when the account isn't a test user or consent was declined.
        case denied(String)
        /// Wrong scheme, missing code, or a state that doesn't match this sign-in attempt.
        case invalid
    }

    /// Extracts the authorization code from Google's redirect, checking scheme and state first.
    func authorizationCode(from callback: URL, expectedState: String) -> Result<String, CallbackError> {
        guard callback.scheme?.lowercased() == redirectScheme.lowercased() else { return .failure(.invalid) }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        guard value("state") == expectedState else { return .failure(.invalid) }
        if let error = value("error") { return .failure(.denied(error)) }
        guard let code = value("code"), !code.isEmpty else { return .failure(.invalid) }
        return .success(code)
    }

    func authorizationURL(pkce: PKCE, state: String) -> URL? {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        c?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GmailScope.requested.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return c?.url
    }
}
