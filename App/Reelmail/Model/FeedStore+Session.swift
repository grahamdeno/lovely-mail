import Foundation

/// Sprint 7 inbox session: the flows behind the session screens. Rules live in Session/; this file only
/// connects them to the mail Lovely already loaded and to the Gmail actions. See docs/sprint7-design.md.
extension FeedStore {
    /// Kids from Settings, for Kids sub-drawers.
    var sessionKids: [KidProfile] { InsightSettings().load().kids }

    /// Where the owner filed each sender, per account.
    var drawerMemory: DrawerMemory { DrawerMemory.load(account: account ?? "demo") }

    /// Everything waiting on you, then the unread to-do (oldest first). The session plan sorts it again.
    var sessionCandidates: [Post] {
        cached("sessionCandidates", [hidden, laterUntil]) {
            let d = digest
            var seen = Set<String>()
            return (d.waiting + d.todo).filter { !hidden.contains($0.id) && seen.insert($0.id).inserted }
        }
    }

    /// Older mail: read, still in the inbox, not waiting on you. Oldest first, one page at a time.
    static let backlogPage = 50
    /// Home reads this on every redraw, so it is rebuilt only when the mail changes (it filters and sorts everything loaded).
    var backlogCandidates: [Post] {
        cached("backlogCandidates", [hidden, laterUntil]) {
            let current = Set(sessionCandidates.map(\.id))
            return posts.filter { !$0.email.isUnread && !$0.email.isFromMe && !hidden.contains($0.id) && !current.contains($0.id) }
                .sorted { $0.email.date < $1.email.date }
        }
    }

    /// A fresh plan from what is loaded now.
    func makeSessionPlan(modelGuesses: [String: DrawerGuess] = [:], backlog: Bool = false) -> SessionPlan {
        let firstTime = Set(newSenders.map { $0.address.lowercased() })
        let source = backlog ? Array(backlogCandidates.prefix(Self.backlogPage)) : sessionCandidates
        let messages = source.map { post in
            SessionMessage(post: post, assessment: assessment(for: post),
                           isFirstTimeSender: firstTime.contains(post.email.from.email.lowercased()))
        }
        return SessionPlanner.plan(messages, memory: drawerMemory, kids: sessionKids,
                                   promises: backlog ? [] : promises.map(CarriedPromise.init), modelGuesses: modelGuesses, backlog: backlog,
                                   households: InsightSettings().load().households)
    }

    func sessionPost(_ id: String) -> Post? { posts.first { $0.id == id } }

    /// Tags for an item filed in a different category than suggested (topics depend on the category).
    func sessionTags(_ item: SessionItem, choice: DrawerChoice?) -> [MailTag] {
        SessionPlanner.tags(for: item.message, choice: choice,
                            context: TagContext(households: InsightSettings().load().households, kids: sessionKids))
    }

    /// The move for an item: its category and tags (recomputed when the owner picks another category).
    func sessionMove(_ item: SessionItem, choice: DrawerChoice?) -> SessionMove {
        guard let choice else { return SessionMove(messageID: item.id, drawer: nil) }
        let tags = choice == item.drawer?.choice ? item.tags : sessionTags(item, choice: choice)
        return SessionMove(messageID: item.id, drawer: choice, tags: tags)
    }

    /// What a put-away covers, for the button that confirms it.
    static func putAwayPreview(_ moves: [SessionMove]) -> ActionPreview {
        let filed = moves.filter { $0.drawer != nil }.count
        let archived = moves.count - filed
        var lines: [String] = []
        if filed > 0 {
            let tagCount = Set(moves.flatMap(\.tags)).count
            lines.append("Files \(filed) under Lovely categories\(tagCount > 0 ? " and \(tagCount) tag\(tagCount == 1 ? "" : "s")" : ""), marks them read and takes them out of the inbox.")
        }
        if archived > 0 { lines.append("Marks \(archived) read and takes them out of the inbox.") }
        lines.append("Nothing is deleted. You have 10 seconds to undo.")
        return ActionPreview(kind: .label, title: moves.count == 1 ? "Put away" : "Put away \(moves.count)", lines: lines)
    }

    /// Puts mail away: drawer label (or none for archive), read, out of the inbox. It leaves the session and Home at once;
    /// Gmail changes after the 10-second Undo, like a send. Drawer choices are remembered at once so the next item benefits.
    /// `finished` reports how many Gmail accepted.
    func putAway(_ moves: [SessionMove], confirmed: ConfirmedAction, finished: @escaping @MainActor (Int, Error?) -> Void = { _, _ in },
                onReturn: @escaping @MainActor ([String]) -> Void = { _ in }) {
        guard !moves.isEmpty else { return }
        var memory = drawerMemory
        for move in moves {
            if let drawer = move.drawer, let post = sessionPost(move.messageID) { memory.remember(drawer, for: post.email.from.email) }
        }
        memory.save(account: account ?? "demo")
        var trashMemory = sessionTrashMemory
        for move in moves { if let post = sessionPost(move.messageID) { trashMemory.forget(post.email.from.email) } }
        trashMemory.save(account: account ?? "demo")

        let posts = moves.compactMap { sessionPost($0.messageID) }
        for post in posts {
            if setUnread(post.id, false) { countDone(+1, id: post.id) }
            hide(post)
        }
        persist()

        let title = moves.count == 1 ? Self.putAwayTitle(moves[0], post: posts.first) : "Put away \(moves.count) emails"
        let actions = self.actions
        let gmail = self.gmail
        let restore: @MainActor (Set<String>) -> Void = { [self] ids in
            for post in posts where ids.contains(post.id) {
                if setUnread(post.id, true) { countDone(-1, id: post.id) }
                unhide(post)
            }
            persist()
        }
        undo.enqueue(title: title, work: { [self] in
            guard let actions else { finished(moves.count, nil); return }  // demo mail: local only
            var labelIDs: [String: String] = [:]
            var failed = Set<String>()
            var lastError: Error?
            for move in moves {
                do {
                    if let drawer = move.drawer {
                        var ids: [String] = []
                        for name in [drawer.labelName] + move.tags.map(\.labelName) {
                            if let known = labelIDs[name] { ids.append(known) }
                            else { let id = try await actions.ensureLabel(name, confirmed: confirmed); labelIDs[name] = id; ids.append(id) }
                        }
                        try await actions.file(messageID: move.messageID, labelIDs: ids, removeFromInbox: true, confirmed: confirmed)
                    } else {
                        try await actions.archive(messageID: move.messageID, confirmed: confirmed)
                    }
                    try await gmail.markRead(messageID: move.messageID)
                } catch {
                    failed.insert(move.messageID); lastError = error
                }
            }
            // Only the ones Gmail refused come back; the rest stay put away.
            if let lastError {
                restore(failed)
                onReturn(Array(failed))
                changeFailed(lastError)
                errorMessage = failed.count == moves.count
                    ? "Gmail did not put that away, so it is back on your to-do. \(lastError.localizedDescription)"
                    : "\(failed.count) of \(moves.count) are back on your to-do; Gmail refused them. \(lastError.localizedDescription)"
            }
            finished(moves.count - failed.count, lastError)
        }, undone: { restore(Set(posts.map(\.id))); onReturn(posts.map(\.id)) })
    }

    // MARK: Trash in a session

    /// Senders he trashed before in a session; Lovely offers Trash first for them.
    var sessionTrashMemory: TrashMemory { TrashMemory.load(account: account ?? "demo") }

    /// Moves one message to Gmail's Trash with the app-wide 10-second Undo (the Trash approved 2026-11-01; never a permanent
    /// delete) and remembers the sender so the next one from them offers Trash first.
    func sessionTrash(_ post: Post) {
        var memory = sessionTrashMemory
        memory.remember(post.email.from.email)
        memory.save(account: account ?? "demo")
        Task { await moveToTrash(post) }
    }

    static func putAwayTitle(_ move: SessionMove, post: Post?) -> String {
        let what = post.map { $0.email.subject.isEmpty ? $0.email.from.name : $0.email.subject } ?? "Email"
        return move.drawer.map { "Filed in \($0.title): \(what)" } ?? "Archived: \(what)"
    }

    /// Lovely sends a reply itself only to one person with nobody copied, as the draft sheet does. Otherwise Gmail.
    func canSendSessionReply(_ post: Post) -> Bool {
        actions != nil && !post.email.isFromMe && ReplyRecipients.reply(post.email).to.count == 1 && post.email.cc.isEmpty
    }

    /// The filing half of "Send and put away": shown on the same button as the send.
    static func replyFilingPreview(_ post: Post, drawer: DrawerChoice?) -> ActionPreview {
        ActionPreview(kind: .label, title: "Put away after sending",
                      lines: [drawer.map { "Files it in \($0.title), marks it read and takes it out of the inbox." } ?? "Marks it read and takes it out of the inbox."])
    }

    static func replyPreview(_ post: Post, body: String) -> ActionPreview {
        ActionPreview(kind: .send, title: "Send to \(post.email.from.firstName)",
                      lines: ["Subject: " + GmailCompose.replySubject(post.email.subject), body],
                      recipients: [post.email.from.email])
    }

    /// Sends the reply, then puts the message away in `drawer` (People by default). Held 10 seconds for Undo; one Undo covers both.
    /// If the send fails, the text is kept for the Reply sheet and nothing is put away.
    func sendSessionReply(_ post: Post, body: String, drawer: DrawerChoice?, tags: [MailTag] = [], confirmed: ConfirmedAction, filing: ConfirmedAction,
                          finished: @escaping @MainActor (Error?) -> Void = { _ in }, onReturn: @escaping @MainActor ([String]) -> Void = { _ in }) {
        guard let actions, canSendSessionReply(post) else { errorMessage = "Reply in Gmail for this one."; return }
        let to = post.email.from.email, subject = GmailCompose.replySubject(post.email.subject), thread = post.email.threadId
        if let drawer {
            var memory = drawerMemory; memory.remember(drawer, for: to); memory.save(account: account ?? "demo")
        }
        if setUnread(post.id, false) { countDone(+1, id: post.id) }
        hide(post); persist()
        let restore: @MainActor () -> Void = { [self] in
            if setUnread(post.id, true) { countDone(-1, id: post.id) }
            unhide(post); persist()
        }
        let gmail = self.gmail
        undo.enqueue(title: "Sending to \(post.email.from.firstName)", work: { [self] in
            do {
                try await actions.sendReply(to: to, subject: subject, body: body, threadID: thread, inReplyTo: nil, confirmed: confirmed)
            } catch {
                restore(); savedDrafts[post.id] = body; onReturn([post.id])
                errorMessage = "Not sent. Your text is saved; tap Reply to try again. \(error.localizedDescription)"
                finished(error); return
            }
            // The reply went. Filing is a bonus: if it fails, the message stays answered and read, just still in the inbox.
            do {
                if let drawer {
                    var ids: [String] = []
                    for name in [drawer.labelName] + tags.map(\.labelName) { ids.append(try await actions.ensureLabel(name, confirmed: filing)) }
                    try await actions.file(messageID: post.id, labelIDs: ids, removeFromInbox: true, confirmed: filing)
                } else {
                    try await actions.archive(messageID: post.id, confirmed: filing)
                }
                try await gmail.markRead(messageID: post.id)
            } catch {
                errorMessage = "Sent. Gmail did not file it, so it is still in your inbox."
            }
            finished(nil)
        }, undone: { [self] in restore(); savedDrafts[post.id] = body; onReturn([post.id]) })
    }
}

/// One message and where it goes. `drawer` nil means archive without a label.
struct SessionMove: Hashable, Sendable {
    var messageID: String
    var drawer: DrawerChoice?
    /// Filed with the category: type, topic, property, person, tax year.
    var tags: [MailTag] = []
}

// MARK: Clean up old login codes (shown before anything moves)

extension FeedStore {
    /// Finds old account notices in Gmail and returns them for the owner to look at. Changes nothing.
    func findOldAccountNotices(ageDays: Int = AccountsCleanup.defaultAgeDays) async throws -> [MessageStub] {
        guard mode == .gmail else { return [] }
        let (ids, _, _) = try await gmail.listMessageIDs(query: AccountsCleanup.query(ageDays: ageDays), limit: AccountsCleanup.limit)
        let known = Set(people.map { $0.email.lowercased() })
        var out: [MessageStub] = []
        for id in ids {
            if let stub = try? await gmail.getMetadata(id: id), AccountsCleanup.keep(stub, knownPeople: known) { out.append(stub) }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Moves the listed messages to Gmail's Trash after the 10-second Undo. Gmail keeps Trash for 30 days.
    func trashOldAccountNotices(_ stubs: [MessageStub], finished: @escaping @MainActor (Int) -> Void = { _ in }) {
        guard !stubs.isEmpty else { return }
        let gmail = self.gmail
        undo.enqueue(title: "Moving \(stubs.count) old login emails to Trash", work: { [self] in
            var done = 0
            for stub in stubs {
                do { try await gmail.trash(messageID: stub.id); done += 1 } catch { errorMessage = "Some were not moved to Trash. \(error.localizedDescription)" }
            }
            finished(done)
        }, undone: {})
    }
}
