import SwiftUI

/// Dear's Airmail palette. Source of truth: Design/Brand/README.md.
enum CalmStyle {
    /// Letter paper.
    static let background = Color(hex: 0xFBF8F4)
    static let ink = Color(hex: 0x25222A)
    static let secondary = Color(hex: 0x6D6870)
    /// Airmail blue: everything you can tap.
    static let blue = Color(hex: 0x2E58C8)
    /// Postmark rose: "Waiting on you" only. Graphics (rings, dots).
    static let rose = Color(hex: 0xD2546E)
    /// Postmark rose for text; passes 4.5:1 on letter paper.
    static let roseInk = Color(hex: 0xB8405A)
    static let divider = Color(hex: 0xECE6E2)
    static let field = Color.white
    static let bubble = Color(hex: 0xEFEBE8)
    static let warning = Color(hex: 0xFFF4E6)
    static let warningInk = Color(hex: 0x7A4A10)
}

/// The italic "dear" wordmark. Apple's serif (New York) so nothing extra ships with the app.
struct DearWordmark: View {
    var size: CGFloat = 30
    var body: some View {
        Text("dear").font(.system(size: size, weight: .regular, design: .serif)).italic()
            .foregroundStyle(CalmStyle.blue)
            .accessibilityLabel("Dear")
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

struct HomeView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showingFiltered = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HomeHeader(onFiltered: { showingFiltered = true }).padding(.bottom, 14)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(FeedFilter.allCases) { f in
                            let selected = store.filter == f
                            Button { store.filter = f } label: {
                                HStack(spacing: 6) {
                                    Text(f.title)
                                    if f == .waiting, store.waitingCount > 0 { Text("\(store.waitingCount)").opacity(0.8) }
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).frame(minHeight: 40)
                                .foregroundStyle(selected ? Color.white : CalmStyle.secondary)
                                .background(selected ? CalmStyle.blue : Color.white, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden).padding(.bottom, 8)
                StatusNotices()
                ForEach(store.sections, id: \.section) { group in
                    HStack(spacing: 6) {
                        Text(group.section.title.uppercased()).font(.caption.weight(.semibold)).kerning(0.6)
                        Text("\(group.posts.count)").font(.caption).opacity(0.7)
                    }
                    .foregroundStyle(group.section == .waiting ? CalmStyle.roseInk : CalmStyle.secondary)
                    .padding(.top, 18).padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(group.posts) { post in
                        MailRow(post: post, section: group.section)
                        Rectangle().fill(CalmStyle.divider).frame(height: 1).accessibilityHidden(true)
                    }
                }
                if !store.isLoading, store.sections.isEmpty {
                    Text(store.posts.isEmpty ? "No mail loaded yet." : "Nothing here right now.")
                        .font(.subheadline.weight(.medium)).padding(.vertical, 24)
                }
                if !store.isLoading, !store.posts.isEmpty {
                    Text(store.mode == .sample ? "Fictional mail for the demo." : (store.inboxTruncated ? "Showing the most recent Primary inbox mail. Older mail stays in Gmail." : "That's all of your Primary inbox."))
                        .font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 20)
                }
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .sheet(isPresented: $showingFiltered) { FilteredMailReview() }
        .refreshable { await store.load() }
    }
}

/// Loading, errors and reconnect prompts, in one place above the feed.
struct StatusNotices: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.needsReconnect {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Google signed you out. While Dear is in testing this happens every 7 days. Your loaded mail is still here.")
                        .font(.subheadline)
                    Button("Reconnect Gmail") { Task { await store.connectGmail() } }.buttonStyle(CalmActionStyle(prominent: true))
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
            } else if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
            }
            if let error = store.rules.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            if store.isLoading { ProgressView(store.posts.isEmpty ? "Loading mail…" : "Checking for new mail…").font(.caption) }
            else if store.isSummarizing { Text("Writing summaries on this iPhone").font(.caption).foregroundStyle(CalmStyle.secondary) }
        }
        .padding(.top, store.needsReconnect || store.errorMessage != nil || store.isLoading || store.isSummarizing ? 6 : 0)
    }
}

struct HomeHeader: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    var onFiltered: () -> Void = {}
    private var subtitle: String {
        if store.mode == .sample { return "Demo · fictional mail" }
        var parts: [String] = []
        if let account = store.account { parts.append(account) }
        if let fetched = store.lastFetched { parts.append("updated " + MailTime.label(fetched).lowercased()) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                DearWordmark().accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Account and settings") { router.tab = .profile }
                Button("Filtered senders", action: onFiltered)
                if !store.hiddenPosts.isEmpty { Button("Show hidden mail (\(store.hiddenPosts.count))") { store.restoreAll() } }
            } label: {
                CalmAvatar(person: store.me, size: 36).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Account and mail options")
        }
    }
}

/// One message in the feed: a full-width row, not a card.
struct MailRow: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let post: Post
    let section: FeedSection
    private var sensitive: Bool { ConversationPresentation.isSensitive(post.email, summary: post.summary) }
    private var showsPerson: Bool { !post.email.isAutomated }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                CalmAvatar(person: post.email.from, size: 36, waiting: section == .waiting)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(post.email.from.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MailTime.label(post.email.date)).font(.caption).foregroundStyle(CalmStyle.secondary)
                        if post.email.isUnread { Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                    }
                    Text(sensitive ? "Private message" : post.summary.headline).font(.headline).lineLimit(2)
                    Text(sensitive ? "Open the source to read private details." : post.summary.blurb)
                        .font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !post.summary.dates.isEmpty, !sensitive {
                        Label(post.summary.dates.prefix(2).joined(separator: " · "), systemImage: "calendar")
                            .font(.caption).foregroundStyle(CalmStyle.secondary)
                    }
                }
            }
            HStack(spacing: 8) {
                if section == .waiting {
                    Button { store.markRead(post); router.draftPostID = post.id } label: { Label("Draft reply", systemImage: "arrowshape.turn.up.left") }
                        .buttonStyle(CalmActionStyle(prominent: true))
                }
                if showsPerson {
                    Button { router.open(.thread(post.email.from)) } label: { Label("Conversation", systemImage: "bubble.left") }
                        .buttonStyle(CalmActionStyle())
                }
                Spacer(minLength: 0)
                Button { store.markRead(post); router.open(.email(post.id)) } label: {
                    Text("Source").font(.caption).foregroundStyle(CalmStyle.secondary).frame(minWidth: 44, minHeight: 40)
                }.buttonStyle(.plain)
            }.padding(.leading, 48)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { store.markRead(post); router.open(.email(post.id)) }
        .contextMenu {
            Button("Hide in Reelmail") { store.hide(post) }
            Button("Move this sender to Reading") { store.setSenderRule(post.email.from.email, destination: .reading) }
            Button("Filter this sender") { store.setSenderRule(post.email.from.email, destination: .filtered) }
            Button("Remove sender rule") { store.setSenderRule(post.email.from.email, destination: nil) }
        }
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
                    Text(store.mode == .sample ? "Fictional mail. Rules change the demo only." : "Saved rules change what Dear shows. Gmail is never changed.").font(.subheadline)
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
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16)).disabled(store.rules.persistenceError != nil)
                    }
                }.padding(20)
            }.background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
                .navigationTitle("Filtered senders").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CalmStyle.blue).preferredColorScheme(.light)
    }
}
