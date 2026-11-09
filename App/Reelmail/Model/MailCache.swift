import CryptoKit
import Foundation

/// On-device cache of the last import plus the summaries made for it, one file per account.
/// Lets the app open instantly and keeps cards stable between launches.
/// Stored in Application Support with complete file protection (encrypted while the phone is locked),
/// excluded from backups. Deleted on disconnect. Never contains tokens.
struct MailCache: Codable, Equatable {
    var snapshot: MailboxSnapshot
    var summaries: [String: EmailSummary] = [:]
    /// Message ids hidden locally ("Hide in Lovely"). Hiding never changes Gmail.
    var hidden: Set<String> = []
    /// Message ids opened in the app. Gmail's own read state is not changed.
    var seen: Set<String> = []
    /// On-device verdicts for You said you would / Waiting on them. Optional so older caches still decode.
    var verdicts: [String: Bool]? = nil

    /// Stable, non-reversible id for keying preferences without writing the address around.
    static func accountKey(_ address: String) -> String {
        let digest = SHA256.hash(data: Data(address.lowercased().utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads and writes `MailCache` files. Pure file IO so FeedStore stays testable with a temp directory.
struct MailCacheStore {
    let directory: URL

    static var standard: MailCacheStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return MailCacheStore(directory: base.appendingPathComponent("Reelmail/mail", isDirectory: true))
    }

    private func url(for account: String) -> URL {
        directory.appendingPathComponent("account-\(MailCache.accountKey(account)).json")
    }

    /// The cache for the account that was signed in last, if any.
    func loadCurrent() -> MailCache? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let newest = files.filter { $0.pathExtension == "json" }.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        guard let newest, let data = try? Data(contentsOf: newest) else { return nil }
        return try? JSONDecoder().decode(MailCache.self, from: data)
    }

    func save(_ cache: MailCache) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cache)
        let target = url(for: cache.snapshot.account)
        try data.write(to: target, options: [.atomic, .completeFileProtectionUnlessOpen])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = target; try? mutable.setResourceValues(values)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
