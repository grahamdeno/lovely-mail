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
            LazyVStack(alignment: .leading, spacing: 16) {
                HomeHeader()
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(["All", "Possible replies", "Updates", "Reading"].enumerated()), id: \.offset) { index, title in
                            Button { filter = index } label: {
                                Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                                    .foregroundStyle(filter == index ? Color.white : CalmStyle.secondary)
                                    .background(filter == index ? CalmStyle.blue : Color.white, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(filter == index ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                if let error = store.errorMessage { Text(error).font(.subheadline) }
                if store.mode == .sample, let error = store.demoRules.persistenceError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.subheadline)
                }
                if store.isLoading { ProgressView("Loading mail…") }
                if store.isSummarizing { Text("Refining summaries on this device").font(.caption) }
                if store.lens != nil || store.chip != .forYou {
                    Button("Show all loaded mail") { store.lens = nil; store.chip = .forYou }.frame(minHeight: 44)
                }
                ForEach(topics) { topic in TopicCard(topic: topic) }
                if !store.isLoading {
                    Text(topics.isEmpty ? "No loaded topics match this view." : "You’re through the loaded topics.")
                        .font(.subheadline.weight(.medium))
                    Text("Grouped by loaded thread and sender, not subject or matching names. Status describes loaded messages, not resolved tasks. Summaries can be imperfect.")
                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                }
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .toolbar {}
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.mode == .sample {
                Button { showingFiltered = true } label: {
                    Label("Filtered · \(store.filteredDemoPosts.count) demo messages", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption).frame(maxWidth: .infinity, minHeight: 44)
                }.background(CalmStyle.background)
            }
        }
        .sheet(isPresented: $showingFiltered) { FilteredDemoReview() }
        .refreshable { await store.load() }
    }
}

struct HomeHeader: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("reelmail").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(store.mode == .sample ? "Demo · fictional mail" : "Partial inbox · sent history not imported")
                    .font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            Spacer()
            Button { router.tab = .profile } label: {
                CalmAvatar(person: store.me, size: 36).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Account and settings")
        }
    }
}

private struct TopicCard: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let topic: MailTopic
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { router.open(.thread(topic.person)) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        CalmAvatar(person: topic.person, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(topic.person.name).font(.subheadline.weight(.semibold))
                            Text(MailTime.label(topic.updatedAt)).font(.caption).foregroundStyle(CalmStyle.secondary)
                        }
                        Spacer(minLength: 0)
                        if topic.posts.contains(where: { $0.email.isUnread }) {
                            Circle().fill(CalmStyle.blue).frame(width: 7, height: 7).accessibilityLabel("Unread locally")
                        }
                    }
                    Text(topic.sensitive ? "Private topic" : topic.origin.summary.headline).font(.headline)
                    if topic.sensitive {
                        Label("Open sources to read private details.", systemImage: "lock").font(.body)
                    } else {
                        if topic.posts.count > 1 {
                            Text(topic.origin.summary.blurb).font(.body)
                            Text(topic.origin.summary.engine == .appleIntelligence ? "Earlier · generated summary" : "Earlier · source excerpt")
                                .font(.caption).foregroundStyle(CalmStyle.secondary)
                        }
                        if let reply = topic.lastReply {
                            let preview = ConversationPresentation.preview(reply, summary: nil)
                            Text("You: " + preview.text).font(.subheadline)
                            if let label = preview.label { Text(label).font(.caption).foregroundStyle(CalmStyle.secondary) }
                        }
                        Text(topic.latest.summary.blurb).font(.body)
                        Text(topic.latest.summary.engine == .appleIntelligence ? "Latest incoming · generated summary" : "Latest incoming · source excerpt")
                            .font(.caption).foregroundStyle(CalmStyle.secondary)
                    }
                    Text(topic.status).font(.caption.weight(.medium)).foregroundStyle(CalmStyle.secondary)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint("Opens the person’s loaded conversation; source messages are also available below")
            HStack {
                Text("\(topic.posts.count + (topic.lastReply == nil ? 0 : 1)) loaded messages shown")
                    .font(.caption).foregroundStyle(CalmStyle.secondary)
                Spacer(minLength: 0)
                Menu {
                    Section("Source emails") {
                        ForEach(topic.posts) { post in
                            Button(topic.sensitive ? "Source · " + MailTime.label(post.email.date) : post.email.subject + " · " + MailTime.label(post.email.date)) {
                                store.markRead(post); router.open(.email(post.id))
                            }
                        }
                    }
                    if store.mode == .sample {
                        Section("Saved demo sender rules · no Gmail changes") {
                            Button("Filter this demo sender") { store.demoRules.setSender(topic.person.email, destination: .filtered) }
                            Button("Keep this demo sender in Reading") { store.demoRules.setSender(topic.person.email, destination: .reading) }
                            Button("Remove demo sender rule") { store.demoRules.setSender(topic.person.email, destination: nil) }
                        }.disabled(store.demoRules.persistenceError != nil)
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Topic sources and organization")
            }
        }.padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct FilteredDemoReview: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("Fictional mail only. These saved rules change the demo Home and People views, never Gmail. No learned spam classifier is active.")
                        .font(.subheadline)
                    if let error = store.demoRules.persistenceError { Text(error).font(.subheadline) }
                    if store.filteredDemoPosts.isEmpty { Text("No filtered demo messages.") }
                    ForEach(store.filteredDemoPosts) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.email.from.name).font(.headline)
                            Text(ConversationPresentation.isSensitive(post.email, summary: post.summary) ? "Private message" : post.email.subject)
                            Text(store.demoRules.decision(messageID: post.id, sender: post.email.from.email).reason).font(.caption)
                            Button("Restore this sender") { store.demoRules.setSender(post.email.from.email, destination: nil) }
                                .frame(minHeight: 44)
                            Button("Keep this message visible") { store.demoRules.setMessage(post.id, destination: .inbox) }
                                .frame(minHeight: 44)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                            .disabled(store.demoRules.persistenceError != nil)
                    }
                }.padding(20)
            }.background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
                .navigationTitle("Filtered demo mail").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CalmStyle.blue).preferredColorScheme(.light)
    }
}
