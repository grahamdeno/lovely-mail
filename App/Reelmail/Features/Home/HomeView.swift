import SwiftUI

/// Lovely's palette. Light mode is the LifeOS look (owner, Nov 12, 2026): greige ground, light cards, black for
/// everything you tap, orange for Waiting on you, purple for done. Dark and Neon are unchanged.
/// Earlier source of truth: Design/Brand/README.md.
/// Each color has a light (letter paper) and dark (airmail at night) value and follows the iPhone's appearance.
/// Neon (owner, Nov 9): dark mode's surfaces and text, with cool neon accents: electric cyan for everything you can
/// tap, hot magenta for Waiting on you, violet in the stripe, lime for Done.
enum CalmStyle {
    /// Letter paper.
    static let background = Color(light: 0xEAE2D9, dark: 0x17161A, neon: 0x121116)
    /// Cards, pills and fields that sit on the background.
    static let card = Color(light: 0xF6F2EE, dark: 0x25232A, neon: 0x211F27)
    static let ink = Color(light: 0x141414, dark: 0xF2EFEA, neon: 0xF2EFEA)
    static let secondary = Color(light: 0x5F5650, dark: 0xA9A3AC, neon: 0xA9A3AC)
    /// Airmail blue: everything you can tap. In Neon, electric cyan.
    static let blue = Color(light: 0x141414, dark: 0x5B7FE8, neon: 0x2DE2E6)
    /// Text and icons on `blue`: white, except near-black on Neon's bright cyan.
    static let onBlue = Color(light: 0xFFFFFF, dark: 0xFFFFFF, neon: 0x0B1416)
    /// Postmark rose: "Waiting on you" only. Graphics (rings, dots). In Neon, hot magenta.
    static let rose = Color(light: 0xE8552F, dark: 0xE0708A, neon: 0xFF3CAC)
    /// Postmark rose for text; passes 4.5:1 on its background in every palette.
    static let roseInk = Color(light: 0xAD3517, dark: 0xF08DA3, neon: 0xFF8FD0)
    /// Done. Swipe tint only, with white text.
    static let green = Color(light: 0x3D2A73, dark: 0x3A9D66, neon: 0x17A866)
    static let divider = Color(light: 0xDCD2C8, dark: 0x2F2D34, neon: 0x2C2A33)
    static let field = card
    static let bubble = Color(light: 0xE3DBD3, dark: 0x2B2930, neon: 0x2A2731)
    static let warning = Color(light: 0xFFF4E6, dark: 0x3A2E1F, neon: 0x332A14)
    static let warningInk = Color(light: 0x7A4A10, dark: 0xF3C98B, neon: 0xFFE066)
    /// The Undo bar: dark in every palette, with white text.
    static let toast = Color(light: 0x141414, dark: 0x3A3842, neon: 0x2E2B36)
    /// Neon's signature stripe: cyan, violet, magenta. Used for the line under the top bar.
    static let gel = LinearGradient(colors: [Color(hex: 0x2DE2E6), Color(hex: 0x9D4EDD), Color(hex: 0xFF3CAC)],
                                    startPoint: .leading, endPoint: .trailing)
}

/// The italic "lovely" wordmark. Apple's serif (New York) so nothing extra ships with the app.
struct Wordmark: View {
    var size: CGFloat = 30
    var body: some View {
        Text("lovely").font(.system(size: size, weight: .regular, design: .serif)).italic()
            .foregroundStyle(CalmStyle.blue)
            .accessibilityLabel("Lovely")
    }
}

struct CalmAvatar: View {
    let person: Person
    var size: CGFloat = 40
    /// Rose ring: this person is waiting on you. The only place besides labels that uses rose.
    var waiting = false
    /// Organizations show their company icon (when fetched); people show their Contacts photo.
    var organization = false
    var domain: String? = nil
    private var images: AvatarImages { AvatarImages.shared }

    /// The same color for the same person every time.
    static func circleColor(for person: Person) -> Color {
        let n = person.email.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return LifeColor.avatars[n % LifeColor.avatars.count]
    }

    private var picture: UIImage? {
        organization ? images.logo(for: domain ?? OrganizationKey.domain(of: person.email)) : images.contactPhoto(for: person.email)
    }

    var body: some View {
        Group {
            if let picture {
                if organization {
                    Image(uiImage: picture).resizable().scaledToFit()
                        .frame(width: size * 0.76, height: size * 0.76)
                        .frame(width: size, height: size)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
                } else {
                    // Zoomed in a little: many contact photos (initials images) carry white corners of their own.
                    Image(uiImage: picture).resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .scaleEffect(1.14)
                        .clipShape(Circle())
                }
            } else {
                // LifeOS agent circles: a solid color circle with white initials; organizations keep a soft square.
                if organization {
                    Text(person.initials).font(.lovely(size: size * 0.38, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(CalmStyle.secondary)
                        .frame(width: size, height: size)
                        .background(CalmStyle.bubble, in: RoundedRectangle(cornerRadius: size * 0.3))
                } else {
                    Text(person.initials).font(.lovely(size: size * 0.38, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .background(Self.circleColor(for: person), in: Circle())
                }
            }
        }
            .padding(waiting ? 3 : 0)
            .overlay {
                if waiting {
                    if organization { RoundedRectangle(cornerRadius: size * 0.3 + 3).strokeBorder(CalmStyle.rose, lineWidth: 1.75) }
                    else { Circle().strokeBorder(CalmStyle.rose, lineWidth: 1.75) }
                }
            }
            .accessibilityHidden(true)
    }
}

/// Quiet pill button used for row and sheet actions.
struct CalmActionStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        // Delete, remove, decline and clear buttons (role: .destructive) are rose-red, never blue.
        // LifeOS (Nov 13, 2026): the main button is a black rounded square, the rest are light cards.
        let destructive = configuration.role == .destructive
        return Group {
            if prominent {
                configuration.label
                    .font(.lovely(.callout, .medium))
                    .padding(.horizontal, 16).frame(minHeight: 50)
                    .foregroundStyle(.white)
                    .lifeBlack(corner: 16)
            } else {
                configuration.label
                    .font(.lovely(.subheadline, .medium))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .foregroundStyle(destructive ? CalmStyle.roseInk : CalmStyle.ink)
                    .lifeCard(corner: 14)
            }
        }
        .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// One reversible action offered for a few seconds after a swipe.
enum UndoAction: Equatable {
    case notWaiting(Post)
    case trash(Post)
    case done(Post)
    case later(Post, Date)
    case promise(id: String, text: String)
    case waitingGone(id: String)
    var text: String {
        switch self {
        case .notWaiting: return "Moved out of Waiting on you"
        case .trash: return "Moved to Gmail Trash"
        case .done: return "Done. Marked read in Gmail"
        case .later(_, let date): return "Later: " + LaterSchedule.label(date, now: Date())
        case .promise(_, let text): return text
        case .waitingGone: return "Removed from Waiting on them"
        }
    }
    var id: String {
        switch self {
        case .notWaiting(let p): return "nw-" + p.id
        case .trash(let p): return "tr-" + p.id
        case .done(let p): return "dn-" + p.id
        case .later(let p, _): return "lt-" + p.id
        case .promise(let id, _): return "pr-" + id
        case .waitingGone(let id): return "wg-" + id
        }
    }
}

struct HomeView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var undo: UndoAction?
    @AppStorage(BriefSettings.offerSeenKey) private var briefOfferSeen = false
    @AppStorage(BriefSettings.enabledKey) private var briefEnabled = false
    @AppStorage(SplitPillBar.settingKey) private var splitPill = true

    private let rowInsets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)

    var body: some View {
        VStack(spacing: 0) {
            // Pinned: the filter pills and account button stay put while the feed scrolls.
            TopBar()
            List {
                StatusNotices()
                    .listRowInsets(rowInsets).listRowSeparator(.hidden)
                    .listRowBackground(CalmStyle.background.overlay(PullDownOnly()))   // pull down refreshes; no push up past the end

                if store.filter == .all {
                    digest(store.digest)
                } else {
                    ForEach(store.sections, id: \.section) { group in
                        SectionTitle(section: group.section, count: group.posts.count)
                            .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
                        rows(group.posts, compact: group.section != .waiting)
                    }
                }

                Group {
                    if !store.isLoading, store.sections.isEmpty { EmptyFeedNote() }
                    if !store.isLoading, !store.posts.isEmpty {
                        Text(footerText).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).padding(.vertical, 20)
                    }
                }
                .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .refreshable { await store.load(); await store.refreshShortTermExpired(force: true) }
            .safeAreaInset(edge: .bottom) {
                if store.filter == .all, store.mode == .gmail, !splitPill {   // with the split pill, its field is the ask field
                    AskLovelyBar(showSuggestions: store.todaySteps().filter { !$0.done }.count <= 2)
                }
            }
            .task(id: store.mode == .gmail) { await store.refreshShortTermExpired() }
        }
        .background(CalmStyle.background)
        .foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .overlay(alignment: .bottom) {
            if let action = undo {
                UndoBar(text: action.text) { perform(undo: action) }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: undo?.id)
        .onChange(of: store.lastPutOff?.post.id) { _, _ in if let item = store.lastPutOff { offer(.later(item.post, item.until)) } }
        .onChange(of: store.lastPromiseClosed?.id) { _, _ in if let item = store.lastPromiseClosed { offer(.promise(id: item.id, text: item.text)) } }
        .onChange(of: store.lastWaitingDismissed) { _, _ in if let id = store.lastWaitingDismissed { offer(.waitingGone(id: id)) } }
    }

    @ViewBuilder private func rows(_ posts: [Post], compact: Bool, showAge: Bool = false) -> some View {
        ForEach(posts) { post in
            MailRow(post: post, assessment: store.assessment(for: post), compact: compact, showAge: showAge,
                    onNotWaiting: { notWaiting(post, wholeSender: $0) }, onTrash: { trash(post) })
                .listRowInsets(rowInsets)
                .listRowBackground(CalmStyle.background)
                .listRowSeparatorTint(CalmStyle.divider)
        }
    }

    static let waitingOnHome = 2

    /// A section title that opens that section's full list.
    private func title(_ text: String, _ count: Int, rose: Bool = false, note: String? = nil, opens key: String? = nil) -> some View {
        Group {
            if let key, let note {
                // Two targets in one row: the heading opens the list, "N done today" opens what you finished.
                HStack(spacing: 8) {
                    Button { router.open(.mailList(key)) } label: { DigestTitle(text: text, count: count, rose: rose) }
                        .buttonStyle(.borderless).accessibilityHint("Shows all of them")
                    Spacer(minLength: 8)
                    Button { router.open(.mailList("done")) } label: {
                        HStack(spacing: 6) {
                            Label(note, systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                            Image(systemName: "chevron.right").font(.lovely(.caption2, .bold)).accessibilityHidden(true)
                        }
                        .font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.blue)
                        .frame(minHeight: 44).padding(.top, 18).padding(.bottom, 2).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless).accessibilityHint("Shows what you finished today")
                    .accessibilityIdentifier("home.doneToday")
                }
            } else if let key {
                Button { router.open(.mailList(key)) } label: { DigestTitle(text: text, count: count, rose: rose, note: note, chevron: true) }
                    .buttonStyle(.plain).accessibilityHint("Shows all of them")
            } else {
                DigestTitle(text: text, count: count, rose: rose, note: note)
            }
        }
        .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
    }

    /// Home: what needs you, your to-do (unread, oldest first), notes, people, organizations as groups,
    /// then older read mail in one row.
    @ViewBuilder private func digest(_ d: HomeDigest) -> some View {
        if store.mode == .sample {
            SampleMailCard()
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
                .listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        }
        // Today: up to three steps, only the first lit (owner chose design D, Nov 9).
        let older = store.sessionCandidates.isEmpty && store.mode == .gmail ? store.backlogCandidates.count : 0
        let steps = store.todaySteps()
        TodayStepsCard(steps: steps)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        if store.shortTermExpired > 0 {
            Button { router.open(.shortTermCleanup) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(CalmStyle.blue)
                    Text("\(store.shortTermExpired) short-term email\(store.shortTermExpired == 1 ? "" : "s") past \(ShortTerm.keepDays) days")
                        .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.ink)
                    Spacer(minLength: 8)
                    Text("Review").font(.lovely(.subheadline, .medium)).foregroundStyle(CalmStyle.blue)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("home.shortTermExpired")
            .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        }
        // Round 5 (owner, Nov 9): no chips. Older mail is an optional step that never counts against the day;
        // what's worth knowing is one short paragraph; the tools sit in the ask field.
        if older > 0 {
            Button { router.open(.backlog) } label: {
                HStack(spacing: 12) {
                    Circle().strokeBorder(CalmStyle.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 22, height: 22).padding(.leading, 9)
                    Text("Optional: clear \(older) older email\(older == 1 ? "" : "s")").font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
                    Spacer(minLength: 8)
                    Text("about \(max(1, Int((Double(older) * 0.08).rounded()))) min").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("home.optional.older")
            .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        }
        HomeAlsoView(sentences: alsoSentences(d, steps: steps))
            .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 4, trailing: 20))
            .listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        if !splitPill {
            ShortcutRow(items: HomeShortcuts.items(hasKids: !InsightSettings().load().kids.isEmpty))
                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 4, trailing: 20))
                .listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        }
        if store.doneToday > 0, !briefOfferSeen, !briefEnabled {
            BriefOfferCard()
                .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        }
    }

    /// The "Also" paragraph (round 5). A plain function: a view body cannot build inputs step by step.
    private func alsoSentences(_ d: HomeDigest, steps: [TodayStep]) -> [[HomeAlso.Part]] {
        let now = Date()
        let money = MoneyInsights.summary(store.insights.store, households: InsightSettings().load().households)
        let kids = InsightSettings().load().kids
        let energy = EnergyInsights.summary(store.insights.store, household: nil)
        let onToday = Set(steps.filter { $0.kind == .bill }.map(\.id))
        var i = HomeAlso.Inputs()
        i.hasKids = !kids.isEmpty
        i.kidNext = KidInsights.soonest(kids.compactMap { KidInsights.next(for: $0, mail: store.kidMail(for: $0), now: now) })
        i.energy = energy.latest.map { ($0.dollarsPerDay, $0.changePerDay) }
        let open = money.households.filter { !$0.ended }.flatMap(\.open)
        i.tracksBills = !open.isEmpty || money.households.contains { !$0.recentPayments.isEmpty }
        i.otherBills = open.compactMap { b in b.dueOn.map { (b.payee, $0) } }.filter { !onToday.contains("bill-" + $0.0.lowercased()) }
        i.billProblem = money.alarms.first?.payee
        i.datesThisWeek = ComingUp.thisWeek(store.comingUp, now: now).count
        i.todo = d.todo.count
        i.notes = d.notes.count
        i.promises = store.promises.count
        i.waitingOnThem = store.waitingOnThem.count
        i.later = store.laterPosts.count
        return HomeAlso.sentences(i, now: now)
    }

    /// What you told people you would do, from mail you sent. Up to three; the rest open from the title.
    @ViewBuilder private func youSaidYouWould() -> some View {
        let promises = store.promises
        if !promises.isEmpty {
            Button { router.open(.promises) } label: { DigestTitle(text: "You said you would", count: promises.count, chevron: true) }
                .buttonStyle(.plain).accessibilityHint("Shows all of them")
                .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
            ForEach(promises.prefix(3)) { item in
                PromiseCard(item: item)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 6, trailing: 20))
                    .listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
            }
        }
    }

    /// Your unread mail is your to-do. The oldest is "Next up", one decision at a time; a few more follow.
    @ViewBuilder private func todo(_ todo: [Post]) -> some View {
        let done = store.doneToday
        let note = done > 0 ? "\(done) done today" : nil
        if let next = todo.first {
            title("To do", todo.count, note: note, opens: "todo")
            NextUpCard(post: next, onTrash: { trash(next) })
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 6, trailing: 20))
                .listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
            rows(Array(todo.dropFirst().prefix(4)), compact: true, showAge: true)
            if todo.count > 5 {
                Button { router.open(.mailList("todo")) } label: {
                    Text("\(todo.count - 5) more unread").font(.lovely(.subheadline, .medium)).foregroundStyle(CalmStyle.blue)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
            }
        } else if !store.isLoading, !store.posts.isEmpty {
            title("To do", 0, note: note, opens: note == nil ? nil : "todo")
            Text("Nothing unread. All caught up.").font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
                .padding(.vertical, 6)
                .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
        }
    }

    private var footerText: String {
        if store.mode == .sample { return "Fictional mail for the demo." }
        var parts: [String] = []
        if let account = store.account { parts.append(account) }
        if let fetched = store.lastFetched { parts.append("updated " + MailTime.label(fetched).lowercased()) }
        parts.append(store.inboxTruncated ? "showing your most recent inbox mail; older mail stays in Gmail" : "that's all of your inbox")
        return parts.joined(separator: " · ")
    }

    private func notWaiting(_ post: Post, wholeSender: Bool) {
        store.markNotWaiting(post, wholeSender: wholeSender)
        offer(.notWaiting(post))
    }

    private func trash(_ post: Post) {
        Task { await store.moveToTrash(post) }  // the app-wide Undo bar offers Undo
    }

    /// Every Undo goes through the one app-wide bar, with the same 10 seconds as Trash and Send.
    private func offer(_ action: UndoAction) {
        _ = store.undo.enqueue(title: action.text, work: {}, undone: { perform(undo: action) })
    }

    private func perform(undo action: UndoAction) {
        switch action {
        case .notWaiting(let post): store.undoNotWaiting(post)
        case .trash(let post): Task { await store.restoreFromTrash(post) }
        case .done(let post): Task { await store.undoDone(post) }
        case .later(let post, _): store.bringBack(post.id)
        case .promise(let id, _): store.reopenPromise(id)
        case .waitingGone(let id): store.restoreWaiting(id)
        }
        undo = nil
    }
}

/// The only thing above the feed: the date and the Settings button. No title, no wordmark.
/// It stays in place while the feed scrolls. Loading shows as a thin bar; the account address and
/// "updated" time are at the end of the list.
struct TopBar: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.lovely(.subheadline, .semibold)).foregroundStyle(CalmStyle.secondary)
                    .padding(.leading, 20)
                Spacer()
                Button { router.open(.settings) } label: {
                    CalmAvatar(person: store.me, size: 36)
                        .overlay { RoundedRectangle(cornerRadius: 36 * 0.3).strokeBorder(CalmStyle.divider, lineWidth: 1) }
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .accessibilityLabel("Settings").accessibilityIdentifier("home.settings")
            }
            .padding(.top, 4)
            ZStack {
                if ThemeState.neon {
                    Rectangle().fill(CalmStyle.gel).frame(height: 2)
                } else {
                    Rectangle().fill(CalmStyle.divider).frame(height: 1)
                }
                if store.isLoading || store.isSummarizing {
                    ProgressView().progressViewStyle(.linear).tint(CalmStyle.blue)
                        .accessibilityLabel(store.isLoading ? "Checking for new mail" : "Writing summaries on this iPhone")
                }
            }.frame(height: 2).padding(.top, 4)
        }
        .background(CalmStyle.background)
    }
}

/// A Home digest heading: "NEW · 3". Rose only for Waiting on you.
struct DigestTitle: View {
    let text: String
    let count: Int
    var rose = false
    /// A quiet note on the right, such as "3 done today".
    var note: String? = nil
    var chevron = false
    var body: some View {
        HStack(spacing: 6) {
            Text(text.uppercased()).tracking(0.8)
            Text("\(count)").opacity(0.8)
            if note != nil || chevron { Spacer(minLength: 8) }
            if let note {
                Label(note, systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                    .foregroundStyle(CalmStyle.blue).textCase(nil)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.lovely(.caption2, .bold)).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .font(.lovely(.caption, .semibold))
        .foregroundStyle(rose ? CalmStyle.roseInk : CalmStyle.secondary)
        .padding(.top, 18).padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One button per organization ("National Life Group · 3"); tap to see its mail.
struct OrganizationChips: View {
    @Environment(Router.self) private var router
    @Environment(FeedStore.self) private var store
    let groups: [HomeDigest.OrganizationGroup]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(groups) { group in
                    Button { router.open(.organization(group.id)) } label: {
                        HStack(spacing: 8) {
                            CalmAvatar(person: group.posts[0].email.from, size: 22, organization: true, domain: group.domain)
                            Text(chipText(group)).font(.lovely(.subheadline, .medium)).lineLimit(1)
                        }
                            .padding(.leading, 8).padding(.trailing, 12).frame(minHeight: 36)
                            .foregroundStyle(CalmStyle.ink)
                            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    /// "Rink · Sun 9 PM" when the group has a date in the next week, else "Rink · 3".
    private func chipText(_ group: HomeDigest.OrganizationGroup) -> String {
        if let when = ComingUp.chipLabel(for: group.posts, in: store.comingUp, now: Date()) { return "\(group.name) · \(when)" }
        return "\(group.name) · \(group.posts.count)"
    }
}

/// Earlier mail, or one organization's mail, as compact rows.
struct DigestListView: View {
    @Environment(FeedStore.self) private var store
    let key: String
    private var content: (title: String, posts: [Post]) {
        let d = store.digest
        switch key {
        case "earlier": return ("Earlier", d.earlier)
        case "waiting": return ("Waiting on you", d.waiting)
        case "notes": return ("Notes to self", d.notes)
        case "todo", "new": return ("To do", d.todo)
        case "done": return ("Done today", [])
        case "people": return ("People", d.people)
        case "organizations": return ("Organizations", d.organizations.flatMap(\.posts).sorted { $0.email.date > $1.email.date })
        default: break
        }
        let id = String(key.dropFirst(4))
        let group = d.organizations.first { $0.id == id }
        return (group?.name ?? "Organization", group?.posts ?? [])
    }
    var body: some View {
        if key == "done" { DoneTodayList() } else { list }
    }

    private var list: some View {
        let c = content
        return List {
            if c.posts.isEmpty { Text("Nothing here now.").foregroundStyle(CalmStyle.secondary).listRowBackground(CalmStyle.background) }
            ForEach(c.posts) { post in
                MailRow(post: post, assessment: store.assessment(for: post), compact: key != "waiting", showAge: key == "todo",
                        onNotWaiting: { store.markNotWaiting(post, wholeSender: $0) },
                        onTrash: { Task { await store.moveToTrash(post) } })
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .lifeListRow()
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle(c.title).navigationBarTitleDisplayMode(.inline)
    }
}

/// What you finished today, from the saved records (mail that left the inbox still shows). Tap one still loaded to open it.
struct DoneTodayList: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let records = store.doneTodayRecords
        List {
            if records.isEmpty {
                Text("Nothing done yet today.").foregroundStyle(CalmStyle.secondary).listRowBackground(CalmStyle.background)
            }
            ForEach(records) { r in
                let loaded = store.sessionPost(r.id) != nil
                Button { if loaded { router.open(.email(r.id)) } } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(CalmStyle.blue).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.from).font(.lovely(.subheadline, .semibold)).lineLimit(1)
                            Text(r.subject.isEmpty ? "(no subject)" : r.subject).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                            Text("Done " + r.doneAt.formatted(date: .omitted, time: .shortened)).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .lifeListRow()
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Done today").navigationBarTitleDisplayMode(.inline)
    }
}

struct SectionTitle: View {
    let section: FeedSection
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(section.title.uppercased()).font(.lovely(.caption, .semibold)).kerning(0.6)
            Text("\(count)").font(.lovely(.caption)).opacity(0.7)
        }
        .foregroundStyle(section == .waiting ? CalmStyle.roseInk : CalmStyle.secondary)
        .padding(.top, 18).padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyFeedNote: View {
    @Environment(FeedStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.posts.isEmpty ? (store.mode == .gmail && store.lastFetched != nil ? "Your inbox is empty. Nice." : "No mail loaded yet.") : "Nothing here right now.")
                .font(.lovely(.subheadline, .medium))
            if store.mode == .gmail, store.posts.isEmpty, store.lastFetched != nil {
                Text("Pull down to check again.")
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            } else if store.filter == .waiting {
                Text("No one is waiting on a reply from you.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            } else if store.filter == .notes {
                Text("Mail from your other addresses shows here. Add them in Settings.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
        }.padding(.vertical, 24)
    }
}

struct UndoBar: View {
    let text: String
    let undo: () -> Void
    var body: some View {
        HStack {
            Text(text).font(.lovely(.subheadline))
            Spacer(minLength: 12)
            Button("Undo", action: undo).font(.lovely(.subheadline, .semibold)).foregroundStyle(Color.white)
                .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("undo.home")
        }
        .padding(.horizontal, 16)
        .foregroundStyle(Color.white)
        .background(CalmStyle.toast, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Errors and reconnect prompts above the feed.
struct StatusNotices: View {
    @Environment(FeedStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let waiting = store.waitingChanges
            if !waiting.isEmpty, store.actions != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(waiting.count) change\(waiting.count == 1 ? "" : "s") from earlier did not reach Gmail.", systemImage: "tray.and.arrow.up")
                        .font(.lovely(.subheadline))
                    SessionConfirmButton(title: "Finish them", previews: [Outbox.preview(waiting)], identifier: "home.outbox.finish") { approvals in
                        store.finishWaitingChanges(confirmed: approvals[0])
                    }
                    Button("Put them back") { store.dropWaitingChanges() }
                        .font(.lovely(.subheadline, .medium)).frame(minHeight: 44).foregroundStyle(CalmStyle.blue)
                }
                .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
            }
            if store.needsMailAccess {
                notice("Google didn't give Lovely access to your mail. Tap Reconnect, and on Google's screen tick the Gmail box (or Select all) before Continue.", button: "Reconnect Gmail")
            } else if store.needsReconnect {
                notice("Google signed you out. While Lovely is in testing this happens every 7 days. Your loaded mail is still here.", button: "Reconnect Gmail")
            } else if store.needsTrashPermission {
                notice("Lovely needs your OK to change mail in Gmail (Trash and Done). It can't send mail or delete anything for good. Reconnect and allow it.", button: "Reconnect Gmail")
            } else if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.lovely(.subheadline))
                    if store.refreshFailed {
                        Button("Try again") { Task { await store.load() } }
                            .buttonStyle(CalmActionStyle(prominent: true)).disabled(store.isLoading)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
            }
            if let error = store.rules.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            if store.isLoading, store.posts.isEmpty {
                ProgressView("Loading mail…").font(.lovely(.caption)).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .padding(.top, store.needsReconnect || store.needsTrashPermission || store.errorMessage != nil ? 10 : 0)
    }

    private func notice(_ text: String, button: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.lovely(.subheadline))
            Button(button) { Task { await store.connectGmail() } }.buttonStyle(CalmActionStyle(prominent: true))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
    }
}

/// One message in the feed: a full-width row, not a card. No buttons on the row; tap opens it.
/// Swipe right to reply. Swipe left: a short swipe shows Hide (and Not waiting); swiping all the way moves it to Trash.
struct MailRow: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let post: Post
    let assessment: TriageAssessment
    /// One line of preview, smaller avatar, no headline: for New, People, organizations and Earlier.
    var compact = false
    /// In the to-do, show how long it has waited ("3 weeks") instead of the date.
    var showAge = false
    var onNotWaiting: (Bool) -> Void = { _ in }
    var onTrash: () -> Void = {}

    private var section: FeedSection { assessment.section }
    private var sensitive: Bool { ConversationPresentation.isSensitive(post.email, summary: post.summary) }
    private var fromPerson: Bool { !store.isAutomated(post) && section != .notes }
    private var waiting: Bool { section == .waiting }
    private var preview: String {
        if sensitive { return "Open to read." }
        if waiting, let ask = assessment.ask { return "\u{201C}" + ask + "\u{201D}" }
        return post.summary.blurb
    }

    var body: some View {
        // Opening never marks mail read. Unread is your to-do; Done is the only thing that clears it.
        Button { router.open(.email(post.id)) } label: {
            if compact { compactBody } else { fullBody }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mail.row." + post.id)
        .modifier(MailRowActions(post: post, assessment: assessment, fromPerson: fromPerson, waiting: waiting,
                                 onNotWaiting: onNotWaiting, onTrash: onTrash))
    }

    /// Organizations name their section ("Rink · Coming up") so you know why it's there.
    private var compactName: String {
        guard !fromPerson, section != .notes else { return post.email.from.name }
        return HomeDigest.organizationName(post.email.from) + " · " + section.title
    }

    /// "Later · tomorrow 9 AM" for mail you put off, so Search and lists show why it left Home.
    private var laterText: String? {
        guard let until = store.laterUntil[post.id], LaterSchedule.isPending(until, now: Date()) else { return nil }
        return "Later \u{00B7} " + LaterSchedule.label(until, now: Date())
    }

    private var compactBody: some View {
        HStack(alignment: .top, spacing: 12) {
            CalmAvatar(person: post.email.from, size: 30, waiting: waiting, organization: !fromPerson && section != .notes)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(compactName).font(.subheadline.weight(post.email.isUnread ? .bold : .semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(showAge ? HomeDigest.age(of: post.email.date, now: Date()) : MailTime.short(post.email.date))
                        .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1).fixedSize()
                    if post.email.isUnread { Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                }
                Text(sensitive ? "Private message" : (fromPerson ? post.summary.blurb : post.summary.headline))
                    .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                if let laterText { Label(laterText, systemImage: "clock").font(.lovely(.caption)).foregroundStyle(CalmStyle.blue).lineLimit(1) }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var fullBody: some View {
            HStack(alignment: .top, spacing: 12) {
                CalmAvatar(person: post.email.from, size: 36, waiting: waiting, organization: !fromPerson && section != .notes)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(post.email.from.name).font(.subheadline.weight(post.email.isUnread ? .bold : .semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MailTime.short(post.email.date)).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1).fixedSize()
                        if post.email.isUnread { Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                    }
                    Text(sensitive ? "Private message" : post.summary.headline)
                        .font(.lovely(.subheadline, .medium)).lineLimit(1)
                    Text(preview)
                        .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let laterText { Label(laterText, systemImage: "clock").font(.lovely(.caption)).foregroundStyle(CalmStyle.blue).lineLimit(1) }
                    if waiting {
                        Text(assessment.reason).font(.lovely(.caption, .medium)).foregroundStyle(CalmStyle.roseInk).lineLimit(1)
                    } else if !post.summary.dates.isEmpty, !sensitive {
                        Label(post.summary.dates.prefix(2).joined(separator: " · "), systemImage: "calendar")
                            .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
    }
}

/// Swipes and the long-press menu, shared by full and compact rows.
private struct MailRowActions: ViewModifier {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let post: Post
    let assessment: TriageAssessment
    let fromPerson: Bool
    let waiting: Bool
    let onNotWaiting: (Bool) -> Void
    let onTrash: () -> Void
    private var section: FeedSection { assessment.section }

    func body(content: Content) -> some View {
        content
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if fromPerson {
                Button { router.draftPostID = post.id } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                    .tint(CalmStyle.blue)
            }
            if post.email.isUnread {
                Button { Task { await store.markDone(post) } } label: { Label("Done", systemImage: "checkmark") }
                    .tint(CalmStyle.green)
            }
        }
        // First button = the full swipe. Short swipe reveals all of them.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onTrash) { Label("Trash", systemImage: "trash") }
            Button { store.hide(post) } label: { Label("Hide", systemImage: "eye.slash") }.tint(CalmStyle.secondary)
            if post.email.isUnread, let tomorrow = LaterSchedule.options(now: Date()).first(where: { $0.title == "Tomorrow" }) {
                Button { store.putOff(post, until: tomorrow.date) } label: { Label("Later", systemImage: "clock") }.tint(CalmStyle.blue)
            }
            if waiting {
                Button { onNotWaiting(false) } label: { Label("Not waiting", systemImage: "checkmark.circle") }.tint(CalmStyle.roseInk)
            }
        }
        .contextMenu {
            Section("Why it's here: " + assessment.reason) {
                if fromPerson {
                    Button { router.draftPostID = post.id } label: { Label("Draft reply", systemImage: "arrowshape.turn.up.left") }
                    Button { router.open(.thread(post.email.from)) } label: { Label("Conversation with \(post.email.from.firstName)", systemImage: "bubble.left") }
                }
            }
            if post.email.isUnread {
                Section {
                    Button { Task { await store.markDone(post) } } label: { Label("Done (mark read in Gmail)", systemImage: "checkmark.circle") }
                }
            }
            Section {
                if waiting {
                    Button { onNotWaiting(false) } label: { Label("Not waiting on me", systemImage: "checkmark.circle") }
                    Button { onNotWaiting(true) } label: { Label("Never put \(post.email.from.firstName) in Waiting", systemImage: "person.crop.circle.badge.checkmark") }
                } else if store.isMarkedNotWaiting(post) {
                    Button { store.undoNotWaiting(post) } label: { Label("Put back in Waiting", systemImage: "arrow.uturn.backward") }
                }
                if section == .notes, store.otherAddresses.contains(post.email.from.email.lowercased()) {
                    Button { store.removeOtherAddress(post.email.from.email) } label: { Label("This isn't my address", systemImage: "person.crop.circle.badge.xmark") }
                } else if fromPerson, section != .notes {
                    Button { store.addOtherAddress(post.email.from.email) } label: { Label("This is another address of mine", systemImage: "person.crop.circle.badge.checkmark") }
                }
            }
            Section {
                Button { store.hide(post) } label: { Label("Hide in Lovely", systemImage: "eye.slash") }
                Button { store.setSenderRule(post.email.from.email, destination: .reading) } label: { Label("Treat as a newsletter (hides its dates)", systemImage: "newspaper") }
                Button { store.filterSender(post.email.from.email) } label: { Label("Filter this sender", systemImage: "line.3.horizontal.decrease.circle") }
                Button { store.setSenderRule(post.email.from.email, destination: nil) } label: { Label("Remove sender rule", systemImage: "arrow.uturn.backward") }
            }
            Section {
                Button(role: .destructive, action: onTrash) { Label("Move to Gmail Trash", systemImage: "trash") }
            }
        }
        .accessibilityHint(waiting ? "Waiting on you. Swipe right to reply, swipe left to hide, mark not waiting or move to Trash."
                           : post.email.isUnread ? "On your to-do. Swipe right for Done, swipe left to hide or move to Trash." : "Swipe left to hide or move to Trash.")
    }
}

/// Senders and messages a saved rule keeps out of the feed. Rules only affect this app.
struct FilteredMailReview: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(store.mode == .sample ? "Fictional mail. Rules change the demo only." : "Filtered senders are hidden in Lovely. A Gmail filter, if you made one, is listed in Settings > Gmail filters.").font(.lovely(.subheadline))
                    if let error = store.rules.persistenceError { Text(error).font(.lovely(.subheadline)) }
                    let senders = store.rules.filteredSenders
                    if senders.isEmpty && store.filteredPosts.isEmpty { Text("Nothing is filtered.").font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary) }
                    if !senders.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(senders, id: \.self) { sender in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sender.hasPrefix("@") ? "Everything from " + sender.dropFirst() : sender).font(.lovely(.subheadline)).lineLimit(1).truncationMode(.middle)
                                        let n = store.filteredPosts.filter { post in
                                            let from = post.email.from.email.lowercased()
                                            return sender.hasPrefix("@") ? LocalTriageRules.domainKeys(from).contains(sender) : from == sender
                                        }.count
                                        Text(n == 0 ? "No loaded mail" : "\(n) hidden").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Button("Restore") { store.unfilterSender(sender) }.buttonStyle(CalmActionStyle()).frame(minHeight: 44)
                                }.padding(.vertical, 6)
                                Divider()
                            }
                        }.padding(16).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16)).disabled(store.rules.persistenceError != nil)
                        if !store.filteredPosts.isEmpty { Text("Hidden messages").font(.lovely(.headline)).padding(.top, 4) }
                    }
                    ForEach(store.filteredPosts) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.email.from.name).font(.lovely(.headline))
                            Text(ConversationPresentation.isSensitive(post.email, summary: post.summary) ? "Private message" : post.email.subject).font(.lovely(.subheadline))
                            Text(store.rules.decision(messageID: post.id, sender: post.email.from.email).reason).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                            HStack {
                                Button("Restore sender") { store.setSenderRule(post.email.from.email, destination: nil) }.buttonStyle(CalmActionStyle())
                                Button("Keep this message") { store.setMessageRule(post.id, destination: .inbox) }.buttonStyle(CalmActionStyle())
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16)).disabled(store.rules.persistenceError != nil)
                    }
                }.padding(20)
            }.background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
                .navigationTitle("Filtered senders").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CalmStyle.blue)
    }
}

/// The oldest unread message, on its own: one decision at a time.
struct NextUpCard: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let post: Post
    var onTrash: () -> Void = {}

    private var age: TimeInterval { Date().timeIntervalSince(post.email.date) }
    private var stale: Bool { age >= HomeDigest.staleAfter }
    private var sensitive: Bool { ConversationPresentation.isSensitive(post.email, summary: post.summary) }
    private var organization: Bool { store.isAutomated(post) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { router.open(.email(post.id)) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEXT UP").font(.lovely(.caption2, .bold)).tracking(0.8).foregroundStyle(CalmStyle.blue)
                    HStack(alignment: .top, spacing: 12) {
                        CalmAvatar(person: post.email.from, size: 36, organization: organization)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(organization ? HomeDigest.organizationName(post.email.from) : post.email.from.name)
                                .font(.lovely(.subheadline, .bold)).lineLimit(1)
                            Text(sensitive ? "Private message" : post.summary.headline)
                                .font(.lovely(.subheadline, .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            if !sensitive {
                                Text(post.summary.blurb).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Text((store.isBackFromLater(post) ? "Back from Later. " : "")
                         + (stale ? "Still need this? Unread \(HomeDigest.age(of: post.email.date, now: Date()))."
                                  : "Unread \(HomeDigest.age(of: post.email.date, now: Date())).")
                    )
                        .font(.lovely(.caption, .medium)).foregroundStyle(CalmStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the message").accessibilityIdentifier("home.nextup.open")
            HStack(spacing: 8) {
                Button { Task { await store.markDone(post) } } label: { Label("Done", systemImage: "checkmark").labelStyle(AdaptiveLabelStyle()) }
                    .buttonStyle(CalmActionStyle(prominent: true)).lineLimit(1)
                    .accessibilityHint("Marks it read in Gmail").accessibilityIdentifier("home.nextup.done")
                LaterMenu(post: post) {
                    Image(systemName: "clock").font(.lovely(.body, .medium)).foregroundStyle(CalmStyle.blue)
                        .frame(minWidth: 44, minHeight: 40)
                }
                if !organization {
                    Button { router.draftPostID = post.id } label: { Label("Reply", systemImage: "arrowshape.turn.up.left").labelStyle(AdaptiveLabelStyle()) }
                        .buttonStyle(CalmActionStyle()).lineLimit(1).accessibilityIdentifier("home.nextup.reply")
                }
                Spacer(minLength: 0)
                Button(action: onTrash) {
                    Label("Trash", systemImage: "trash").labelStyle(AdaptiveLabelStyle()).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.roseInk).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("Move to Gmail Trash").accessibilityIdentifier("home.nextup.trash")
            }
        }
        .padding(14)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// First launch: says plainly that the people on Home are made up, with Connect right there.
struct SampleMailCard: View {
    @Environment(FeedStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This is sample mail. The people here are made up.").font(.lovely(.subheadline, .semibold))
            Text("Connect Gmail to see your own. Lovely reads your mail on this iPhone.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            if store.gmailConfigured {
                Button { Task { await store.connectGmail() } } label: {
                    Label("Connect Gmail", systemImage: "envelope.badge.shield.half.filled").frame(maxWidth: .infinity)
                }.buttonStyle(CalmActionStyle(prominent: true)).accessibilityIdentifier("home.connect")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Title and icon normally; icon only at the accessibility text sizes, where words would be cut off. VoiceOver still reads the title.
struct AdaptiveLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { AdaptiveLabel(configuration: configuration) }
}

private struct AdaptiveLabel: View {
    let configuration: LabelStyleConfiguration
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        if size.isAccessibilitySize { Label(configuration).labelStyle(.iconOnly) } else { Label(configuration).labelStyle(.titleAndIcon) }
    }
}
