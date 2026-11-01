import SwiftUI

enum CalmStyle {
    static let background = Color(hex: 0xF7F6F2)
    static let ink = Color(hex: 0x202827)
    static let secondary = Color(hex: 0x626C69)
    static let blue = Color(hex: 0x245FCC)
    static let divider = Color(hex: 0xE4E8E3)
}

struct CalmAvatar: View {
    let person: Person
    var size: CGFloat = 40
    var body: some View {
        Text(person.initials).font(.system(size: size * 0.38, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(CalmStyle.blue)
            .frame(width: size, height: size)
            .background(CalmStyle.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

struct HomeView: View {
    @Environment(FeedStore.self) private var store
    @State private var filter = 0
    @State private var showingFiltered = false
    private var posts: [Post] {
        store.visiblePosts.filter { post in
            let reading = post.summary.category == .newsletter || (store.mode == .sample &&
                store.demoRules.decision(messageID: post.id, sender: post.email.from.email).destination == .reading)
            switch filter {
            case 1: return post.summary.needsReply
            case 2: return !post.summary.needsReply && !reading
            case 3: return reading
            default: return true
            }
        }.sorted { $0.email.date > $1.email.date }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HomeHeader(onFiltered: { showingFiltered = true })
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(["All", "Possible replies", "Updates", "Reading"].enumerated()), id: \.offset) { index, title in
                            Button { filter = index } label: {
                                Text(title).font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .foregroundStyle(filter == index ? Color.white : CalmStyle.secondary)
                                    .background(filter == index ? CalmStyle.blue : Color.white, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(filter == index ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                if let error = store.errorMessage {
                    Label(error + " Displayed mail may be incomplete.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline).padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }
                if store.mode == .sample, let error = store.demoRules.persistenceError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.subheadline)
                }
                if store.isLoading { ProgressView("Loading mail…") }
                if store.isSummarizing {
                    Text("Refining summaries on this device").font(.caption).foregroundStyle(CalmStyle.secondary)
                }
                if store.lens != nil || store.chip != .forYou {
                    Button("Show all loaded mail") { store.lens = nil; store.chip = .forYou }
                        .frame(minHeight: 44).tint(CalmStyle.blue)
                }
                ForEach(posts) { post in CompactMailCard(post: post) }
                if !store.isLoading {
                    Text(posts.isEmpty ? "No loaded messages match this view." : "You’re through the loaded mail.")
                        .font(.subheadline.weight(.medium))
                    Text("Loaded history only. Summaries and reply suggestions may be imperfect; check the source when details matter.")
                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                }
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .sheet(isPresented: $showingFiltered) { FilteredDemoReview() }
        .refreshable { await store.load() }
    }
}

struct HomeHeader: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    var onFiltered: () -> Void = {}
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("reelmail").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(store.mode == .sample ? "Demo · fictional mail" : "Gmail · partial, read-only history")
                    .font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            Spacer()
            Menu {
                Button("Account and settings") { router.tab = .profile }
                if store.mode == .sample { Button("Filtered demo mail", action: onFiltered) }
            } label: {
                CalmAvatar(person: store.me, size: 36).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Account and mail options")
        }
    }
}

private struct CompactMailCard: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let post: Post
    private var sensitive: Bool { ConversationPresentation.isSensitive(post.email, summary: post.summary) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CalmAvatar(person: post.email.from, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.email.from.name).font(.subheadline.weight(.semibold))
                    Text(MailTime.label(post.email.date)).font(.caption).foregroundStyle(CalmStyle.secondary)
                }
                Spacer(minLength: 0)
                if post.email.isUnread {
                    Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).accessibilityLabel("Unread locally")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(sensitive ? "Private message" : post.summary.headline).font(.headline)
                Text(sensitive ? "Open the source to read private details." : post.summary.blurb)
                    .font(.body).fixedSize(horizontal: false, vertical: true)
                Text(sensitive ? "Private details hidden" : (post.summary.engine == .appleIntelligence ? "Generated summary" : "Source excerpt"))
                    .font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            if post.summary.needsReply {
                Label("Possible reply needed", systemImage: "arrowshape.turn.up.left")
                    .font(.caption.weight(.medium)).foregroundStyle(CalmStyle.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { conversationButton; sourceButton }
                VStack(alignment: .leading, spacing: 0) { conversationButton; sourceButton }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(CalmStyle.ink)
        .contextMenu {
            if store.mode == .sample {
                Button("Filter this demo sender") { store.demoRules.setSender(post.email.from.email, destination: .filtered) }
                Button("Keep this demo sender in Reading") { store.demoRules.setSender(post.email.from.email, destination: .reading) }
                Button("Remove demo sender rule") { store.demoRules.setSender(post.email.from.email, destination: nil) }
            }
        }
    }
    private var conversationButton: some View {
        Button { router.open(.thread(post.email.from)) } label: {
            Label("Conversation", systemImage: "bubble.left").font(.subheadline.weight(.medium)).frame(minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(CalmStyle.blue)
    }
    private var sourceButton: some View {
        Button { store.markRead(post); router.open(.email(post.id)) } label: {
            Text("View source").font(.caption).frame(minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(CalmStyle.secondary)
    }
}

private struct FilteredDemoReview: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("Fictional mail only. Saved rules change the demo Home and People views, never Gmail. No learned spam classifier is active.").font(.subheadline)
                    if let error = store.demoRules.persistenceError { Text(error).font(.subheadline) }
                    if store.filteredDemoPosts.isEmpty { Text("No filtered demo messages.") }
                    ForEach(store.filteredDemoPosts) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.email.from.name).font(.headline)
                            Text(ConversationPresentation.isSensitive(post.email, summary: post.summary) ? "Private message" : post.email.subject)
                            Text(store.demoRules.decision(messageID: post.id, sender: post.email.from.email).reason).font(.caption)
                            Button("Restore this sender") { store.demoRules.setSender(post.email.from.email, destination: nil) }.frame(minHeight: 44)
                            Button("Keep this message visible") { store.demoRules.setMessage(post.id, destination: .inbox) }.frame(minHeight: 44)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16)).disabled(store.demoRules.persistenceError != nil)
                    }
                }.padding(20)
            }.background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
                .navigationTitle("Filtered demo mail").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CalmStyle.blue).preferredColorScheme(.light)
    }
}
