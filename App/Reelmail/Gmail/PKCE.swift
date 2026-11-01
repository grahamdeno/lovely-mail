import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636), S256.
struct PKCE: Equatable {
    let verifier: String
    let challenge: String

    static func make() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "No secure randomness")
        return PKCE(verifier: Data(bytes).base64URLEncoded())
    }

    init(verifier: String) {
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }
}
