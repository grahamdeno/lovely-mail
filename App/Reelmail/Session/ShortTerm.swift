import Foundation

/// "Keep 2 weeks": mail he never goes back to (delivery digests, shipping updates). It leaves the inbox at once under
/// Lovely/Short-term, and after two weeks Lovely lists what has expired so one tap moves it to Gmail's Trash
/// (kept 30 more days). A safety net instead of deleting right away. Lovely never trashes on a timer by itself:
/// every move to Trash waits for the owner's tap. Pure here, so it is tested.
enum ShortTerm {
    static let label = "Lovely/Short-term"
    static let keepDays = 14
    static let limit = 300
    /// How often Home asks Gmail how many have expired.
    static let checkEvery: TimeInterval = 6 * 3600

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
        lines.append("After \(keepDays) days Lovely lists what has expired, and one tap moves it to Trash. Nothing is deleted before you tap.")
        return ActionPreview(kind: sender == nil ? .label : .filter,
                             title: sender == nil ? "Keep 2 weeks" : "Always keep 2 weeks", lines: lines)
    }
}
