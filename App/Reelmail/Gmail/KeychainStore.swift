import Foundation
import Security

/// OAuth tokens live in the Keychain, this device only. Never in UserDefaults or logs.
struct KeychainStore {
    let service: String
    let account: String

    static let googleTokens = KeychainStore(service: "com.grahamdeno.reelmail.google", account: "oauth")

    func save(_ data: Data) {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct OAuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}
