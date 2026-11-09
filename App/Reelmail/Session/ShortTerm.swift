import Foundation

/// "Keep 2 weeks": mail he never goes back to (delivery digests, shipping updates). It leaves the inbox at once under
/// Lovely/Short-term, and after two weeks Lovely moves it to Gmail's Trash (kept 30 more days): a safety net instead
/// of deleting right away. Automatic by default (owner approved Nov 9, 2026); with the setting off, Lovely lists what
/// has expired and waits for a tap. Starred mail and mail from people he writes to are never trashed. Pure here, so it is tested.
enum ShortTerm {
    static let label = "Lovely/Short-term"
    static let keepDays = 14
    static let limit = 300
    /// How often Home asks Gmail how many have expired.
    static let checkEvery: TimeInterval = 6 * 3600

    /// "Move expired short-term mail to Trash automatically", per account. On unless he turns it off.
    static func autoKey(account: String) -> String { "lovely.shortTerm.auto." + account.lowercased() }
    static func autoTrash(account: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: autoKey(account: account)) as? Bool ?? true
    }

    /// Gmail's search name for the label: lowercase, "/" and spaces become "-".
    static var searchLabel: String {
        label.lowercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
    }

    static func query(keepDays: Int = keepDays) -> String {
        "label:\(searchLabel) older_than:\(keepDays)d -in:trash -is:starred"
    }

    /// Never clean up mail from someone he writes to, even if it was marked short-term.
    static func keep(_ stub: MessageStub, knownPeople: Set<String>) -> Bool {
        !knownPeople.contains(stub.fromAddress.lowercased())
    }

    static func preview(sender: String?) -> ActionPreview {
        var lines = ["Takes it out of your inbox, marks it read and labels it Short-term in Gmail."]
        if let sender {
            lines = ["Creates a Gmail filter: new mail from \(sender) skips your inbox and is labeled Short-term.",
                     "Also moves their email now in your inbox there and marks it read.",
                     "Filters match the exact address. Remove it any time in Settings > Gmail filters."]
        }
        lines.append("After \(keepDays) days Lovely moves it to Trash, where Gmail keeps it 30 more days. Starred mail is never moved. Change this in Settings > Short-term mail.")
        return ActionPreview(kind: sender == nil ? .label : .filter,
                             title: sender == nil ? "Keep 2 weeks" : "Always keep 2 weeks", lines: lines)
    }
}
