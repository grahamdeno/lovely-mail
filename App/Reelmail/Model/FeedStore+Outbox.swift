import Foundation

extension FeedStore {
    var outbox: Outbox { Outbox(account: account ?? "demo", defaults: triageDefaults) }

    /// Changes waiting for a fresh tap (filing, archiving) from an earlier visit.
    var waitingChanges: [OutboxOp] { _ = outboxVersion; return outbox.ops.filter { !$0.finishesByItself && $0.created < AppLaunch.at } }

    func outboxAdd(_ ops: [OutboxOp]) { guard mode == .gmail, !ops.isEmpty else { return }; outbox.add(ops); outboxVersion &+= 1 }
    func outboxDone(_ id: String) { outbox.remove(id: id); outboxVersion &+= 1 }
    func outboxCancel(batch: String) { outbox.remove(batch: batch); outboxVersion &+= 1 }

    /// Trash and mark-read left over from before (closed app, no signal): finish them now. Refusals put the mail back.
    func replayAutomaticChanges() async {
        guard mode == .gmail else { return }
        let ops = outbox.ops.filter { $0.finishesByItself && $0.created < AppLaunch.at }
        guard !ops.isEmpty else { return }
        let gmail = self.gmail
        await undo.keepAlive { [self] in
            for op in ops {
                do {
                    if op.kind == .trash { try await gmail.trash(messageID: op.messageID) }
                    else { try await gmail.markRead(messageID: op.messageID) }
                    outboxDone(op.id)
                } catch let error where NetworkRetry.isTransient(error) {
                    return   // still offline: try again next time
                } catch {
                    outboxDone(op.id)
                    if op.kind == .trash, let post = sessionPost(op.messageID) { unhide(post) }
                }
            }
        }
    }

    /// Filing and archiving from before, with the owner's fresh tap on "Finish them".
    func finishWaitingChanges(confirmed: ConfirmedAction) {
        let ops = waitingChanges
        guard let actions, !ops.isEmpty else { return }
        let gmail = self.gmail
        Task {
            await undo.keepAlive { [self] in
                var labelIDs: [String: String] = [:]
                var failed = 0
                for op in ops {
                    do {
                        if op.kind == .file {
                            var ids: [String] = []
                            for name in op.labels {
                                if let known = labelIDs[name] { ids.append(known) }
                                else { let id = try await actions.ensureLabel(name, confirmed: confirmed); labelIDs[name] = id; ids.append(id) }
                            }
                            try await actions.file(messageID: op.messageID, labelIDs: ids, removeFromInbox: true, confirmed: confirmed)
                        } else {
                            try await actions.archive(messageID: op.messageID, confirmed: confirmed)
                        }
                        try await gmail.markRead(messageID: op.messageID)
                        outboxDone(op.id)
                    } catch let error where NetworkRetry.isTransient(error) {
                        failed += 1
                    } catch {
                        failed += 1
                        outboxDone(op.id)
                        if let post = sessionPost(op.messageID) { unhide(post) }
                    }
                }
                if failed > 0 { errorMessage = "\(failed) change\(failed == 1 ? "" : "s") did not reach Gmail yet." }
            }
        }
    }

    /// "Put them back": forget the waiting changes and show that mail again.
    func dropWaitingChanges() {
        for op in waitingChanges {
            if let post = sessionPost(op.messageID) { unhide(post); if op.kind == .file || op.kind == .archive { _ = setUnread(post.id, true) } }
            outboxDone(op.id)
        }
        persist()
    }
}
