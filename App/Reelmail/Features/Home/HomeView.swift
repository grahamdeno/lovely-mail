import SwiftUI

private enum HomeStyle {
    static let background = Color(hex: 0xF7F6F2)
    static let ink = Color(hex: 0x202827)
    static let secondary = Color(hex: 0x626C69)
    static let accent = Color(hex: 0x176B63)
    static let attention = Color(hex: 0x956018)
    static let divider = Color(hex: 0xE4E8E3)
}

struct HomeView: View {
    @Environment(FeedStore.self) private var store

    private var requests: [Post] { store.visiblePosts.filter { $0.summary.needsReply } }
    private var updates: [Post] {
        store.visiblePosts.filter { !$0.summary.needsReply && $0.summary.category != .newsletter }
    }
    private var reading: [Post] {
        store.visiblePosts.filter { !$0.summary.needsReply && $0.summary.category == .newsletter }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HomeHeader()

                if let error = store.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Mail needs attention", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(error).font(.subheadline)
                        Text("Displayed messages may not represent your connected inbox.")
                            .font(.caption)
                    }
                    .foregroundStyle(HomeStyle.attention)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }

                if store.isLoading {
                    ProgressView("Loading mail…")
                        .frame(maxWidth: .infinity)
                }
                if store.isSummarizing {
                    Label("Refining summaries on this device", systemImage: "text.alignleft")
                        .font(.caption).foregroundStyle(HomeStyle.secondary)
                }

                if store.lens != nil || store.chip != .forYou {
                    Button {
                        store.lens = nil
                        store.chip = .forYou
                    } label: {
                        Label("Show all loaded mail", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .font(.subheadline).foregroundStyle(HomeStyle.accent)
                    .frame(minHeight: 44)
                }

                section("Needs your reply", posts: requests)
                section("Updates", posts: updates)
                section("Reading", posts: reading)

                if !store.isLoading && store.errorMessage == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2).foregroundStyle(HomeStyle.accent)
                        Text(store.visiblePosts.isEmpty ? "No messages in this view" : "That’s the loaded mail")
                            .font(.headline)
                        Text("This view is not your complete email history.")
                            .font(.caption).foregroundStyle(HomeStyle.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
            .padding(20)
        }
        .background(HomeStyle.background)
        .foregroundStyle(HomeStyle.ink)
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private func section(_ title: String, posts: [Post]) -> some View {
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(posts.count.formatted()).font(.subheadline)
                        .foregroundStyle(HomeStyle.secondary)
                }
                ForEach(posts) { post in CompactMailCard(post: post) }
            }
        }
    }
}

struct HomeHeader: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("reelmail").font(.title2.weight(.bold))
                    .foregroundStyle(HomeStyle.accent)
                Spacer()
                Button { router.tab = .profile } label: {
                    AvatarView(person: store.me, size: 36)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Account and settings")
            }
            Text("A little less to think about.")
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Label(store.mode == .sample ? "Demo · fictional emails" : "Gmail · read-only",
                  systemImage: store.mode == .sample ? "rectangle.stack" : "lock")
                .font(.caption.weight(.medium))
                .foregroundStyle(HomeStyle.secondary)
            Text("Summaries can be imperfect. Open the original when details matter.")
                .font(.caption).foregroundStyle(HomeStyle.secondary)
        }
    }
}

private struct CompactMailCard: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { router.open(.thread(post.email.from)) } label: {
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(person: post.email.from, size: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.email.from.name).font(.subheadline.weight(.semibold))
                        Text(post.email.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(HomeStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption)
                        .foregroundStyle(HomeStyle.secondary)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open loaded conversation with \(post.email.from.name)")

            Button {
                store.markRead(post)
                router.open(.email(post.id))
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(post.summary.sensitive ? "Private message" : post.summary.headline)
                        .font(.headline)
                    Text(post.summary.sensitive ? "Open the original to view private details." : post.summary.blurb)
                        .font(.subheadline).foregroundStyle(HomeStyle.secondary)
                    HStack(spacing: 6) {
                        if post.summary.needsReply {
                            Label("Possible reply needed", systemImage: "arrowshape.turn.up.left")
                                .foregroundStyle(HomeStyle.attention)
                        } else {
                            Text(post.summary.category.label).foregroundStyle(HomeStyle.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").foregroundStyle(HomeStyle.accent)
                    }
                    .font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the source email")
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(HomeStyle.divider, lineWidth: 1)
        }
        .foregroundStyle(HomeStyle.ink)
    }
}
