import SwiftUI

/// Lovely's Airmail palette. Source of truth: Design/Brand/README.md.
/// Each color has a light (letter paper) and dark (airmail at night) value and follows the iPhone's appearance.
enum CalmStyle {
    /// Letter paper.
    static let background = Color(light: 0xFBF8F4, dark: 0x17161A)
    /// Cards, pills and fields that sit on the background.
    static let card = Color(light: 0xFFFFFF, dark: 0x25232A)
    static let ink = Color(light: 0x25222A, dark: 0xF2EFEA)
    static let secondary = Color(light: 0x6D6870, dark: 0xA9A3AC)
    /// Airmail blue: everything you can tap. White text on it stays readable in both appearances.
    static let blue = Color(light: 0x2E58C8, dark: 0x5B7FE8)
    /// Postmark rose: "Waiting on you" only. Graphics (rings, dots).
    static let rose = Color(light: 0xD2546E, dark: 0xE0708A)
    /// Postmark rose for text; passes 4.5:1 on its background in both appearances.
    static let roseInk = Color(light: 0xB8405A, dark: 0xF08DA3)
    static let divider = Color(light: 0xECE6E2, dark: 0x2F2D34)
    static let field = card
    static let bubble = Color(light: 0xEFEBE8, dark: 0x2B2930)
    static let warning = Color(light: 0xFFF4E6, dark: 0x3A2E1F)
    static let warningInk = Color(light: 0x7A4A10, dark: 0xF3C98B)
    /// The Undo bar: dark in both appearances, with white text.
    static let toast = Color(light: 0x25222A, dark: 0x3A3842)
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
    var body: some View {
        Text(person.initials).font(.system(size: size * 0.38, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(CalmStyle.blue)
            .frame(width: size, height: size)
            .background(CalmStyle.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: size * 0.3))
            .padding(waiting ? 3 : 0)
            .overlay {
                if waiting { RoundedRectangle(cornerRadius: size * 0.3 + 3).strokeBorder(CalmStyle.rose, lineWidth: 1.75) }
            }
            .accessibilityHidden(true)
    }
}

/// Quiet pill button used for row and sheet actions.
struct CalmActionStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).frame(minHeight: 40)
            .foregroundStyle(prominent ? Color.white : CalmStyle.blue)
            .background(prominent ? CalmStyle.blue : CalmStyle.blue.opacity(0.08), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// One reversible action offered for a few seconds after a swipe.
enum UndoAction: Equatable {
    case notWaiting(Post)
    case trash(Post)
    var text: String {
        switch self {
        case .notWaiting: return "Moved out of Waiting on you"
        case .trash: return "Moved to Gmail Trash"
        }
    }
    var id: String {
        switch self {
        case .notWaiting(let p): return "nw-" + p.id
        case .trash(let p): return "tr-" + p.id
        }
    }
}

struct HomeView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showingFiltered = false
    @State private var undo: UndoAction?

    private let rowInsets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)

    var body: some View {
        VStack(spacing: 0) {
            // Pinned: the filter pills and account button stay put while the feed scrolls.
            TopBar(onFiltered: { showingFiltered = true })
            List {
                StatusNotices()
                    .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)

                ForEach(store.sections, id: \.section) { group in
                    SectionTitle(section: group.section, count: group.posts.count)
                        .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
                    ForEach(group.posts) { post in
                        MailRow(post: post, assessment: store.assessment(for: post),
                                onNotWaiting: { notWaiting(post, wholeSender: $0) }, onTrash: { trash(post) })
                            .listRowInsets(rowInsets)
                            .listRowBackground(CalmStyle.background)
                            .listRowSeparatorTint(CalmStyle.divider)
                    }
                }

                Group {
                    if !store.isLoading, store.sections.isEmpty { EmptyFeedNote() }
                    if !store.isLoading, !store.posts.isEmpty {
                        Text(footerText).font(.caption).foregroundStyle(CalmStyle.secondary).padding(.vertical, 20)
                    }
                }
                .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(CalmStyle.background)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .refreshable { await store.load() }
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
        .sheet(isPresented: $showingFiltered) { FilteredMailReview() }
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
        Task { await store.moveToTrash(post) }
        offer(.trash(post))
    }

    private func offer(_ action: UndoAction) {
        undo = action
        let id = action.id
        Task { try? await Task.sleep(for: .seconds(6)); if undo?.id == id { undo = nil } }
    }

    private func perform(undo action: UndoAction) {
        switch action {
        case .notWaiting(let post): store.undoNotWaiting(post)
        case .trash(let post): Task { await store.restoreFromTrash(post) }
        }
        undo = nil
    }
}

/// The only thing above the feed: filter pills and the account menu. No title, no wordmark.
/// It stays in place while the feed scrolls. Loading shows as a thin bar; the account address and
/// "updated" time are at the end of the list.
struct TopBar: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    var onFiltered: () -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FilterPills()
                Menu {
                    if let account = store.account { Text(account) }
                    Button("Account and settings") { router.tab = .profile }
                    Button("Filtered senders", action: onFiltered)
                    if !store.hiddenPosts.isEmpty { Button("Show hidden mail (\(store.hiddenPosts.count))") { store.restoreAll() } }
                } label: {
                    CalmAvatar(person: store.me, size: 34).frame(minWidth: 44, minHeight: 44)
                }
                .padding(.leading, 4).padding(.trailing, 12)
                .accessibilityLabel("Account and mail options")
            }
            .padding(.top, 4)
            ZStack {
                Rectangle().fill(CalmStyle.divider).frame(height: 1)
                if store.isLoading || store.isSummarizing {
                    ProgressView().progressViewStyle(.linear).tint(CalmStyle.blue)
                        .accessibilityLabel(store.isLoading ? "Checking for new mail" : "Writing summaries on this iPhone")
                }
            }.frame(height: 2).padding(.top, 4)
        }
        .background(CalmStyle.background)
    }
}

/// Filter pills. The row scrolls edge to edge so a partly visible pill reads as "more", not as clipping.
struct FilterPills: View {
    @Environment(FeedStore.self) private var store
    private var filters: [FeedFilter] {
        // "Notes to self" appears once there is something in it.
        FeedFilter.allCases.filter { $0 != .notes || store.noteCount > 0 || store.filter == .notes }
    }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filters) { f in
                    let selected = store.filter == f
                    Button { store.filter = f } label: {
                        HStack(spacing: 6) {
                            Text(f.title).lineLimit(1)
                            if f == .waiting, store.waitingCount > 0 { Text("\(store.waitingCount)").opacity(0.8) }
                            if f == .notes, store.noteCount > 0 { Text("\(store.noteCount)").opacity(0.8) }
                        }
                        .font(.subheadline.weight(.medium))
                        .fixedSize()
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .foregroundStyle(selected ? Color.white : CalmStyle.secondary)
                        .background(selected ? CalmStyle.blue : CalmStyle.card, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .contentMargins(.leading, 20, for: .scrollContent)
        .contentMargins(.trailing, 28, for: .scrollContent)
        .scrollIndicators(.hidden)
        // Pills fade out before the profile button instead of running underneath it.
        .mask(HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28)
        })
    }
}

struct SectionTitle: View {
    let section: FeedSection
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(section.title.uppercased()).font(.caption.weight(.semibold)).kerning(0.6)
            Text("\(count)").font(.caption).opacity(0.7)
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
            Text(store.posts.isEmpty ? "No mail loaded yet." : "Nothing here right now.")
                .font(.subheadline.weight(.medium))
            if store.mode == .gmail, store.posts.isEmpty, store.lastFetched != nil {
                Text("Gmail connected, but it returned no inbox mail (\(store.sentByMe.count) sent messages found). Pull down to refresh.")
                    .font(.caption).foregroundStyle(CalmStyle.secondary)
            } else if store.filter == .waiting {
                Text("No one is waiting on a reply from you.").font(.caption).foregroundStyle(CalmStyle.secondary)
            } else if store.filter == .notes {
                Text("Mail from your other addresses shows here. Add them in Profile.").font(.caption).foregroundStyle(CalmStyle.secondary)
            }
        }.padding(.vertical, 24)
    }
}

struct UndoBar: View {
    let text: String
    let undo: () -> Void
    var body: some View {
        HStack {
            Text(text).font(.subheadline)
            Spacer(minLength: 12)
            Button("Undo", action: undo).font(.subheadline.weight(.semibold)).foregroundStyle(Color.white)
                .frame(minWidth: 44, minHeight: 44)
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
            if store.needsMailAccess {
                notice("Google didn't give Lovely access to your mail. Tap Reconnect, and on Google's screen tick the Gmail box (or Select all) before Continue.", button: "Reconnect Gmail")
            } else if store.needsReconnect {
                notice("Google signed you out. While Lovely is in testing this happens every 7 days. Your loaded mail is still here.", button: "Reconnect Gmail")
            } else if store.needsTrashPermission {
                notice("Lovely needs your OK to move mail to Gmail's Trash. It can't send mail or delete anything for good. Reconnect and allow it.", button: "Reconnect Gmail")
            } else if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
            }
            if let error = store.rules.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            if store.isLoading, store.posts.isEmpty {
                ProgressView("Loading mail…").font(.caption).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .padding(.top, store.needsReconnect || store.needsTrashPermission || store.errorMessage != nil ? 10 : 0)
    }

    private func notice(_ text: String, button: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.subheadline)
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
        Button { store.markRead(post); router.open(.email(post.id)) } label: {
            HStack(alignment: .top, spacing: 12) {
                CalmAvatar(person: post.email.from, size: 36, waiting: waiting)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(post.email.from.name).font(.subheadline.weight(post.email.isUnread ? .bold : .semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MailTime.short(post.email.date)).font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(1).fixedSize()
                        if post.email.isUnread { Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                    }
                    Text(sensitive ? "Private message" : post.summary.headline)
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(preview)
                        .font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if waiting {
                        Text(assessment.reason).font(.caption.weight(.medium)).foregroundStyle(CalmStyle.roseInk).lineLimit(1)
                    } else if !post.summary.dates.isEmpty, !sensitive {
                        Label(post.summary.dates.prefix(2).joined(separator: " · "), systemImage: "calendar")
                            .font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if fromPerson {
                Button { store.markRead(post); router.draftPostID = post.id } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                    .tint(CalmStyle.blue)
            }
        }
        // First button = the full swipe. Short swipe reveals all of them.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onTrash) { Label("Trash", systemImage: "trash") }
            Button { store.hide(post) } label: { Label("Hide", systemImage: "eye.slash") }.tint(CalmStyle.secondary)
            if waiting {
                Button { onNotWaiting(false) } label: { Label("Not waiting", systemImage: "checkmark.circle") }.tint(CalmStyle.roseInk)
            }
        }
        .contextMenu {
            Section("Why it's here: " + assessment.reason) {
                if fromPerson {
                    Button { store.markRead(post); router.draftPostID = post.id } label: { Label("Draft reply", systemImage: "arrowshape.turn.up.left") }
                    Button { router.open(.thread(post.email.from)) } label: { Label("Conversation with \(post.email.from.firstName)", systemImage: "bubble.left") }
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
                Button { store.setSenderRule(post.email.from.email, destination: .reading) } label: { Label("Move sender to Reading", systemImage: "newspaper") }
                Button { store.setSenderRule(post.email.from.email, destination: .filtered) } label: { Label("Filter this sender", systemImage: "line.3.horizontal.decrease.circle") }
                Button { store.setSenderRule(post.email.from.email, destination: nil) } label: { Label("Remove sender rule", systemImage: "arrow.uturn.backward") }
            }
            Section {
                Button(role: .destructive, action: onTrash) { Label("Move to Gmail Trash", systemImage: "trash") }
            }
        }
        .accessibilityHint(waiting ? "Waiting on you. Swipe right to reply, swipe left to hide, mark not waiting or move to Trash." : "Swipe left to hide or move to Trash.")
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
                    Text(store.mode == .sample ? "Fictional mail. Rules change the demo only." : "Saved rules only change what Lovely shows. They never change Gmail.").font(.subheadline)
                    if let error = store.rules.persistenceError { Text(error).font(.subheadline) }
                    if store.filteredPosts.isEmpty { Text("Nothing is filtered.").font(.subheadline).foregroundStyle(CalmStyle.secondary) }
                    ForEach(store.filteredPosts) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.email.from.name).font(.headline)
                            Text(ConversationPresentation.isSensitive(post.email, summary: post.summary) ? "Private message" : post.email.subject).font(.subheadline)
                            Text(store.rules.decision(messageID: post.id, sender: post.email.from.email).reason).font(.caption).foregroundStyle(CalmStyle.secondary)
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
