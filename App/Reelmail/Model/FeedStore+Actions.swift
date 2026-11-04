import Foundation

/// The flows behind the preview sheets. Each one is called only with a ConfirmedAction (or, for Trash, after a preview tap).
extension FeedStore {
    /// One request to the sender's own unsubscribe address (RFC 8058). Sends no email.
    func unsubscribe(url: URL, sender: String) async {
        do {
            let (_, response) = try await URLSession.shared.data(for: OneClickUnsubscribe.request(url))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                ActivityLog().record(kind: "unsubscribe", summary: "Unsubscribed from \(sender) at \(url.host ?? "its own address")")
                errorMessage = "Unsubscribe sent to \(sender)."
            } else { errorMessage = "\(sender) did not accept the unsubscribe (HTTP \(code))." }
        } catch { errorMessage = "The unsubscribe could not be sent. \(error.localizedDescription)" }
    }

    /// How many messages the Shoebox backfill would forward for a sender.
    func shoeboxBackfillCount(sender: String) async -> Int {
        (try? await gmail.listMessageIDs(query: ShoeboxRule.backfillQuery(sender: sender), limit: 50).ids.count) ?? 0
    }

    /// A standing filter that forwards one sender to Shoebox, then a forward of the last 10 days. Held 10 seconds for Undo.
    func sendSenderToShoebox(sender: String, shoebox: String, confirmed: ConfirmedAction) {
        guard let actions else { errorMessage = "Connect Gmail first."; return }
        undo.enqueue(title: "Shoebox rule for \(sender)", work: { [self] in
            _ = try await actions.createFilter(sender: sender, forwardTo: shoebox, labelID: nil, confirmed: confirmed)
            let ids = try await gmail.listMessageIDs(query: ShoeboxRule.backfillQuery(sender: sender), limit: 50).ids
            for id in ids {
                let e = try await gmail.getMessage(id: id, account: account)
                try await actions.forward(from: e.from.name + " <" + e.from.email + ">", subject: e.subject, date: e.date, text: e.body, to: shoebox, confirmed: confirmed)
            }
        }, finished: { [self] error in
            errorMessage = error.map { "The Shoebox rule was not completed. \($0.localizedDescription)" } ?? "Shoebox rule added for \(sender)."
        })
    }

    /// Screened Out: files a first-time sender's messages under Lovely/Screened Out and out of the inbox. Nothing is deleted.
    func decline(_ candidate: ScreenedOut.Candidate, confirmed: ConfirmedAction) async {
        guard let actions else { errorMessage = "Connect Gmail first."; return }
        do {
            let label = try await actions.ensureLabel(ScreenedOut.label, confirmed: confirmed)
            for id in candidate.messageIDs { try await actions.file(messageID: id, labelID: label, removeFromInbox: true, confirmed: confirmed) }
            await load()
        } catch { errorMessage = "That could not be declined. \(error.localizedDescription)" }
    }

    func accept(_ candidate: ScreenedOut.Candidate) { ScreenedOut.approve(candidate.address) }

    /// Screened-out mail older than 30 days.
    func oldScreenedOutIDs() async -> [String] {
        (try? await gmail.listMessageIDs(query: ScreenedOut.trashQuery, limit: 200).ids) ?? []
    }

    /// Moves old screened-out mail to Gmail's Trash (recoverable for 30 days) after a preview tap.
    func trashScreenedOut(_ ids: [String]) async {
        var moved = 0
        for id in ids { if (try? await gmail.trash(messageID: id)) != nil { moved += 1 } }
        ActivityLog().record(kind: "trash", summary: "Moved \(moved) old screened-out messages to Trash")
        errorMessage = "Moved \(moved) old screened-out message\(moved == 1 ? "" : "s") to Trash."
    }
}
