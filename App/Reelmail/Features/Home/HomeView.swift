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
    private let filters = ["All mail", "Possible replies", "Updates", "Reading"]
    private var topics: [MailTopic] {
        store.topics.filter { topic in
            let reading = topic.latest.summary.category == .newsletter || (store.mode == .sample && topic.posts.contains {
                store.demoRules.decision(messageID: $0.id, sender: $0.email.from.email).destination == .reading
            })
            switch filter {
            case 1: return topic.possibleReply
            case 2: return !topic.possibleReply && !reading
            case 3: return reading
            default: return true
            }
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HomeHeader(onFiltered: { showingFiltered = true })
                Menu {
                    Picker("Mail view", selection: $filter) {
                        ForEach(filters.indices, id: \.self) { index in Text(filters[index]).tag(index) }
                    }
                } label: {
                    HStack(spacing: 6) { Text(filters[filter]); Image(systemName: "chevron.down").font(.caption) }
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }.accessibilityLabel("Mail view: " + filters[filter])
                if let error = store.errorMessage { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline) }
                if store.mode == .sample, let error = store.demoRules.persistenceError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.subheadline)
                }
                if store.isLoading { ProgressView("Loading mail…") }
                if store.isSummarizing { Text("Updating summaries…").font(.caption).foregroundStyle(CalmStyle.secondary) }
                if store.lens != nil || store.chip != .forYou {
                    Button("Show all loaded mail") { store.lens = nil; store.chip = .forYou }.frame(minHeight: 44)
                }
                ForEach(topics) { topic in TopicCard(topic: topic) }
                if !store.isLoading && topics.isEmpty {
                    Text("Nothing in this view.").font(.subheadline).padding(.vertical, 24)
                }
                DisclosureGroup("About this view") {
                    Text("Only loaded mail is included. Topics are grouped by thread and sender. Excerpts are selected source text; AI summaries may be imperfect. A reply does not prove a request is complete. Live Gmail sent history is not imported yet.")
                        .font(.caption).padding(.top, 8)
                }.font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 8)
            }.padding(20)
        }.background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
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
                Text(store.mode == .sample ? "Demo · fictional mail" : "Partial Gmail history · read-only")
                    .font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            Spacer()
            Menu {
                Button("Account and settings") { router.tab = .profile }
                if store.mode == .sample {
                    Button("Filtered demo mail (\(store.filteredDemoPosts.count))", action: onFiltered)
                }
            } label: {
                CalmAvatar(person: store.me, size: 36).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Account and mail options")
        }
    }
}

private struct TopicCard: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let topic: MailTopic
    var body: some View {
        let preview = topic.preview
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CalmAvatar(person: topic.person, size: 32)
                Text(topic.person.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(MailTime.label(topic.updatedAt)).font(.caption).foregroundStyle(CalmStyle.secondary)
                if topic.posts.contains(where: { $0.email.isUnread }) {
                    Circle().fill(CalmStyle.blue).frame(width: 6, height: 6).accessibilityLabel("Unread locally")
                }
            }
            Button { router.open(.thread(topic.person)) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(topic.title).font(.headline)
                    Text(preview.text).font(.body).fixedSize(horizontal: false, vertical: true)
                    if let reply = topic.replyContext {
                        Text(reply).font(.caption).foregroundStyle(CalmStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint("Opens the conversation and original messages")
            HStack {
                if let label = preview.label { Text(label).font(.caption2).foregroundStyle(CalmStyle.secondary) }
                Spacer()
                Menu {
                    Section("Source emails") {
                        ForEach(topic.posts) { post in
                            Button(topic.sensitive ? "Source · " + MailTime.label(post.email.date) : post.email.subject + " · " + MailTime.label(post.email.date)) {
                                store.markRead(post); router.open(.email(post.id))
                            }
                        }
                    }
                    if store.mode == .sample {
                        Section("Saved demo rules · no Gmail changes") {
                            Button("Filter this demo sender") { store.demoRules.setSender(topic.person.email, destination: .filtered) }
                            Button("Keep this demo sender in Reading") { store.demoRules.setSender(topic.person.email, destination: .reading) }
                            Button("Remove demo sender rule") { store.demoRules.setSender(topic.person.email, destination: nil) }
                        }.disabled(store.demoRules.persistenceError != nil)
                    }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Sources and organization")
            }.padding(.top, -4)
        }.padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
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
