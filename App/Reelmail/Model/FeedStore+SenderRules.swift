import Foundation

/// Rules for a whole sender, made in Gmail so they hold everywhere, not just in Lovely:
/// - "Always put away": a Gmail filter files new mail from the sender under a Lovely category and skips the inbox.
/// - "Screen out": a Gmail filter files new mail under Lovely/Screened Out and skips the inbox; Lovely hides the sender too.
/// Both also move the sender's mail now in the inbox. Nothing is deleted. Each waits for the owner's tap on a preview,
/// is held 10 seconds for Undo, and the filter can be removed in Settings > Gmail filters. Filters: approved Nov 4, 2026.
extension FeedStore {

    /// What "Always put away" and "Screen out" would do, as the button's preview.
    static func senderRulePreview(sender: String, label: String, inboxCount: Int, screenOut: Bool) -> ActionPreview {
        let shownLabel = label.replacingOccurrences(of: LovelyLabels.prefix, with: "")
        var lines = ["Creates a Gmail filter: new mail from \(sender) skips your inbox and goes to \(screenOut ? "Screened Out" : shownLabel)."]
        if inboxCount > 0 {
            lines.append("Also moves the \(inboxCount) email\(inboxCount == 1 ? "" : "s") from them now in your inbox there\(screenOut ? "" : " and marks them read").")
        }
        lines.append("Filters match the exact address, so other mail from the same company is not affected.")
        lines.append(screenOut ? "Nothing is deleted. After \(ScreenedOut.trashAfterDays) days Lovely offers to move them to Trash." : "Nothing is deleted.")
        lines.append("Remove it any time in Settings > Gmail filters.")
        return ActionPreview(kind: .filter, title: screenOut ? "Screen out \(sender)" : "Always put away in \(shownLabel)", lines: lines)
    }

    /// Inbox mail from this exact address that Lovely has loaded.
    func inboxPosts(from sender: String) -> [Post] {
        let key = sender.lowercased()
        return posts.filter { $0.email.from.email.lowercased() == key && !hidden.contains($0.id) }
    }

    /// Makes the Gmail filter (unless Lovely already made one for this sender and label) and files the listed mail.
    /// The mail leaves Lovely at once; Gmail changes after the 10-second Undo. `finished` gets nil on success.
    func applySenderRule(sender: String, label: String, posts moving: [Post], markRead: Bool, screenOut: Bool,
                         confirmed: ConfirmedAction, finished: @escaping @MainActor (Error?) -> Void = { _ in }) {
        let key = sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let actions, ForwardAllowlist.isAddress(key), label.hasPrefix(LovelyLabels.prefix) else {
            errorMessage = actions == nil ? "Connect Gmail first." : "Lovely can only make this rule for a single address."
            return
        }
        if screenOut { _ = rules.setSender(key, destination: .filtered) }
        for post in moving {
            if markRead, setUnread(post.id, false) { countDone(+1) }
            hide(post)
        }
        persist()
        let restore: @MainActor () -> Void = { [self] in
            if screenOut { _ = rules.setSender(key, destination: nil) }
            for post in moving {
                if markRead, setUnread(post.id, true) { countDone(-1) }
                unhide(post)
            }
            persist()
        }
        let gmail = self.gmail
        let title = screenOut ? "Screened out \(key)" : "Always: \(key) to \(label.replacingOccurrences(of: LovelyLabels.prefix, with: ""))"
        undo.enqueue(title: title, work: {
            let labelID = try await actions.ensureLabel(label, confirmed: confirmed)
            if !FilterRegistry().filters.contains(where: { $0.sender == key && $0.label == labelID }) {
                _ = try await actions.createFilter(sender: key, forwardTo: nil, labelID: labelID, skipInbox: true, confirmed: confirmed)
            }
            for post in moving.prefix(100) {
                try await actions.file(messageID: post.id, labelID: labelID, removeFromInbox: true, confirmed: confirmed)
                if markRead { try await gmail.markRead(messageID: post.id) }
            }
        }, finished: { [self] error in
            if let error {
                restore()
                errorMessage = "The Gmail rule was not made. \(error.localizedDescription)"
            }
            finished(error)
        }, undone: { restore() })
    }
}
