import SwiftUI

/// The inbox session (Sprint 7): unread mail one decision at a time. Each screen has one main button.
/// Gmail stays the place for heavy email work; this is the calm front end.
struct SessionView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var model: SessionModel?

    var body: some View {
        VStack(spacing: 0) {
            if let model {
                SessionHeader(model: model, close: close)
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CalmStyle.background)
        .foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .toolbar(.hidden, for: .navigationBar)
        .task { if model == nil { model = SessionModel(plan: store.makeSessionPlan()) } }
    }

    @ViewBuilder private func content(_ m: SessionModel) -> some View {
        switch m.phase {
        case .start: SessionStartScreen(model: m)
        case .item(let id): SessionItemScreen(model: m, itemID: id).id(id)
        case .batch: SessionBatchScreen(model: m)
        case .reading: SessionReadingScreen(model: m)
        case .wrap: SessionWrapScreen(model: m, close: close)
        }
    }

    private func close() { if !router.path.isEmpty { router.path.removeLast() } }
}

// MARK: Header

struct SessionHeader: View {
    let model: SessionModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inbox session").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(CalmStyle.secondary)
                    .accessibilityLabel("Close session").accessibilityIdentifier("session.close")
            }
            if model.plan.count > 0 {
                HStack {
                    Text("\(model.progress.dealtWith) of \(model.plan.count)").font(.caption.weight(.semibold))
                    Spacer()
                    if model.progress.dealtWith < model.plan.count {
                        Text("about \(remainingMinutes) min").font(.caption).foregroundStyle(CalmStyle.secondary)
                    }
                }
                ProgressView(value: model.progress.fraction).tint(CalmStyle.blue)
                    .accessibilityLabel("\(model.progress.dealtWith) of \(model.plan.count) handled")
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }

    private var remainingMinutes: Int {
        let left = model.plan.count - model.progress.dealtWith
        guard model.plan.count > 0 else { return 0 }
        return max(1, Int((Double(model.plan.estimatedMinutes) * Double(left) / Double(model.plan.count)).rounded(.up)))
    }
}

// MARK: Start

struct SessionStartScreen: View {
    let model: SessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.isEmpty {
                        Text("Nothing to go through").font(.largeTitle.weight(.bold))
                        Text("Your inbox is clear. New mail will be here next time.").foregroundStyle(CalmStyle.secondary)
                    } else {
                        Text("\(model.plan.count) to go through").font(.largeTitle.weight(.bold))
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(SessionGroup.allCases, id: \.self) { group in
                                let n = model.plan.items.filter { $0.group == group }.count
                                if n > 0 {
                                    HStack {
                                        Text(group.title)
                                        Spacer()
                                        Text("\(n)").font(.body.weight(.semibold))
                                    }
                                }
                            }
                        }
                        .padding(16).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                        Text("About \(model.plan.estimatedMinutes) min. Each one ends up answered, dated or filed, and out of your inbox.")
                            .font(.callout).foregroundStyle(CalmStyle.secondary)
                    }
                    if !model.plan.carried.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STILL OPEN FROM BEFORE").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                            ForEach(model.plan.carried.prefix(3), id: \.id) { p in
                                Text("You told \(p.recipient): \u{201C}\(p.text)\u{201D}").font(.callout).lineLimit(2)
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(20)
            }
            if !model.isEmpty {
                Button("Start") { model.start() }
                    .buttonStyle(SessionButtonStyle()).padding(20)
                    .accessibilityIdentifier("session.start")
            }
        }
    }
}

// MARK: One item

struct SessionItemScreen: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    let model: SessionModel
    let itemID: String

    private enum Mode { case decide, drawers, reply }
    @State private var mode: Mode = .decide
    @State private var draft = ""
    @State private var drafting = false
    @State private var calendar: SessionCalendarBox?
    @State private var pendingDateMove: SessionMove?
    @State private var pendingDateApproval: ConfirmedAction?

    var body: some View {
        if let item = model.item(itemID), let post = store.sessionPost(itemID) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SessionMailCard(item: item, post: post) { router.open(.email(post.id)) }
                        switch mode {
                        case .decide: EmptyView()
                        case .drawers: drawerGrid(item)
                        case .reply: replyEditor
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                }
                VStack(spacing: 10) {
                    switch mode {
                    case .decide: decideActions(item, post)
                    case .drawers: secondaryRow(item, post, showOtherDrawer: false)
                    case .reply: replyActions(item, post)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                .background(CalmStyle.background)
            }
            .onAppear { if case .decide = item.suggestion, item.drawer == nil { mode = .drawers } }
            .sheet(item: $calendar, onDismiss: finishDate) { box in CalendarEventSheet(draft: box.draft).ignoresSafeArea() }
        } else {
            Color.clear.task { model.drop(itemID) }
        }
    }

    // MARK: Decide

    @ViewBuilder private func decideActions(_ item: SessionItem, _ post: Post) -> some View {
        switch item.suggestion {
        case .reply:
            Button("Reply") { openReply(post) }.buttonStyle(SessionButtonStyle()).accessibilityIdentifier("session.reply")
        case .putAway(let d):
            putAwayButton(item, d)
        case .addDatesThenPutAway(let d):
            dateButton(item, post, d)
        case .archive:
            archiveButton(item, prominent: true)
        case .decide:
            if let d = item.drawer?.choice { putAwayButton(item, d) }
            else { Button("Choose a drawer") { mode = .drawers }.buttonStyle(SessionButtonStyle()) }
        }
        secondaryRow(item, post, showOtherDrawer: true)
    }

    private func secondaryRow(_ item: SessionItem, _ post: Post, showOtherDrawer: Bool) -> some View {
        HStack(spacing: 8) {
            if item.suggestion != .reply, item.message.isPerson || item.message.section == .notes {
                small("Reply", id: "session.replyInstead") { openReply(post) }
            }
            if showOtherDrawer { small("Other drawer", id: "session.otherDrawer") { mode = .drawers } }
            small("Leave unread", id: "session.leaveUnread") { model.record(item.id, .leftUnread); model.advance() }
            small("Skip", id: "session.skip") { model.skip(item.id) }
        }
    }

    private func small(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(CalmStyle.blue)
            .accessibilityIdentifier(id)
    }

    private func putAwayButton(_ item: SessionItem, _ d: DrawerChoice) -> some View {
        let move = SessionMove(messageID: item.id, drawer: d)
        return SessionConfirmButton(title: "Put away in \(d.title)", previews: [FeedStore.putAwayPreview([move])],
                                    identifier: "session.putAway") { approvals in
            put(move, approvals[0])
        }
    }

    private func archiveButton(_ item: SessionItem, prominent: Bool) -> some View {
        let move = SessionMove(messageID: item.id, drawer: nil)
        return SessionConfirmButton(title: "Archive, no drawer", previews: [FeedStore.putAwayPreview([move])],
                                    prominent: prominent, identifier: "session.archive") { approvals in
            put(move, approvals[0])
        }
    }

    private func dateButton(_ item: SessionItem, _ post: Post, _ d: DrawerChoice) -> some View {
        let move = SessionMove(messageID: item.id, drawer: d)
        let first = MailDates.extract(post.email, now: Date()).first
        return SessionConfirmButton(title: first.map { "Add \(ComingUp.fullLabel($0)), then put away in \(d.title)" } ?? "Put away in \(d.title)",
                                    previews: [FeedStore.putAwayPreview([move])], identifier: "session.addDate") { approvals in
            guard let first else { put(move, approvals[0]); return }
            pendingDateMove = move; pendingDateApproval = approvals[0]
            calendar = SessionCalendarBox(draft: CalendarDraft.make(email: post.email, date: first))
        }
    }

    /// After Apple's Add Event sheet closes, the message is put away either way; the calendar is Apple's to keep.
    private func finishDate() {
        guard let move = pendingDateMove, let approval = pendingDateApproval else { return }
        pendingDateMove = nil; pendingDateApproval = nil
        model.addedDate()
        put(move, approval)
    }

    private func put(_ move: SessionMove, _ approval: ConfirmedAction) {
        store.putAway([move], confirmed: approval, onReturn: { [model] ids in model.reopen(ids) })
        model.recordMoves([move])
        model.advance()
    }

    // MARK: Drawers

    private func drawerGrid(_ item: SessionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE DOES IT GO?").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(DrawerChoice.all(kids: store.sessionKids), id: \.self) { d in
                    let move = SessionMove(messageID: item.id, drawer: d)
                    SessionConfirmButton(title: d.title, previews: [FeedStore.putAwayPreview([move])], prominent: d == item.drawer?.choice,
                                         identifier: "session.drawer.\(d.labelName)") { approvals in put(move, approvals[0]) }
                }
            }
            archiveButton(item, prominent: false)
        }
    }

    // MARK: Reply

    private var replyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR REPLY").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .frame(minHeight: 180).scrollContentBackground(.hidden)
                    .padding(10).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("session.replyText")
                if drafting { ProgressView().padding(18) }
            }
        }
    }

    @ViewBuilder private func replyActions(_ item: SessionItem, _ post: Post) -> some View {
        let drawer = item.drawer?.choice ?? DrawerChoice(.people)
        if store.canSendSessionReply(post) {
            SessionConfirmButton(title: "Send and put away in \(drawer.title)",
                                 previews: [FeedStore.replyPreview(post, body: draft), FeedStore.replyFilingPreview(post, drawer: drawer)],
                                 enabled: !drafting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                 identifier: "session.send") { approvals in
                store.sendSessionReply(post, body: draft, drawer: drawer, confirmed: approvals[0], filing: approvals[1],
                                       onReturn: { [model] ids in model.reopen(ids) })
                model.record(item.id, .replied)
                model.advance()
            }
            Text("To \(post.email.from.email). You have 10 seconds to undo.").font(.caption).foregroundStyle(CalmStyle.secondary)
        } else {
            Button("Finish in Gmail") { openInGmail(post) }.buttonStyle(SessionButtonStyle())
            Text("Several people are on this one, so Gmail sends it.").font(.caption).foregroundStyle(CalmStyle.secondary)
        }
        HStack {
            small("Back", id: "session.replyBack") { mode = .decide }
            small("Skip", id: "session.skip") { model.skip(item.id) }
        }
    }

    private func openReply(_ post: Post) {
        mode = .reply
        guard draft.isEmpty else { return }
        if let saved = store.savedDrafts.removeValue(forKey: post.id) { draft = saved; return }
        drafting = true
        let name = store.mode == .gmail ? "" : store.me.firstName
        Task {
            let text = (try? await ReplyDrafterFactory.best().draft(replyTo: post.email, myName: name))
                ?? (try? await TemplateReplyDrafter().draft(replyTo: post.email, myName: name)) ?? ""
            if draft.isEmpty { draft = text }
            drafting = false
        }
    }

    private func openInGmail(_ post: Post) {
        let plan = ReplyRecipients.reply(post.email)
        let subject = GmailCompose.replySubject(post.email.subject)
        guard let app = GmailCompose.appURL(to: plan.toLine, subject: subject, body: draft) else { return }
        openURL(app) { accepted in
            if !accepted, let web = GmailCompose.webURL(to: plan.toLine, subject: subject, body: draft) { openURL(web) }
        }
    }
}

struct SessionCalendarBox: Identifiable {
    let draft: CalendarDraft
    var id: String { "\(draft.start.timeIntervalSince1970)-\(draft.title)" }
}

/// Who, what and when for one email. Tapping "Open the email" shows the original.
struct SessionMailCard: View {
    let item: SessionItem
    let post: Post
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CalmAvatar(person: post.email.from, size: 44, waiting: item.message.section == .waiting, organization: !item.message.isPerson)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.email.from.name).font(.headline).lineLimit(1)
                    Text(HomeDigest.age(of: post.email.date, now: Date()) + (post.email.isUnread ? " · unread" : ""))
                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                }
                Spacer()
            }
            if !post.email.subject.isEmpty {
                Text(post.email.subject).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            if let ask = item.message.ask {
                Text("\u{201C}\(ask)\u{201D}").font(.body).foregroundStyle(CalmStyle.roseInk).fixedSize(horizontal: false, vertical: true)
            } else if !post.summary.blurb.isEmpty {
                Text(post.summary.blurb).font(.body).foregroundStyle(CalmStyle.secondary).lineLimit(5)
            }
            if let reason = item.drawer?.reason, item.suggestion != .reply {
                Label(reason, systemImage: "tray.and.arrow.down").font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            Button("Open the email", action: open).font(.subheadline.weight(.medium)).foregroundStyle(CalmStyle.blue)
                .frame(minHeight: 44).accessibilityIdentifier("session.openEmail")
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 20))
        .padding(.top, 4)
    }
}

// MARK: Batch

struct SessionBatchScreen: View {
    @Environment(FeedStore.self) private var store
    @Bindable var model: SessionModel
    @State private var calendar: SessionCalendarBox?

    var body: some View {
        let page = model.batchPage
        let moves = model.batchMoves
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(page.count == 1 ? "One quick one" : "\(page.count) quick ones").font(.title.weight(.bold))
                    Text("Each goes in its drawer, marked read and out of your inbox. Tap a drawer to change it.")
                        .font(.callout).foregroundStyle(CalmStyle.secondary)
                    VStack(spacing: 0) {
                        ForEach(page) { item in
                            row(item)
                            if item.id != page.last?.id { Divider().overlay(CalmStyle.divider) }
                        }
                    }
                    .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            VStack(spacing: 10) {
                SessionConfirmButton(title: moves.count == page.count ? "Put away all \(moves.count)" : "Put away \(moves.count)",
                                     previews: [FeedStore.putAwayPreview(moves)], enabled: !moves.isEmpty,
                                     identifier: "session.batch.confirm") { approvals in
                    store.putAway(moves, confirmed: approvals[0], onReturn: { [model] ids in model.reopen(ids) })
                    model.finishBatchPage(moves)
                }
                Button(moves.isEmpty ? "Continue" : "Leave these unread") { model.finishBatchPage([]) }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44).foregroundStyle(CalmStyle.blue)
                    .accessibilityIdentifier("session.batch.skip")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
        .sheet(item: $calendar) { box in CalendarEventSheet(draft: box.draft).ignoresSafeArea() }
    }

    private func row(_ item: SessionItem) -> some View {
        let leftOut = model.batchLeftOut.contains(item.id)
        let post = store.sessionPost(item.id)
        let date = post.flatMap { MailDates.extract($0.email, now: Date()).first }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.message.fromName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.message.subject).font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                if let date, let post {
                    Button { calendar = SessionCalendarBox(draft: CalendarDraft.make(email: post.email, date: date)) } label: {
                        Label("Add \(ComingUp.fullLabel(date))", systemImage: "calendar.badge.plus").font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(CalmStyle.blue).frame(minHeight: 32)
                }
            }
            .opacity(leftOut ? 0.45 : 1)
            Spacer(minLength: 8)
            Menu {
                ForEach(DrawerChoice.all(kids: store.sessionKids), id: \.self) { d in
                    Button(d.title) { model.batchDrawers[item.id] = d; model.batchLeftOut.remove(item.id) }
                }
                Divider()
                Button(leftOut ? "Put it away" : "Leave unread") {
                    if leftOut { model.batchLeftOut.remove(item.id) } else { model.batchLeftOut.insert(item.id) }
                }
            } label: {
                Text(leftOut ? "Stays unread" : (model.batchDrawer(item)?.title ?? "Choose"))
                    .font(.caption.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 12).frame(minHeight: 34)
                    .foregroundStyle(leftOut ? CalmStyle.secondary : CalmStyle.blue)
                    .background((leftOut ? CalmStyle.secondary : CalmStyle.blue).opacity(0.1), in: Capsule())
            }
            .accessibilityIdentifier("session.batch.drawer")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: Reading

struct SessionReadingScreen: View {
    @Environment(FeedStore.self) private var store
    @Bindable var model: SessionModel

    var body: some View {
        let items = model.readingItems
        let moves = model.readingMoves
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(items.count == 1 ? "One newsletter" : "\(items.count) newsletters").font(.title.weight(.bold))
                    Text("Archive the ones you won't read. Tap Keep to leave one unread.").font(.callout).foregroundStyle(CalmStyle.secondary)
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            let kept = model.readingKept.contains(item.id)
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.message.fromName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(item.message.subject).font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 8)
                                Button(kept ? "Kept" : "Keep") {
                                    if kept { model.readingKept.remove(item.id) } else { model.readingKept.insert(item.id) }
                                }
                                .font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 34)
                                .foregroundStyle(kept ? CalmStyle.onBlue : CalmStyle.blue)
                                .background(kept ? CalmStyle.blue : CalmStyle.blue.opacity(0.1), in: Capsule())
                                .accessibilityIdentifier("session.reading.keep")
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            if item.id != items.last?.id { Divider().overlay(CalmStyle.divider) }
                        }
                    }
                    .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            VStack(spacing: 10) {
                SessionConfirmButton(title: moves.count == items.count ? "Archive all \(moves.count)" : "Archive \(moves.count)",
                                     previews: [FeedStore.putAwayPreview(moves)], enabled: !moves.isEmpty,
                                     identifier: "session.reading.confirm") { approvals in
                    store.putAway(moves, confirmed: approvals[0], onReturn: { [model] ids in model.reopen(ids) })
                    model.finishReading(moves)
                }
                Button(moves.isEmpty ? "Continue" : "Leave them unread") { model.finishReading([]) }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44).foregroundStyle(CalmStyle.blue)
                    .accessibilityIdentifier("session.reading.skip")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
    }
}

// MARK: Wrap-up

struct SessionWrapScreen: View {
    let model: SessionModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.leftUnread.isEmpty ? "Inbox clear" : "Done for now").font(.largeTitle.weight(.bold))
                    HStack(spacing: 10) {
                        stat(model.replies, "Replies")
                        stat(model.filed, "Filed")
                        stat(model.archived, "Archived")
                    }
                    if !model.drawerSummary.isEmpty {
                        Text(model.drawerSummary).font(.callout).foregroundStyle(CalmStyle.secondary)
                    }
                    if model.datesAdded > 0 {
                        Label(model.datesAdded == 1 ? "1 date added to your calendar" : "\(model.datesAdded) dates added to your calendar",
                              systemImage: "calendar").font(.callout)
                    }
                    if !model.leftUnread.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LEFT UNREAD ON PURPOSE").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                            ForEach(model.leftUnread.prefix(5)) { item in
                                Text("\(item.message.fromName): \(item.message.subject)").font(.callout).lineLimit(1)
                            }
                            if model.leftUnread.count > 5 {
                                Text("and \(model.leftUnread.count - 5) more").font(.caption).foregroundStyle(CalmStyle.secondary)
                            }
                        }
                    }
                    if !model.plan.carried.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOU PROMISED").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                            ForEach(model.plan.carried.prefix(5), id: \.id) { p in
                                Text("\(p.recipient): \u{201C}\(p.text)\u{201D}").font(.callout).lineLimit(2)
                            }
                        }
                    }
                }
                .padding(20)
            }
            Button("Done") { close() }.buttonStyle(SessionButtonStyle()).padding(20).accessibilityIdentifier("session.done")
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.title.weight(.bold))
            Text(label).font(.caption).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
