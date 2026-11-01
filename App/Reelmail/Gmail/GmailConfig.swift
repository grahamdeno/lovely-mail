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

    /// Empty or unexpanded values mean "not set up yet": the app stays in sample mode.
    var isConfigured: Bool {
        !clientID.isEmpty && !clientID.contains("$(") && !clientID.hasPrefix("YOUR_")
            && clientID.hasSuffix(".apps.googleusercontent.com")
    }

    /// iOS OAuth clients redirect to the reversed client ID.
    var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var redirectURI: String { redirectScheme + ":/oauthredirect" }

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
