import Foundation
import Observation

@MainActor
@Observable
final class FeedStore {
    private(set) var posts: [Post] = []
    private(set) var sentByMe: [Email] = []
    private(set) var mode: DataMode = .sample
    private(set) var isLoading = false
    private(set) var isSummarizing = false
    var errorMessage: String?
    var lens: Lens?
    var chip: FeedChip = .forYou
    private(set) var hidden: Set<String> = []

    let me: Person = SampleData.me
    let gmail: any GmailInboxClient
    let photos: PhotoProvider = PlaceholderPhotoProvider()
    private let summarizeOnDevice: Bool
    private var revision = 0

    init(gmail: (any GmailInboxClient)? = nil, summarizeOnDevice: Bool = true) {
        self.gmail = gmail ?? GmailService()
        self.summarizeOnDevice = summarizeOnDevice
    }

    var gmailConfigured: Bool { gmail.config.isConfigured }

    func load() async {
        revision += 1
        let current = revision
        isLoading = true
        isSummarizing = false
        errorMessage = nil
        defer { if revision == current { isLoading = false } }
        let emails: [Email]
        if gmail.isSignedIn || mode == .gmail {
            if mode != .gmail {
                posts = []
                hidden.removeAll()
            }
            mode = .gmail
            sentByMe = []
            guard gmailConfigured, gmail.isSignedIn else {
                errorMessage = "Gmail needs reconnecting. No demo mail has been substituted."
                return
            }
            do {
                emails = try await gmail.fetchInbox(maxResults: 30)
            } catch {
                guard current == revision else { return }
                errorMessage = "Gmail could not refresh. Previously loaded mail, if any, is unchanged. \(error.localizedDescription)"
                return
            }
            guard current == revision else { return }
        } else {
            emails = SampleData.emails
            sentByMe = SampleData.sentByMe
        }
        let fallback = FallbackSummarizer()
        posts = emails.map { Post(email: $0, summary: fallback.summarizeSync(SummaryInput(email: $0))) }
        await upgradeSummaries(revision: current)
    }

    func connectGmail() async {
        do {
            try await gmail.signIn()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func disconnectGmail() async {
        revision += 1
        gmail.signOut()
        posts = []
        sentByMe = []
        hidden.removeAll()
        lens = nil
        chip = .forYou
        mode = .sample
        await load()
    }

    private func upgradeSummaries(revision current: Int) async {
        guard summarizeOnDevice, ModelStatus.current.isAvailable, current == revision else { return }
        isSummarizing = true
        defer { if current == revision { isSummarizing = false } }
        AppleIntelligenceSummarizer.prewarm()
        let ai = AppleIntelligenceSummarizer()
        let snapshot = posts
        for post in snapshot {
            guard current == revision else { return }
            let summary = try? await ai.summarize(SummaryInput(email: post.email))
            guard current == revision else { return }
            if let summary, let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index].summary = summary
            }
        }
    }

    var activePosts: [Post] { posts.filter { !hidden.contains($0.id) } }
    var visiblePosts: [Post] { activePosts.filter { (lens?.includes($0) ?? true) && chip.includes($0) } }
    func posts(for lens: Lens) -> [Post] { activePosts.filter(lens.includes) }
    var unreadCount: Int { activePosts.filter(\.email.isUnread).count }
    var needsReplyPosts: [Post] { activePosts.filter(\.summary.needsReply) }

    var people: [Person] {
        var seen = Set<String>()
        var waiting: [Person] = []
        var rest: [Person] = []
        for post in activePosts where !post.email.from.isAutomated {
            let p = post.email.from
            guard seen.insert(p.id).inserted else { continue }
            if needsReply(p) { waiting.append(p) } else { rest.append(p) }
        }
        return waiting + rest
    }

    func needsReply(_ person: Person) -> Bool {
        activePosts.contains { $0.email.from.id == person.id && $0.summary.needsReply }
    }
    func posts(from person: Person) -> [Post] { posts.filter { $0.email.from.id == person.id } }
    func conversation(with person: Person) -> [Email] {
        let theirs = posts.filter { $0.email.from.id == person.id }.map(\.email)
        let mine = sentByMe.filter { $0.to.contains(person.email) }
        return (theirs + mine).sorted { $0.date < $1.date }
    }
    func post(for email: Email) -> Post? { posts.first { $0.id == email.id } }
    func search(_ query: String) -> [Post] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return activePosts.filter {
            $0.email.from.name.lowercased().contains(q)
                || $0.email.subject.lowercased().contains(q)
                || $0.summary.headline.lowercased().contains(q)
                || $0.email.body.lowercased().contains(q)
        }
    }

    // Existing local actions remain; persistence and action naming are separate work.
    func archive(_ post: Post) { hidden.insert(post.id) }
    func snooze(_ post: Post) { hidden.insert(post.id) }
    func restoreAll() { hidden.removeAll() }
    func markRead(_ post: Post) {
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].email.isUnread = false }
    }
}
