import SwiftUI
import UIKit

/// The inbox session (Sprint 7): unread mail one decision at a time. Each screen has one main button.
/// Gmail stays the place for heavy email work; this is the calm front end.
struct SessionView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var model: SessionModel?
    var backlog = false
    /// Bumped by "Clear the next page" to build a fresh plan in place.
    @State private var page = 0
    @State private var shown: Set<String> = []
    /// The blue bar at the bottom of every card, and the dot's flight (owner, Nov 13, 2026).
    @State private var drop = SessionDropBar()

    var body: some View {
        VStack(spacing: 0) {
            if let model {
                SessionHeader(model: model, title: backlog ? "Older mail" : "Inbox session", close: close)
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(onCard ? CalmStyle.page : CalmStyle.background)
        .overlay { if onCard || drop.flying { SessionDropLayer(bar: drop, showBar: onCard) } }
        .environment(drop)
        .foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: page) {
            guard model == nil else { return }
            let plan = store.makeSessionPlan(backlog: backlog, excluding: shown)
            shown.formUnion(plan.items.map(\.id))
            let fresh = SessionModel(plan: plan, backlog: backlog)
            fresh.rememberedFates = store.senderFates.fates
            model = fresh
            // Routine mail the rules could not place gets an on-device drawer suggestion, so its screen has one main button.
            let unplaced = plan.items.filter { $0.drawer == nil && !$0.message.isPerson && $0.group != .reading }.map(\.message)
            if !unplaced.isEmpty {
                let guesses = await AppleDrawerGuesser.guesses(for: unplaced)
                if !guesses.isEmpty { fresh.replacePlanBeforeStart(store.makeSessionPlan(modelGuesses: guesses, backlog: backlog, excluding: shown.subtracting(plan.items.map(\.id)))) }
            }
            if !backlog, fresh.phase == .start { fresh.start() }
        }
    }

    @ViewBuilder private func content(_ m: SessionModel) -> some View {
        switch m.phase {
        // Swipe to sort already said go (owner, Nov 13, 2026): the inbox session opens on its first email, no Start screen.
        case .start:
            if backlog { SessionStartScreen(model: m, openBacklog: openBacklog) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        case .item(let id): SessionItemScreen(model: m, itemID: id).id(id)
        case .batch: SessionBatchScreen(model: m)
        case .reading: SessionReadingScreen(model: m)
        case .wrap: SessionWrapScreen(model: m, close: close, openBacklog: openBacklog)
        }
    }

    private func close() { if !router.path.isEmpty { router.path.removeLast() } }

    /// One email on its own white page (Sprint 8): the header sits on the same white.
    private var onCard: Bool { if case .item = model?.phase { return true } else { return false } }

    /// Older mail waiting in the inbox, if any, as a next step from the start or wrap-up screens.
    private var openBacklog: (() -> Void)? {
        guard store.backlogCandidates.count > 0 else { return nil }
        // Already on older mail: start the next page here. Popping and pushing the same route kept the old screen,
        // so "Clear the next page" did nothing (Nov 10). Mail just filed is already hidden, so it isn't repeated.
        if backlog {
            guard store.backlogCandidates.contains(where: { !shown.contains($0.id) }) else { return nil }
            return { model = nil; page += 1 }
        }
        return { close(); router.open(.backlog) }
    }
}

// MARK: Header

struct SessionHeader: View {
    let model: SessionModel
    var title = "Inbox session"
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.lovely(.headline))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.lovely(.body, .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(CalmStyle.secondary).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Close session").accessibilityIdentifier("session.close")
            }
            if model.plan.count > 0 {
                HStack {
                    Text("\(model.progress.dealtWith) of \(model.plan.count)").font(.lovely(.caption, .semibold))
                    Spacer()
                    if model.progress.dealtWith < model.plan.count {
                        Text("about \(remainingMinutes) min").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
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
    var openBacklog: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.isEmpty {
                        Text("Nothing to go through").font(.lovely(.largeTitle, .bold))
                        Text(model.backlog ? "No older mail is left in your inbox." : "Nothing new is waiting. New mail will be here next time.")
                            .foregroundStyle(CalmStyle.secondary)
                    } else {
                        Text(model.backlog ? "\(model.plan.count) older emails" : "\(model.plan.count) to go through").font(.lovely(.largeTitle, .bold))
                        // Each group is a way in: tap one to start there. Start (below) still goes in the usual order.
                        VStack(spacing: 0) {
                            let groups = SessionGroup.allCases.filter { g in model.plan.items.contains { $0.group == g } }
                            ForEach(groups, id: \.self) { group in
                                let n = model.plan.items.filter { $0.group == group }.count
                                Button { model.start(with: group) } label: {
                                    HStack(spacing: 10) {
                                        Text(group.title).foregroundStyle(CalmStyle.ink)
                                        Spacer()
                                        Text("\(n)").font(.lovely(.body, .semibold)).foregroundStyle(CalmStyle.ink)
                                        Image(systemName: "chevron.right").font(.lovely(.caption, .bold)).foregroundStyle(CalmStyle.secondary)
                                    }
                                    .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Start with these")
                                .accessibilityIdentifier("session.start.\(group.rawValue)")
                                if group != groups.last { Divider().overlay(CalmStyle.divider).padding(.leading, 16) }
                            }
                        }
                        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                        Text("Tap a group to start there.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                        Text("About \(model.plan.estimatedMinutes) min. Each one ends up answered, dated or filed, and out of your inbox.")
                            .font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
                    }
                    if !model.plan.carried.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STILL OPEN FROM BEFORE").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                            ForEach(model.plan.carried.prefix(3), id: \.id) { p in
                                Text("You told \(p.recipient): \u{201C}\(p.text)\u{201D}").font(.lovely(.callout)).lineLimit(2)
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
            } else if let openBacklog, !model.backlog {
                Button("Clear older mail in your inbox") { openBacklog() }
                    .buttonStyle(SessionButtonStyle()).padding(20)
                    .accessibilityIdentifier("session.backlog")
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
    /// What he said last, for learning from the proposal he picks.
    @State private var lastSaid = ""
    /// What he typed about this email so far, shown as his bubbles and sent with each new ask so Lovely keeps the context.
    @State private var askHistory: [String] = []
    /// Bumped to clear the ask field after a proposal is used.
    @State private var askResetCount = 0
    /// The keyboard is up for the ask field: the bar shrinks to just the field, like Messages.
    @State private var typing = false
    @State private var showMore = false
    /// "Text Julia about this" from the … sheet (opens Messages with a short summary; he taps Send).
    @State private var textAbout: Post?
    /// The same, from typing "text Julia" in the ask field.
    @State private var textAboutFromAsk: Post?
    @State private var thinking = false
    @State private var proposals: [SessionProposal] = []
    @State private var askNote: String?
    @State private var handoff: SessionHandoffOffer?
    @State private var removedTags: Set<MailTag> = []

    // Sprint 8 card page: the thumb, the ball, the drawer box.
    @State var drag: CGFloat = 0
    @State var slide: CGFloat = 0
    @State var slideStart: CGFloat = 0
    @State var dragDirection: SessionCardMotion.Direction?
    @State var crossed = 0
    @State var fly: CGFloat = 0
    @State var flyOpacity: Double = 1
    @State var intoBall = false
    @State var appeared = false
    @State var busy = false
    @State var showBox = false
    @State var peek: SessionItem?
    /// The home indicator's inset, so Archive and ⋯ clear the blue bar on every phone.
    @State var safeBottom: CGFloat = 0
    @Environment(SessionDropBar.self) var bar: SessionDropBar?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        if let item = model.item(itemID), let post = store.sessionPost(itemID) {
            Group {
                if mode == .decide { cardBody(item, post) } else { classicBody(item, post) }
            }
            .sheet(item: $calendar, onDismiss: finishDate) { box in CalendarEventSheet(draft: box.draft).ignoresSafeArea() }
            .sheet(item: $handoff) { offer in SessionHandoffSheet(offer: offer) { model.record(item.id, .leftUnread); model.advance() } }
            .sheet(isPresented: $showMore) { moreSheet(item, post) }
            .sheet(item: $textAboutFromAsk) { TextAboutSheet(post: $0) }
            .sheet(item: $peek) { SessionPeek(item: $0) }
            .onChange(of: mode != .decide || typing || showBox || slide < 0, initial: true) { _, hide in bar?.hidden = hide }
            .onChange(of: drag) { _, d in bar?.pull = SessionCardMotion.pullProgress(d) }
            .onDisappear { bar?.pull = 0 }
        } else {
            Color.clear.task { model.drop(itemID) }
        }
    }

    /// The classic scrolling screen: reply, and the drawer grid after an engine's suggestion.
    @ViewBuilder private func classicBody(_ item: SessionItem, _ post: Post) -> some View {
            VStack(spacing: 0) {
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SessionMailCard(item: item, post: post) { router.open(.email(post.id)) }
                            if mode != .reply { tagChips(item) }
                            switch mode {
                            case .decide: askResults(item, post)
                            case .drawers:
                                askResults(item, post)
                                if proposals.isEmpty { drawerGrid(item) }
                            case .reply: replyEditor
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: proposals) { _, new in
                        if !new.isEmpty { withAnimation { reader.scrollTo("session.askResults", anchor: .bottom) } }
                    }
                }
                // The ask field lives here, outside the scroll view, so the keyboard pushes it up and it stays in view as it grows.
                VStack(spacing: 10) {
                    switch mode {
                    case .decide: decideBar(item, post)
                    case .drawers:
                        // You can still talk about it when Lovely has no drawer to suggest.
                        SessionAskField(hint: hint(item), thinking: thinking, onFocus: { typing = $0 }, onAsk: { ask($0, item, post) })
                            .id("\(item.id)-\(askResetCount)")
                        if !typing { secondaryRow(item, post, showOtherDrawer: false) }
                    case .reply: replyActions(item, post)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                .background(CalmStyle.background)
            }
            .background(CalmStyle.background)
    }

    // MARK: Decide

    /// Field, then one main button, then the small row. While typing, only the field, so it sits right above the keyboard.
    /// When an engine has proposed something, its card is the main button and the usual one steps aside (no duplicates).
    @ViewBuilder private func decideBar(_ item: SessionItem, _ post: Post) -> some View {
        SessionAskField(hint: hint(item), thinking: thinking, onFocus: { typing = $0 }, onAsk: { ask($0, item, post) })
            .id("\(item.id)-\(askResetCount)")
        if !typing {
            if proposals.isEmpty { primaryAction(item, post) }
            secondaryRow(item, post, showOtherDrawer: true)
        }
    }

    @ViewBuilder private func primaryAction(_ item: SessionItem, _ post: Post) -> some View {
        if store.sessionTrashMemory.suggestsTrash(for: post.email.from.email) {
            trashButton(item, post, prominent: true)
            Text("You moved mail from this sender to Trash before.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        } else {
            suggestedAction(item, post)
        }
    }

    func trashButton(_ item: SessionItem, _ post: Post, prominent: Bool) -> some View {
        Button("Move to Trash") {
            showMore = false
            clearAsk()
            store.sessionTrash(post)
            model.record(item.id, .trashed); model.advance()
        }
        .buttonStyle(SessionButtonStyle(prominent: prominent)).accessibilityIdentifier("session.trash")
    }

    @ViewBuilder private func suggestedAction(_ item: SessionItem, _ post: Post) -> some View {
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
    }

    private func secondaryRow(_ item: SessionItem, _ post: Post, showOtherDrawer: Bool) -> some View {
        HStack(spacing: 8) {
            if item.suggestion != .reply, item.message.isPerson || item.message.section == .notes {
                small("Reply", id: "session.replyInstead") { openReply(post) }
            }
            if showOtherDrawer { small("Other drawer", id: "session.otherDrawer") { mode = .drawers } }
            small("Leave unread", id: "session.leaveUnread") { model.record(item.id, .leftUnread); model.advance() }
            small("Skip", id: "session.skip") { model.skip(item.id) }
            Button { showMore = true } label: { Image(systemName: "ellipsis.circle").font(.lovely(.title3)) }
                .frame(width: 44, height: 44).foregroundStyle(CalmStyle.blue)
                .accessibilityLabel("More for this sender").accessibilityIdentifier("session.more")
        }
    }

    // MARK: More: rules for the whole sender

    /// Everything about the sender, not just this email: always put away (a Gmail filter), screen out, or Trash.
    /// Each button is its own preview: the lines above it say exactly what Gmail will do.
    private func moreSheet(_ item: SessionItem, _ post: Post) -> some View {
        let sender = post.email.from.email
        let moving = store.inboxPosts(from: sender)
        let drawer = item.drawer?.choice
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mail from \(post.email.from.name)").font(.lovely(.title3, .bold))
                        Text(sender).font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
                    }
                    if let drawer {
                        let label = DrawerChoice(drawer.drawer).labelName
                        let preview = FeedStore.senderRulePreview(sender: sender, label: label, inboxCount: moving.count, screenOut: false)
                        ruleBlock(preview) {
                            SessionConfirmButton(title: "Always put away in \(drawer.drawer.title)", previews: [preview], identifier: "session.always") { a in
                                store.applySenderRule(sender: sender, label: label, posts: moving, markRead: true, screenOut: false, confirmed: a[0])
                                finishSender(item, moving, .filed(DrawerChoice(drawer.drawer)))
                            }
                        }
                    }
                    let always2w = ShortTerm.preview(sender: sender)
                    ruleBlock(always2w) {
                        SessionConfirmButton(title: "Always keep 2 weeks, then Trash", previews: [always2w], identifier: "session.alwaysTwoWeeks") { a in
                            store.applySenderRule(sender: sender, label: ShortTerm.label, posts: moving, markRead: true, screenOut: false, confirmed: a[0])
                            finishSender(item, moving, .archived)
                        }
                    }
                    let screen = FeedStore.senderRulePreview(sender: sender, label: ScreenedOut.label, inboxCount: moving.count, screenOut: true)
                    ruleBlock(screen) {
                        SessionConfirmButton(title: "Screen out this sender", previews: [screen], prominent: drawer == nil, identifier: "session.screenOut") { a in
                            store.applySenderRule(sender: sender, label: ScreenedOut.label, posts: moving, markRead: false, screenOut: true, confirmed: a[0])
                            finishSender(item, moving, .archived)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Just this email.").font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
                        Button { textAbout = post } label: {
                            Label(OpenEmailView.textAboutTitle(TextRecipients().all.first), systemImage: "message").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CalmActionStyle()).accessibilityIdentifier("session.textAbout")
                        Button { showMore = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openBox() } } label: {
                            Label("Choose another drawer", systemImage: "tray.and.arrow.down").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CalmActionStyle()).accessibilityIdentifier("session.otherDrawer.more")
                        keepTwoWeeksButton(item, prominent: false)
                        trashButton(item, post, prominent: false)
                    }
                }
                .padding(20)
            }
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
            .toolbar { Button("Cancel") { showMore = false } }
            .sheet(item: $textAbout) { TextAboutSheet(post: $0) }
        }
        .presentationDetents([.large])
    }

    private func ruleBlock(_ preview: ActionPreview, @ViewBuilder button: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
            }
            button()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }

    /// The sender's other emails in this session are handled too; move on.
    private func finishSender(_ item: SessionItem, _ moving: [Post], _ outcome: SessionOutcome) {
        showMore = false
        clearAsk()
        for p in moving where model.item(p.id) != nil { model.record(p.id, outcome) }
        model.record(item.id, outcome)
        model.advance()
    }

    private func small(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.lovely(.subheadline, .medium)).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(CalmStyle.blue)
            .accessibilityIdentifier(id)
    }

    private func putAwayButton(_ item: SessionItem, _ d: DrawerChoice) -> some View {
        let move = filedMove(item, d)
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
        let move = filedMove(item, d)
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

    /// The move for this item in a category, without any tags the owner tapped off.
    private func filedMove(_ item: SessionItem, _ d: DrawerChoice) -> SessionMove {
        var move = store.sessionMove(item, choice: d)
        move.tags.removeAll { removedTags.contains($0) }
        return move
    }

    /// The suggested tags as chips. Tap one to leave it off; tap again to bring it back.
    @ViewBuilder private func tagChips(_ item: SessionItem) -> some View {
        if !item.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        let off = removedTags.contains(tag)
                        Button {
                            if off { removedTags.remove(tag) } else { removedTags.insert(tag) }
                        } label: {
                            Text(tag.title).font(.lovely(.caption, .medium)).strikethrough(off)
                                .padding(.horizontal, 10).frame(minHeight: 30)
                                .foregroundStyle(off ? CalmStyle.secondary : CalmStyle.blue)
                                .background((off ? CalmStyle.secondary : CalmStyle.blue).opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(off ? "\(tag.title), left off" : "Tag \(tag.title)")
                        .accessibilityHint(off ? "Adds the tag back" : "Leaves this tag off")
                    }
                }
            }
            .accessibilityIdentifier("session.tags")
        }
    }

    private func put(_ move: SessionMove, _ approval: ConfirmedAction) {
        store.putAway([move], confirmed: approval, onReturn: { [model] ids in model.reopen(ids) })
        model.recordMoves([move])
        model.advance()
    }

    // MARK: Drawers

    private func drawerGrid(_ item: SessionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE DOES IT GO?").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(DrawerChoice.all(kids: store.sessionKids), id: \.self) { d in
                    let move = filedMove(item, d)
                    SessionConfirmButton(title: d.title, previews: [FeedStore.putAwayPreview([move])], prominent: d == item.drawer?.choice,
                                         identifier: "session.drawer.\(d.labelName)") { approvals in put(move, approvals[0]) }
                }
            }
            keepTwoWeeksButton(item, prominent: false)
            archiveButton(item, prominent: false)
        }
    }

    /// Out of the inbox now; after two weeks Lovely offers to move it to Trash (a safety net instead of deleting).
    private func keepTwoWeeksButton(_ item: SessionItem, prominent: Bool) -> some View {
        SessionConfirmButton(title: "Keep 2 weeks, then Trash", previews: [ShortTerm.preview(sender: nil)], prominent: prominent,
                             identifier: "session.keepTwoWeeks") { approvals in
            guard let post = store.sessionPost(item.id) else { return }
            showMore = false
            clearAsk()
            store.keepShortTerm(post, confirmed: approvals[0])
            model.record(item.id, .archived); model.advance()
        }
    }

    // MARK: Reply

    private var replyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR REPLY").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
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
        let drawer = item.drawer?.choice ?? DrawerChoice(.personal)
        if store.canSendSessionReply(post) {
            SessionConfirmButton(title: "Send and put away in \(drawer.title)",
                                 previews: [FeedStore.replyPreview(post, body: draft), FeedStore.replyFilingPreview(post, drawer: drawer)],
                                 enabled: !drafting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                 identifier: "session.send") { approvals in
                store.sendSessionReply(post, body: draft, drawer: drawer, tags: filedMove(item, drawer).tags, confirmed: approvals[0], filing: approvals[1],
                                       onReturn: { [model] ids in model.reopen(ids) })
                model.record(item.id, .replied)
                model.advance()
            }
            Text("To \(post.email.from.email). You have 10 seconds to undo.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        } else {
            Button("Finish in Gmail") { openInGmail(post) }.buttonStyle(SessionButtonStyle())
            Text("Several people are on this one, so Gmail sends it.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
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
            var text = (try? await ReplyDrafterFactory.best().draft(replyTo: post.email, myName: name)) ?? ""
            if text.isEmpty { text = (try? await TemplateReplyDrafter().draft(replyTo: post.email, myName: name)) ?? "" }
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

// MARK: Sprint 8 card page

/// Version 1 (owner, Nov 10, 2026), with the blue bar (Nov 13): the email is a full page. Sender at the top, one big
/// fact, then the email in words set straight on the page (no box: the page is already the card), then tags, Reply and
/// Open, and Ask Lovely. Archive and ⋯ sit just above a thin blue bar at the very bottom. Flick up skips for now; pull
/// down and the bar rises while the drawer is named above it; let go past the line and the email drops into the bar
/// (the destination was shown during the pull). Swipe left shows Move to Trash; tap opens the quick look. No main
/// button: VoiceOver gets the same three moves as actions.
extension SessionItemScreen {
    private func pullTarget(_ item: SessionItem, _ post: Post) -> SessionPullTarget {
        let date = MailDates.extract(post.email, now: Date()).first.map { ComingUp.fullLabel($0) }
        return SessionPullTarget.make(item, dateLabel: date)
    }

    private func hero(_ item: SessionItem, _ post: Post) -> SessionHero {
        // Health mail: only the subject is read, for an appointment day.
        let dates = item.message.isHealth
            ? MailDates.extract(text: post.email.subject, sent: post.email.date, now: Date())
            : MailDates.extract(post.email, now: Date())
        return SessionHero.make(item.message, dates: dates, now: Date())
    }

    @ViewBuilder func cardBody(_ item: SessionItem, _ post: Post) -> some View {
        let target = pullTarget(item, post)
        let p = SessionCardMotion.pullProgress(drag)
        let pageScale = pageScaleNow(p)
        let corner = pageCornerNow(p)
        let y = pageOffsetNow()
        ZStack(alignment: .bottom) {
            CalmStyle.pageGround.ignoresSafeArea()

            // The page, drawn to the bottom edge; the words ride on top with the same moves.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(CalmStyle.page)
                .shadow(color: Color(hex: 0x25222A).opacity(drag != 0 || slide != 0 ? 0.12 : 0), radius: 18, y: 6)
                .scaleEffect(pageScale, anchor: .bottom)
                .offset(x: slide, y: y)
                .opacity(flyOpacity * (appeared ? 1 : 0))
                .ignoresSafeArea(.container, edges: .bottom)

            cardPage(item, post)
                .contentShape(Rectangle())
                .scaleEffect(pageScale, anchor: .bottom)
                .offset(x: slide, y: y)
                .opacity(flyOpacity * (appeared ? 1 : 0) * (intoBall ? 0.4 : 1))
                .onTapGesture { tapPage(item, post) }
                .gesture(cardDrag(item, post, target), including: typing || showBox ? .subviews : .all)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("session.card")
                .accessibilityAction(named: "Skip for now") { skipCard(item) }
                .accessibilityAction(named: target.label) { release(item, post, target) }
                .accessibilityAction(named: "Move to Trash") { trashCard(item, post) }

            if slide < 0 { trashWord(item, post) }

            Text(drag <= -SessionCardMotion.upDistance ? "Back next session" : "Skip for now")
                .font(.lovely(.subheadline, .semibold))
                .foregroundStyle(drag <= -SessionCardMotion.upDistance ? CalmStyle.blue : CalmStyle.secondary)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 4)
                .opacity(Double(min(1, max(0, -drag) / SessionCardMotion.upDistance)))
                .allowsHitTesting(false)

            if !typing {
                // Where it goes, named during the pull, just above the rising bar: dashed, then filled blue once
                // letting go will file it. The bar itself carries no words.
                Label(p >= 1 ? target.releaseLabel : target.label, systemImage: p >= 1 ? "checkmark" : "tray")
                    .font(.lovely(.callout, .medium))
                    .foregroundStyle(p >= 1 ? CalmStyle.onBlue : CalmStyle.ink)
                    .padding(.horizontal, 20).frame(minHeight: 56)
                    .background(p >= 1 ? LifeColor.purple : CalmStyle.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LifeColor.dash, style: StrokeStyle(lineWidth: 2, dash: p >= 1 ? [] : [6, 5])))
                    .padding(.bottom, SessionDropBar.restHeight + (SessionDropBar.risenHeight - SessionDropBar.restHeight) * min(1, p) + 18)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .opacity(Double(min(1, p * 1.8)))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

            }

            if showBox {
                drawerBox(item, post)
                    .transition(.asymmetric(insertion: .scale(scale: 0.25, anchor: .bottom).combined(with: .opacity),
                                            removal: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity)))
                    .zIndex(5)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeBottom = $0 }
        .onAppear {
            // The next email rises out of the bar.
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private func pageScaleNow(_ p: CGFloat) -> CGFloat {
        let pull: CGFloat = 1 - min(p, 1.3) * 0.12
        let into: CGFloat = intoBall ? 0.02 : 1
        let rise: CGFloat = appeared ? 1 : 0.05
        return pull * into * rise
    }

    private func pageCornerNow(_ p: CGFloat) -> CGFloat {
        if intoBall || !appeared { return 300 }
        if drag > 0 { return min(44, p * 44) }
        if drag < 0 { return min(44, -drag / 3) }
        return slide < 0 ? 24 : 0
    }

    private func pageOffsetNow() -> CGFloat {
        let into: CGFloat = intoBall ? 40 : 0
        let rise: CGFloat = appeared ? 0 : 80
        return SessionCardMotion.resisted(drag) + fly + into + rise
    }

    /// The page's words, top to bottom: sender and when it came, the big fact, the subject and Lovely's summary, the
    /// email's own words filling what room is left, then the choices and Ask Lovely near the thumb.
    private func cardPage(_ item: SessionItem, _ post: Post) -> some View {
        let fact = hero(item, post)
        let waiting = item.message.section == .waiting
        let words = SessionCardText.make(item.message, summary: post.summary)
        let talked = !askHistory.isEmpty || !proposals.isEmpty || askNote != nil || thinking
        return VStack(alignment: .leading, spacing: 0) {
            SenderWarning(verdict: store.senderVerdict(post.email), compact: true)
            HStack(spacing: 11) {
                CalmAvatar(person: post.email.from, size: 36, waiting: waiting, organization: !item.message.isPerson)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.email.from.name).font(.lovely(.subheadline, .semibold)).lineLimit(1)
                    Text(post.email.from.email).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(ReceivedDate.label(post.email.date, now: Date())).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                    .accessibilityLabel("Received \(ReceivedDate.full(post.email.date))")
            }
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(fact.label).font(.lovely(.subheadline, .semibold)).foregroundStyle(waiting ? CalmStyle.roseInk : CalmStyle.secondary)
                Text(fact.value)
                    .font(.lovely(size: 60, weight: .heavy)).tracking(-1.8)
                    .lineLimit(2).minimumScaleFactor(0.4)
                    .foregroundStyle(CalmStyle.ink)
            }
            .padding(.top, 28)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                if !post.email.subject.isEmpty {
                    Text(post.email.subject).font(.lovely(.title3, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                if let lead = words.lead {
                    Text(words.leadIsAsk ? "\u{201C}\(lead)\u{201D}" : lead)
                        .font(.lovely(.body)).foregroundStyle(words.leadIsAsk ? CalmStyle.roseInk : CalmStyle.ink)
                        .lineLimit(talked ? 2 : 4).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 20)

            if let excerpt = words.excerpt, !talked {
                SessionExcerpt(text: excerpt)
                    .padding(.top, 14).padding(.bottom, 10)
                    .layoutPriority(-1)
            } else {
                Spacer(minLength: 14)
            }

            choices(item, post, talked: talked)
                .padding(.bottom, typing ? 8 : 4)
            if !typing {
                // Archive and ⋯ in the page's own flow, so they never cover the ask field; clear of the bar on any phone.
                aboveBar(item, post)
                    .opacity(Double(max(0, 1 - SessionCardMotion.pullProgress(drag) * 2)))
                    .padding(.bottom, max(4, SessionDropBar.restHeight + 8 - safeBottom))
            }
        }
        .padding(.horizontal, 22)
        .foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
    }

    /// Near the thumb: a Trash hint when it applies, tags, Choose a drawer, Reply and Open, and Ask Lovely.
    private func choices(_ item: SessionItem, _ post: Post, talked: Bool) -> some View {
        let canReply = item.suggestion == .reply || item.message.isPerson || item.message.section == .notes
        return VStack(alignment: .leading, spacing: 10) {
            if store.sessionTrashMemory.suggestsTrash(for: post.email.from.email) {
                Text("You moved mail from this sender to Trash before. Swipe left to do it again.")
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            tagChips(item)
            HStack(spacing: 18) {
                if item.drawer == nil, item.suggestion != .archive {
                    Button("Choose a drawer") { openBox() }.accessibilityIdentifier("session.chooseDrawer")
                }
                if canReply { Button("Reply") { openReply(post) }.accessibilityIdentifier("session.reply") }
                Spacer(minLength: 0)
                Button("Open \u{203A}") { router.open(.email(post.id)) }.accessibilityIdentifier("session.openEmail")
            }
            .font(.lovely(.subheadline, .semibold)).foregroundStyle(CalmStyle.blue)
            .frame(minHeight: 36)
            if talked {
                ScrollView { askResults(item, post) }
                    .frame(maxHeight: 260)
                    .scrollDismissesKeyboard(.interactively)
            }
            SessionAskField(hint: hint(item), thinking: thinking, onFocus: { typing = $0 }, onAsk: { ask($0, item, post) })
                .id("\(item.id)-\(askResetCount)")
        }
    }

    /// Archive (left) and ⋯ (right), just above the blue bar.
    private func aboveBar(_ item: SessionItem, _ post: Post) -> some View {
        let move = SessionMove(messageID: item.id, drawer: nil)
        return HStack {
            SessionConfirmTap(previews: [FeedStore.putAwayPreview([move])], identifier: "session.archive") { approvals in
                fileInto(move, approvals[0])
            } label: {
                Text("Archive").font(.lovely(.body, .semibold)).foregroundStyle(CalmStyle.blue).frame(minWidth: 44, minHeight: 44)
            }
            Spacer()
            Button { showMore = true } label: {
                Image(systemName: "ellipsis").font(.lovely(.body, .bold)).frame(width: 44, height: 44)
            }
            .foregroundStyle(CalmStyle.blue)
            .accessibilityLabel("More for this email and sender").accessibilityIdentifier("session.more")
        }
        .padding(.horizontal, -10)
    }

    private func trashWord(_ item: SessionItem, _ post: Post) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button { trashCard(item, post) } label: {
                Text("Move to\nTrash").font(.lovely(.body, .semibold)).multilineTextAlignment(.center)
                    .foregroundStyle(Color.white)
                    .frame(width: max(SessionCardMotion.trashWidth, -slide))
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("session.trash")
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .opacity(Double(min(1, -slide / SessionCardMotion.trashWidth)))
    }

    // MARK: The thumb

    private func cardDrag(_ item: SessionItem, _ post: Post, _ target: SessionPullTarget) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { v in
                guard !busy, !typing, !showBox else { return }
                let dx = v.translation.width, dy = v.translation.height
                if dragDirection == nil {
                    slideStart = slide
                    dragDirection = SessionCardMotion.direction(dx: dx, dy: dy, slideStart: slideStart)
                }
                if dragDirection == .sideways {
                    let before = slide <= -SessionCardMotion.trashWidth * 0.6
                    slide = SessionCardMotion.slide(start: slideStart, dx: dx)
                    if !before, slide <= -SessionCardMotion.trashWidth * 0.6 { tick() }
                    return
                }
                if slideStart < 0 { return }
                drag = dy
                let c = -dy >= SessionCardMotion.upDistance ? 1 : (dy >= SessionCardMotion.downDistance ? -1 : 0)
                if c != crossed {
                    if c != 0 { tick() }
                    crossed = c
                }
            }
            .onEnded { v in
                guard !busy, dragDirection != nil else { dragDirection = nil; return }
                let wasSideways = dragDirection == .sideways
                dragDirection = nil
                crossed = 0
                if wasSideways {
                    let open = slideStart + v.predictedEndTranslation.width <= -SessionCardMotion.trashWidth * 0.5
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { slide = open ? -SessionCardMotion.trashWidth : 0 }
                    return
                }
                if slideStart < 0 || slide < 0 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { slide = 0; drag = 0 }
                    return
                }
                switch SessionCardMotion.release(dy: v.translation.height, predictedDy: v.predictedEndTranslation.height) {
                case .skip: skipCard(item)
                case .putAway: release(item, post, target)
                case .springBack:
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { drag = 0 }
                }
            }
    }

    /// A tap reads: the frosted quick look, with Open for the full email (owner, Nov 12, 2026).
    private func tapPage(_ item: SessionItem, _ post: Post) {
        if slide < 0 { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { slide = 0 }; return }
        guard !busy, !typing else { return }
        peek = item
    }

    // MARK: The moves

    /// Flick up: stays unread and comes back next session. Undo brings it straight back.
    private func skipCard(_ item: SessionItem) {
        guard !busy else { return }
        busy = true
        tick()
        withAnimation(.easeIn(duration: 0.3)) { fly = -1100; flyOpacity = 0 }
        let id = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [model, store] in
            clearAsk()
            model.record(id, .leftUnread)
            store.undo.enqueue(title: "Skipped. Back next session", work: {}, undone: { model.returnTo(id) })
            model.advance()
        }
    }

    /// Past the line, let go: the screen's filing action, through the same preview it names during the pull.
    private func release(_ item: SessionItem, _ post: Post, _ target: SessionPullTarget) {
        switch target {
        case .chooseDrawer:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { drag = 0 }
            openBox()
        case .archive:
            let move = SessionMove(messageID: item.id, drawer: nil)
            fileInto(move, SessionPull.approvals(for: [FeedStore.putAwayPreview([move])])[0])
        case .putAway(let d, let dateLabel):
            let move = filedMove(item, d)
            let approval = SessionPull.approvals(for: [FeedStore.putAwayPreview([move])])[0]
            if dateLabel != nil, let first = MailDates.extract(post.email, now: Date()).first {
                // Add its date first (Apple's sheet), then it is put away either way.
                swallow {
                    pendingDateMove = move; pendingDateApproval = approval
                    calendar = SessionCalendarBox(draft: CalendarDraft.make(email: post.email, date: first))
                }
            } else {
                fileInto(move, approval)
            }
        }
    }

    /// Into the bar: the page shrinks into it, the bar gulps, the rose dot flies out, and the mail is put away
    /// (10-second Undo). The next email rises out of the bar while the dot is still falling: no wait.
    private func fileInto(_ move: SessionMove, _ approval: ConfirmedAction) {
        swallow { put(move, approval) }
    }

    private func swallow(then finish: @escaping () -> Void) {
        guard !busy else { return }
        busy = true
        withAnimation(.easeIn(duration: 0.2)) { intoBall = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 1)
            bar?.launch(reduceMotion: reduceMotion)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.25 : 0.5)) {
            clearAsk()
            finish()
        }
    }

    private func trashCard(_ item: SessionItem, _ post: Post) {
        guard !busy else { return }
        busy = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeIn(duration: 0.25)) { slide = -600; flyOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            clearAsk()
            store.sessionTrash(post)
            model.record(item.id, .trashed)
            model.advance()
        }
    }

    // MARK: The drawer box

    private func openBox() {
        tick()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { showBox = true }
    }

    private func closeBox() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showBox = false }
    }

    /// Springs up out of the bar: the email for reference, the likeliest drawers with a reason, then the rest.
    private func drawerBox(_ item: SessionItem, _ post: Post) -> some View {
        let picks = DrawerLikely.top(item.message, guess: item.drawer)
        let rest = DrawerChoice.all(kids: store.sessionKids).filter { c in !picks.contains { $0.choice == c } }
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.18).ignoresSafeArea().onTapGesture { closeBox() }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.email.from.name).font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.secondary)
                    Text(post.email.subject).font(.lovely(.headline)).lineLimit(2)
                    if !post.summary.blurb.isEmpty {
                        Text(post.summary.blurb).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(3)
                    }
                }
                Text("MOST LIKELY").font(.lovely(.caption, .semibold)).tracking(0.6).foregroundStyle(CalmStyle.secondary).padding(.top, 4)
                ForEach(picks, id: \.choice) { pick in
                    let move = filedMove(item, pick.choice)
                    SessionConfirmTap(previews: [FeedStore.putAwayPreview([move])], identifier: "session.drawer.\(pick.choice.labelName)") { a in
                        closeBox()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { fileInto(move, a[0]) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pick.choice.drawer.icon).font(.lovely(.body, .semibold)).foregroundStyle(CalmStyle.blue).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pick.choice.title).font(.lovely(.body, .semibold)).foregroundStyle(CalmStyle.ink)
                                Text(pick.reason).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 58)
                        .background(CalmStyle.page, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(Rectangle())
                    }
                }
                Text("OTHER DRAWERS").font(.lovely(.caption, .semibold)).tracking(0.6).foregroundStyle(CalmStyle.secondary).padding(.top, 4)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(rest, id: \.self) { d in
                            let move = filedMove(item, d)
                            SessionConfirmTap(previews: [FeedStore.putAwayPreview([move])], identifier: "session.drawer.\(d.labelName)") { a in
                                closeBox()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { fileInto(move, a[0]) }
                            } label: {
                                Text(d.title).font(.lovely(.subheadline, .semibold)).foregroundStyle(CalmStyle.ink).lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(CalmStyle.page.opacity(0.7), in: Capsule())
                                    .contentShape(Capsule())
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
                Button("Not now") { closeBox() }
                    .font(.lovely(.body, .semibold)).foregroundStyle(CalmStyle.blue)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("session.box.cancel")
            }
            .padding(18)
            .glassPane(corner: 32)
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
    }

    private func tick() { UISelectionFeedbackGenerator().selectionChanged() }
}

struct SessionCalendarBox: Identifiable {
    let draft: CalendarDraft
    var id: String { "\(draft.start.timeIntervalSince1970)-\(draft.title)" }
}

/// Who, what and when for one email. Tapping "Open the email" shows the original.
struct SessionMailCard: View {
    @Environment(FeedStore.self) private var store
    let item: SessionItem
    let post: Post
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SenderWarning(verdict: store.senderVerdict(post.email), compact: true)
            HStack(spacing: 12) {
                CalmAvatar(person: post.email.from, size: 44, waiting: item.message.section == .waiting, organization: !item.message.isPerson)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.email.from.name).font(.lovely(.headline)).lineLimit(1)
                    Text(HomeDigest.age(of: post.email.date, now: Date()) + (post.email.isUnread ? " · unread" : ""))
                        .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                }
                Spacer()
            }
            if !post.email.subject.isEmpty {
                Text(post.email.subject).font(.lovely(.title3, .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            if let ask = item.message.ask {
                Text("\u{201C}\(ask)\u{201D}").font(.lovely(.body)).foregroundStyle(CalmStyle.roseInk).fixedSize(horizontal: false, vertical: true)
            } else if !post.summary.blurb.isEmpty {
                Text(post.summary.blurb).font(.lovely(.body)).foregroundStyle(CalmStyle.secondary).lineLimit(5)
            }
            if let reason = item.drawer?.reason, item.suggestion != .reply {
                Label(reason, systemImage: "tray.and.arrow.down").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            Button("Open the email", action: open).font(.lovely(.subheadline, .medium)).foregroundStyle(CalmStyle.blue)
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
    @State private var peek: SessionItem?

    var body: some View {
        let page = model.batchPage
        let moves = model.batchMoves
        let twoWeeks = model.batchKeepTwoWeeksIDs
        let trash = model.batchTrashIDs
        let blocked = model.ids(page, .block)
        let blocks = SessionFateStrip.blockRules(page, ids: blocked, store: store)
        let acting = moves.count + twoWeeks.count + trash.count
        let allFiled = moves.count == page.count && moves.allSatisfy { $0.drawer != nil }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(page.count == 1 ? "One quick one" : "\(page.count) quick ones").font(.lovely(.title, .bold))
                    Text("Each goes in its drawer, marked read and out of your inbox. Change a row's choice to decide it differently; tap Every time to make it a Gmail filter for that sender, or Block to screen the sender out.")
                        .font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
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
                let pageIDs = Set(page.map(\.id))
                let always = model.alwaysItems(page).compactMap { item in
                    SessionFateStrip.alwaysRule(item, fate: model.batchFate(item), drawer: model.batchDrawer(item), store: store, skipping: pageIDs)
                        .map { (sender: item.message.fromAddress, rule: $0) }
                }
                // The button is the preview (Sprint 7): it says when it also makes Gmail filters.
                let base = allFiled ? "Put away all \(acting)" : (acting == page.count ? "Do all \(acting)" : "Do \(acting)")
                let withAlways = always.isEmpty ? base : base + " + \(always.count) Gmail filter\(always.count == 1 ? "" : "s")"
                SessionConfirmButton(title: SessionFateStrip.title(withAlways, acting: acting, blocked: blocks.count),
                                     previews: [SessionFateStrip.preview(moves, twoWeeks: twoWeeks.count, trash: trash.count)] + always.map(\.rule.preview) + blocks.map(\.preview),
                                     enabled: acting + blocks.count > 0,
                                     identifier: "session.batch.confirm") { approvals in
                    // "Always" rows: one Gmail filter each, confirmed by the same tap (each has its own preview).
                    for (i, a) in always.enumerated() where approvals.count > i + 1 {
                        store.applySenderRule(sender: a.sender, label: a.rule.label, posts: a.rule.posts,
                                              markRead: a.rule.markRead, screenOut: a.rule.screenOut, confirmed: approvals[i + 1])
                    }
                    // Block rows: one Screen out filter per sender, each with its own preview, after the Always ones.
                    for (i, b) in blocks.enumerated() where approvals.count > 1 + always.count + i {
                        store.applySenderRule(sender: b.sender, label: ScreenedOut.label, posts: b.posts, markRead: false, screenOut: true,
                                              confirmed: approvals[1 + always.count + i])
                    }
                    model.alwaysRows.subtract(pageIDs)
                    store.rememberFates(model.fatesToRemember(page))
                    if !moves.isEmpty { store.putAway(moves, confirmed: approvals[0], onReturn: { [model] ids in model.reopen(ids) }) }
                    store.keepShortTerm(twoWeeks.compactMap { store.sessionPost($0) }, confirmed: approvals[0])
                    store.sessionTrash(trash.compactMap { store.sessionPost($0) })
                    model.finishBatchPage(moves, keptTwoWeeks: twoWeeks, trashed: trash, blocked: blocked)
                }
                Button(acting + blocks.count == 0 ? "Continue" : "Leave these unread") { model.finishBatchPage([]) }
                    .font(.lovely(.subheadline, .medium)).frame(minHeight: 44).foregroundStyle(CalmStyle.blue)
                    .accessibilityIdentifier("session.batch.skip")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
        .sheet(item: $calendar) { box in CalendarEventSheet(draft: box.draft).ignoresSafeArea() }
        .sheet(item: $peek) { SessionPeek(item: $0) }
    }

    private func row(_ item: SessionItem) -> some View {
        let leftOut = model.batchFate(item) == .unread
        let post = store.sessionPost(item.id)
        let date = post.flatMap { MailDates.extract($0.email, now: Date()).first }
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                SessionRowHeader(item: item) { peek = item }
                if let post { SenderWarning(verdict: store.senderVerdict(post.email), compact: true).padding(.top, 4) }
                let tags = model.batchTags(item)
                if !tags.isEmpty {
                    Text(tags.map(\.title).joined(separator: " · ")).font(.lovely(.caption)).foregroundStyle(CalmStyle.blue).lineLimit(1)
                }
                if let date, let post {
                    Button { calendar = SessionCalendarBox(draft: CalendarDraft.make(email: post.email, date: date)) } label: {
                        Label("Add \(ComingUp.fullLabel(date))", systemImage: "calendar.badge.plus").font(.lovely(.caption, .medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(CalmStyle.blue).frame(minHeight: 32)
                }
            }
            .opacity(leftOut ? 0.45 : 1)
            SessionFateStrip(model: model, item: item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: Reading

struct SessionReadingScreen: View {
    @Environment(FeedStore.self) private var store
    @Bindable var model: SessionModel
    @State private var peek: SessionItem?

    var body: some View {
        let items = model.readingItems
        let moves = model.readingMoves
        let twoWeeks = model.ids(items, .keepTwoWeeks, reading: true)
        let trash = model.ids(items, .trash, reading: true)
        let blocked = model.ids(items, .block, reading: true)
        let blocks = SessionFateStrip.blockRules(items, ids: blocked, store: store)
        let acting = moves.count + twoWeeks.count + trash.count
        let allArchive = moves.count == items.count && moves.allSatisfy { $0.drawer == nil }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(items.count == 1 ? "One newsletter" : "\(items.count) newsletters").font(.lovely(.title, .bold))
                    Text("Archive the ones you won't read, or Block a sender so their mail skips your inbox from now on. Lovely remembers each sender.")
                        .font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            let unread = model.batchFate(item, reading: true) == .unread
                            VStack(alignment: .leading, spacing: 8) {
                                SessionRowHeader(item: item) { peek = item }
                                    .opacity(unread ? 0.45 : 1)
                                SessionFateStrip(model: model, item: item, reading: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            if item.id != items.last?.id { Divider().overlay(CalmStyle.divider) }
                        }
                    }
                    .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            VStack(spacing: 10) {
                let base = allArchive ? "Archive all \(acting)" : (acting == items.count ? "Do all \(acting)" : "Do \(acting)")
                SessionConfirmButton(title: SessionFateStrip.title(base, acting: acting, blocked: blocks.count),
                                     previews: [SessionFateStrip.preview(moves, twoWeeks: twoWeeks.count, trash: trash.count)] + blocks.map(\.preview),
                                     enabled: acting + blocks.count > 0,
                                     identifier: "session.reading.confirm") { approvals in
                    for (i, b) in blocks.enumerated() where approvals.count > 1 + i {
                        store.applySenderRule(sender: b.sender, label: ScreenedOut.label, posts: b.posts, markRead: false, screenOut: true,
                                              confirmed: approvals[1 + i])
                    }
                    store.rememberFates(model.fatesToRemember(items, reading: true))
                    if !moves.isEmpty { store.putAway(moves, confirmed: approvals[0], onReturn: { [model] ids in model.reopen(ids) }) }
                    store.keepShortTerm(twoWeeks.compactMap { store.sessionPost($0) }, confirmed: approvals[0])
                    store.sessionTrash(trash.compactMap { store.sessionPost($0) })
                    model.finishReading(moves, keptTwoWeeks: twoWeeks, trashed: trash, blocked: blocked)
                }
                Button(acting + blocks.count == 0 ? "Continue" : "Leave them unread") { model.finishReading([]) }
                    .font(.lovely(.subheadline, .medium)).frame(minHeight: 44).foregroundStyle(CalmStyle.blue)
                    .accessibilityIdentifier("session.reading.skip")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
        .sheet(item: $peek) { SessionPeek(item: $0) }
    }
}

/// A batch row's sender, when it arrived, and subject. Tap it, or press and hold, for a quick look at the email
/// without leaving the page (owner, Nov 12, 2026).
struct SessionRowHeader: View {
    @Environment(FeedStore.self) private var store
    let item: SessionItem
    let peek: () -> Void

    var body: some View {
        Button(action: peek) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.message.fromName).font(.lovely(.subheadline, .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    // The chevron says the row opens (owner, Nov 12: "I had no way of opening the email").
                    HStack(spacing: 4) {
                        Text(ReceivedDate.label(item.message.date, now: Date()))
                        Image(systemName: "chevron.right").font(.lovely(.caption2, .semibold))
                    }
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1).layoutPriority(1)
                }
                Text(item.message.subject).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { peek() } label: { Label("Quick look", systemImage: "eye") }
        } preview: {
            SessionPeekBody(item: item, post: store.sessionPost(item.id)).frame(width: 340, height: 460)
        }
        .accessibilityHint("Shows a quick look at the email")
        .accessibilityIdentifier("session.row.peek")
    }
}

/// The quick look: who, when, the subject and the email's text. Read only; Open shows the full email.
/// The quick look, LifeOS style: a frosted sheet with the subject, a light close square, the sender and date, the text,
/// and one black button to open the full email. Read only.
struct SessionPeek: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    let item: SessionItem

    var body: some View {
        let post = store.sessionPost(item.id)
        let full = post?.email.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = full.isEmpty ? item.message.text : full
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.message.subject.isEmpty ? item.message.fromName : item.message.subject)
                    .font(.lovely(size: 26, weight: .semibold)).tracking(-0.5).lineLimit(3)
                Spacer(minLength: 8)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.bold)) }
                    .buttonStyle(LifeSquareStyle(dark: false))
                    .accessibilityLabel("Close").accessibilityIdentifier("session.peek.close")
            }
            HStack {
                Text(item.message.fromName).font(.lovely(.subheadline)).lineLimit(1)
                Spacer(minLength: 8)
                Text(ReceivedDate.label(item.message.date, now: Date())).font(.lovely(.footnote))
                    .padding(.horizontal, 12).frame(minHeight: 30)
                    .background(Color.white.opacity(0.16), in: Capsule())
            }
            ScrollView {
                Text(text.isEmpty ? "Open the email to read it." : String(text.prefix(4_000)))
                    .font(.lovely(.body)).lineSpacing(4)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let post {
                Button("Open the full email") { dismiss(); router.open(.email(post.id)) }
                    .buttonStyle(LifeBlackButtonStyle())
                    .accessibilityIdentifier("session.peek.open")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 12)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(34)
        .presentationBackground(Color(hex: 0x766C65).opacity(0.96))
    }
}

struct SessionPeekBody: View {
    let item: SessionItem
    let post: Post?

    var body: some View {
        let full = post?.email.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = full.isEmpty ? item.message.text : full
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.message.fromName).font(.lovely(.headline))
                Text(item.message.fromAddress).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).textSelection(.enabled)
                Text(ReceivedDate.full(item.message.date)).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                if !item.message.subject.isEmpty {
                    Text(item.message.subject).font(.lovely(.title3, .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(CalmStyle.divider)
                Text(text.isEmpty ? "Open the email to read it." : String(text.prefix(4_000)))
                    .font(.lovely(.body)).foregroundStyle(text.isEmpty ? CalmStyle.secondary : CalmStyle.ink)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
    }
}

/// One row's choices, side by side and swipeable: its category (tap the arrow to pick another), 2 weeks, Archive,
/// Trash, Unread. Used on the quick-ones and newsletter screens; the page's one button does every row.
struct SessionFateStrip: View {
    @Environment(FeedStore.self) private var store
    @Bindable var model: SessionModel
    let item: SessionItem
    var reading = false

    var body: some View {
        let fate = model.batchFate(item, reading: reading)
        // Wraps onto a second line instead of scrolling sideways, so no choice is cut off.
        WrapLayout(spacing: 6) {
                Menu {
                    ForEach(DrawerChoice.all(kids: store.sessionKids), id: \.self) { d in
                        Button(d.title) { model.batchDrawers[item.id] = d; model.setBatchFate(.file, for: item) }
                    }
                } label: {
                    chip((model.batchDrawer(item)?.title ?? "File") + " \u{25BE}", selected: fate == .file)
                }
                // No primaryAction: with one, a tap only re-selected the drawer and the list opened on a long press,
                // so the ▾ looked broken (Nov 9). Now a tap opens the list; picking a drawer also chooses filing.
                .accessibilityIdentifier("session.batch.drawer")
                ForEach([BatchFate.keepTwoWeeks, .archive, .trash, .unread], id: \.self) { f in
                    Button { model.setBatchFate(f, for: item) } label: { chip(f.title, selected: fate == f, rose: f == .trash) }
                        .buttonStyle(.plain).accessibilityIdentifier("session.fate.\(f.rawValue)")
                }
                // Block: screen the sender out (Gmail filter to Screened Out, skips the inbox). Not for people.
                if store.actions != nil, !item.message.isPerson {
                    Button { model.setBatchFate(.block, for: item) } label: {
                        Label("Block", systemImage: "nosign").labelStyle(.titleAndIcon)
                            .font(.lovely(.caption, .semibold)).lineLimit(1)
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .foregroundStyle(fate == .block ? CalmStyle.onBlue : CalmStyle.roseInk)
                            .background(fate == .block ? CalmStyle.roseInk : CalmStyle.roseInk.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(fate == .block ? "Block this sender, on" : "Block this sender")
                    .accessibilityIdentifier("session.fate.block")
                }
                if !reading, store.actions != nil, !item.message.isPerson, SessionModel.alwaysAllowed(fate) {
                    let on = model.alwaysRows.contains(item.id)
                    let suggested = !on && model.suggestsAlways(item, reading: reading)
                    Button {
                        if on { model.alwaysRows.remove(item.id) } else { model.alwaysRows.insert(item.id) }
                    } label: {
                        Label(suggested ? "Every time?" : "Every time", systemImage: on ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.lovely(.caption, .semibold)).lineLimit(1)
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .foregroundStyle(on ? CalmStyle.onBlue : CalmStyle.blue)
                            .background(on ? CalmStyle.blue : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(CalmStyle.blue.opacity(on ? 0 : (suggested ? 0.9 : 0.4)), style: StrokeStyle(lineWidth: 1.5, dash: suggested ? [] : [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Every time for this sender, on" : "Do this every time for this sender")
                    .accessibilityIdentifier("session.fate.always")
                }
        }
    }

    /// The Gmail filter an "Always" row makes, with its preview: filing goes to the drawer's label, 2 weeks to
    /// Short-term, Trash to Screened Out (future mail skips the inbox; nothing is deleted).
    static func alwaysRule(_ item: SessionItem, fate: BatchFate, drawer: DrawerChoice?, store: FeedStore, skipping page: Set<String>)
        -> (label: String, screenOut: Bool, markRead: Bool, posts: [Post], preview: ActionPreview)? {
        let sender = item.message.fromAddress
        let others = store.inboxPosts(from: sender).filter { !page.contains($0.id) }
        let rule: (String, Bool, Bool)
        switch fate {
        case .file:
            guard let drawer else { return nil }
            rule = (drawer.labelName, false, true)
        case .keepTwoWeeks: rule = (ShortTerm.label, false, true)
        case .trash: rule = (ScreenedOut.label, true, false)
        default: return nil
        }
        let preview = FeedStore.senderRulePreview(sender: sender, label: rule.0, inboxCount: others.count, screenOut: rule.1)
        return (rule.0, rule.1, rule.2, others, preview)
    }

    private func chip(_ title: String, selected: Bool, rose: Bool = false) -> some View {
        let tint = rose ? CalmStyle.roseInk : CalmStyle.blue
        return Text(title).font(.lovely(.caption, .semibold)).lineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .foregroundStyle(selected ? CalmStyle.onBlue : tint)
            .background(selected ? tint : tint.opacity(0.1), in: Capsule())
    }

    /// Block rows: one Screen out rule per sender, covering the row and the sender's other inbox mail, with its preview.
    static func blockRules(_ items: [SessionItem], ids: [String], store: FeedStore) -> [(sender: String, posts: [Post], preview: ActionPreview)] {
        let blocked = Set(ids)
        var seen = Set<String>()
        return items.filter { blocked.contains($0.id) }.compactMap { item in
            let key = item.message.fromAddress.lowercased()
            guard seen.insert(key).inserted else { return nil }
            var posts = store.inboxPosts(from: item.message.fromAddress)
            for other in items where blocked.contains(other.id) && other.message.fromAddress.lowercased() == key {
                if let p = store.sessionPost(other.id), !posts.contains(where: { $0.id == p.id }) { posts.append(p) }
            }
            let preview = FeedStore.senderRulePreview(sender: item.message.fromAddress, label: ScreenedOut.label, inboxCount: posts.count, screenOut: true)
            return (item.message.fromAddress, posts, preview)
        }
    }

    /// The page button names the blocks too: "Block 1 sender", or "Archive all 3 + block 1".
    static func title(_ base: String, acting: Int, blocked: Int) -> String {
        guard blocked > 0 else { return base }
        let senders = blocked == 1 ? "1 sender" : "\(blocked) senders"
        return acting == 0 ? "Block \(senders)" : base + " + block \(blocked)"
    }

    /// One preview for the whole page, so one tap confirms every row.
    static func preview(_ moves: [SessionMove], twoWeeks: Int, trash: Int) -> ActionPreview {
        let base = FeedStore.putAwayPreview(moves)
        var lines = moves.isEmpty ? [] : Array(base.lines.dropLast())
        if twoWeeks > 0 { lines.append("Keeps \(twoWeeks) for \(ShortTerm.keepDays) days under Short-term, then Lovely offers to move them to Trash.") }
        if trash > 0 { lines.append("Moves \(trash) to Trash (Gmail keeps it 30 days).") }
        lines.append("Nothing is deleted for good. You have 10 seconds to undo.")
        let total = moves.count + twoWeeks + trash
        return ActionPreview(kind: .label, title: total == 1 ? "Do this one" : "Do these \(total)", lines: lines)
    }
}

// MARK: Wrap-up

struct SessionWrapScreen: View {
    let model: SessionModel
    let close: () -> Void
    var openBacklog: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.leftUnread.isEmpty ? "Inbox clear" : "Done for now").font(.lovely(.largeTitle, .bold))
                    HStack(spacing: 10) {
                        stat(model.replies, "Replies")
                        stat(model.filed, "Filed")
                        stat(model.archived, "Archived")
                        if model.trashed > 0 { stat(model.trashed, "Trashed") }
                    }
                    if !model.drawerSummary.isEmpty {
                        Text(model.drawerSummary).font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
                    }
                    if model.datesAdded > 0 {
                        Label(model.datesAdded == 1 ? "1 date added to your calendar" : "\(model.datesAdded) dates added to your calendar",
                              systemImage: "calendar").font(.lovely(.callout))
                    }
                    if !model.leftUnread.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LEFT UNREAD ON PURPOSE").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                            ForEach(model.leftUnread.prefix(5)) { item in
                                Text("\(item.message.fromName): \(item.message.subject)").font(.lovely(.callout)).lineLimit(1)
                            }
                            if model.leftUnread.count > 5 {
                                Text("and \(model.leftUnread.count - 5) more").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                            }
                        }
                    }
                    if !model.plan.carried.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOU PROMISED").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                            ForEach(model.plan.carried.prefix(5), id: \.id) { p in
                                Text("\(p.recipient): \u{201C}\(p.text)\u{201D}").font(.lovely(.callout)).lineLimit(2)
                            }
                        }
                    }
                }
                .padding(20)
            }
            VStack(spacing: 10) {
                Button("Done") { close() }.buttonStyle(SessionButtonStyle()).accessibilityIdentifier("session.done")
                if let openBacklog {
                    Button(model.backlog ? "Clear the next page" : "Clear older mail too") { openBacklog() }
                        .font(.lovely(.subheadline, .medium)).frame(minHeight: 44).foregroundStyle(CalmStyle.blue)
                        .accessibilityIdentifier("session.backlog.next")
                }
            }
            .padding(20)
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.lovely(.title, .bold))
            Text(label).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: Say what to do (Sprint 7 step 3)

/// One engine's proposal for the current email. In compare mode there are two, side by side.
struct SessionProposal: Identifiable, Equatable {
    var engine: EngineKind
    var action: SessionAction
    var say: String
    /// "Instant" for the built-in quick commands.
    var quick = false
    var id: String { engine.rawValue + (quick ? "-quick" : "") }
    var label: String { quick ? "Instant" : engine.name }
}

struct SessionHandoffOffer: Identifiable {
    let id = UUID().uuidString
    let task: String
    let item: SessionItem
}

extension SessionItemScreen {
    private var ownerName: String { let n = store.me.firstName; return n == "You" ? "" : n }

    /// What came back from the engine, in the scroll area above the bar.
    @ViewBuilder func askResults(_ item: SessionItem, _ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // His words, like a sent message, so it is clear they went somewhere.
            ForEach(Array(askHistory.enumerated()), id: \.offset) { _, said in
                Text(said).font(.lovely(.body)).foregroundStyle(CalmStyle.onBlue)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 48)
                    .accessibilityLabel("You said: " + said)
            }
            if thinking { ProgressView().frame(maxWidth: .infinity) }
            if let askNote {
                Text(askNote).font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
            }
            ForEach(proposals) { p in proposalCard(p, item, post, comparing: proposals.count > 1) }
            if !proposals.isEmpty, mode == .drawers {
                Button("Not that, show the drawers") { clearAsk() }
                    .font(.lovely(.subheadline, .medium)).frame(minHeight: 44).foregroundStyle(CalmStyle.blue)
            }
        }
        .id("session.askResults")
    }

    func clearAsk() { proposals = []; askNote = nil; askHistory = []; askResetCount += 1 }

    private func hint(_ item: SessionItem) -> String {
        let base = item.message.isPerson ? "Try \u{201C}tell \(item.message.fromName.split(separator: " ").first.map(String.init) ?? "them") Thursday works\u{201D} or \u{201C}file it in People\u{201D}." : "Try \u{201C}Kids\u{201D}, \u{201C}later tomorrow\u{201D}, \u{201C}archive\u{201D} or \u{201C}delete\u{201D}."
        return base + " Tap the mic on the keyboard to talk."
    }

    private func ask(_ text: String, _ item: SessionItem, _ post: Post) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, !thinking else { return }
        lastSaid = said
        askNote = nil
        proposals = []
        // Sent: show it as his bubble and empty the field (it used to stay there, so the send looked lost).
        let earlier = askHistory
        askHistory.append(said)
        askResetCount += 1
        // "text Julia", "text my wife about this": open Messages with a short summary (he taps Send there).
        if TextAbout.isTextRequest(said) { textAboutFromAsk = post; askHistory.removeLast(); return }
        let kids = store.sessionKids
        if let quick = SessionQuickCommands.parse(said, kids: kids, fromPerson: item.message.isPerson) {
            proposals = [SessionProposal(engine: .apple, action: SessionCommandValidator.validate(quick, item: item, kids: kids),
                                         say: quick.say ?? "", quick: true)]
            return
        }
        // Earlier lines about this email go with the new one, so a follow-up keeps its context.
        let context = earlier.isEmpty ? said : (earlier + [said]).joined(separator: "\n")
        let request = EngineRouter.request(for: item, said: context, ownerName: ownerName, kids: kids, examples: SessionExampleStore().examples)
        thinking = true
        Task {
            // Apple Intelligence on this iPhone. If it can't, say so; a task that needs the web comes back as a hand-off.
            do {
                let answer = try await EngineRouter.engine().interpret(request)
                proposals = [SessionProposal(engine: .apple, action: SessionCommandValidator.validate(answer.command, item: item, kids: kids),
                                             say: answer.command.say ?? "")]
            } catch {
                // Apple can't do it here: say so, and offer Hand to Grok with his own words rather than dropping it.
                askNote = error.localizedDescription
                proposals = [SessionProposal(engine: .apple, action: .handoff(task: said), say: "")]
            }
            thinking = false
        }
    }

    @ViewBuilder private func proposalCard(_ p: SessionProposal, _ item: SessionItem, _ post: Post, comparing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if comparing || !p.quick {
                Text(p.label.uppercased()).font(.lovely(.caption2, .bold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            }
            if !p.say.isEmpty { Text(p.say).font(.lovely(.callout)) }
            if case .reply(let text, _) = p.action {
                Text(text).font(.lovely(.body)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CalmStyle.bubble, in: RoundedRectangle(cornerRadius: 12))
            }
            proposalButton(p, item, post, comparing: comparing)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func proposalButton(_ p: SessionProposal, _ item: SessionItem, _ post: Post, comparing: Bool) -> some View {
        let said = lastSaid
        let pick: () -> Void = {
            SessionExampleStore().record(said: said, action: Self.actionName(p.action), drawer: Self.drawerName(p.action))
            clearAsk()
        }
        switch p.action {
        case .reply(let text, let drawer):
            if store.canSendSessionReply(post) {
                SessionConfirmButton(title: p.action.title,
                                     previews: [FeedStore.replyPreview(post, body: text), FeedStore.replyFilingPreview(post, drawer: drawer)],
                                     prominent: !comparing || p.engine == proposals.first?.engine, identifier: "session.proposal.send") { approvals in
                    pick()
                    store.sendSessionReply(post, body: text, drawer: drawer, tags: filedMove(item, drawer).tags, confirmed: approvals[0], filing: approvals[1],
                                           onReturn: { [model] ids in model.reopen(ids) })
                    model.record(item.id, .replied); model.advance()
                }
            } else {
                Button("Edit and finish in Gmail") { pick(); draft = text; openInGmail(post) }.buttonStyle(SessionButtonStyle(prominent: false))
            }
        case .putAway(let d):
            let move = filedMove(item, d)
            SessionConfirmButton(title: p.action.title, previews: [FeedStore.putAwayPreview([move])], identifier: "session.proposal.putAway") { approvals in
                pick(); put(move, approvals[0])
            }
        case .addDateThenPutAway(let d):
            dateButton(item, post, d)
        case .archive:
            let move = SessionMove(messageID: item.id, drawer: nil)
            SessionConfirmButton(title: p.action.title, previews: [FeedStore.putAwayPreview([move])], identifier: "session.proposal.archive") { approvals in
                pick(); put(move, approvals[0])
            }
        case .later(let when):
            Button(p.action.title) {
                pick()
                let options = LaterSchedule.options(now: Date())
                let chosen = options.first { $0.title.lowercased() == when } ?? options.first
                if let chosen { store.putOff(post, until: chosen.date) }
                model.record(item.id, .leftUnread); model.advance()
            }.buttonStyle(SessionButtonStyle())
        case .leaveUnread:
            Button(p.action.title) { pick(); model.record(item.id, .leftUnread); model.advance() }.buttonStyle(SessionButtonStyle())
        case .trash:
            Button(p.action.title) {
                pick(); store.sessionTrash(post)
                model.record(item.id, .trashed); model.advance()
            }.buttonStyle(SessionButtonStyle()).accessibilityIdentifier("session.proposal.trash")
        case .skip:
            Button(p.action.title) { pick(); model.skip(item.id) }.buttonStyle(SessionButtonStyle())
        case .handoff(let task):
            Button("Hand to Grok: \(task)") {
                pick()
                handoff = SessionHandoffOffer(task: task, item: item)
            }.buttonStyle(SessionButtonStyle()).lineLimit(3)
        case .search(let query):
            // Reading, not changing: it runs at once, on the phone, and the results stay here.
            GmailSearchResults(query: query)
        case .unclear:
            EmptyView()
        }
    }

    static func actionName(_ a: SessionAction) -> String {
        switch a {
        case .reply: return "reply"
        case .putAway: return "put_away"
        case .addDateThenPutAway: return "add_date"
        case .later: return "later"
        case .leaveUnread: return "leave_unread"
        case .archive: return "archive"
        case .trash: return "trash"
        case .skip: return "skip"
        case .handoff: return "handoff"
        case .search: return "search"
        case .unclear: return "unclear"
        }
    }

    static func drawerName(_ a: SessionAction) -> String? {
        switch a {
        case .reply(_, let d), .putAway(let d), .addDateThenPutAway(let d): return d.engineName
        default: return nil
        }
    }
}

/// Hand a session task to Grok Bot (owner, Nov 11, 2026): the task in his words, the email's sender and subject as
/// the only facts, and nothing at all for health mail. His report comes back under Grok reports.
struct SessionHandoffSheet: View {
    let offer: SessionHandoffOffer
    let sent: () -> Void

    var body: some View {
        let m = offer.item.message
        let blocked = !HandoffPrompt.isAllowed(address: m.fromAddress, name: m.fromName, subject: m.subject, sensitive: m.isHealth)
        HandToGrokSheet(task: offer.task, facts: GrokHandoff.facts(from: m.fromName, subject: m.subject, isHealth: blocked),
                        blocked: blocked, onSent: sent)
    }
}

/// The ask field, in its own view with its own text, so typing redraws only this field and not the email above it.
struct SessionAskField: View {
    let hint: String
    let thinking: Bool
    let onFocus: (Bool) -> Void
    let onAsk: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var canSend: Bool { !thinking && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Or say what to do", text: $text, axis: .vertical)
                    .lineLimit(1...5).submitLabel(.go).focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(CalmStyle.pageGround, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(CalmStyle.divider, lineWidth: 1))
                    .onSubmit(send)
                    .accessibilityIdentifier("session.ask")
                Button(action: send) {
                    Image(systemName: thinking ? "ellipsis" : "arrow.up").font(.lovely(.body, .bold))
                        .frame(width: 46, height: 46).foregroundStyle(CalmStyle.onBlue)
                        .background(CalmStyle.blue, in: Circle())
                }
                .disabled(!canSend).opacity(canSend ? 1 : 0.5)
                .accessibilityLabel("Go").accessibilityIdentifier("session.ask.go")
            }
            if focused, text.isEmpty {
                Text(hint).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
        }
        .onChange(of: focused) { _, now in onFocus(now) }
        // A multi-line field takes Return as a new line; treat it as Go instead.
        .onChange(of: text) { _, new in
            if new.contains("\n") { text = new.replacingOccurrences(of: "\n", with: " "); send() }
        }
    }

    private func send() {
        guard canSend else { return }
        focused = false
        onAsk(text)
    }
}
