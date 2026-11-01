import Foundation
import Observation
import os

/// Loads mail (sample or read-only Gmail), summarizes it on device, and filters the feed.
@MainActor
@Observable
final class FeedStore {
    private(set) var posts: [Post] = []
    private(set) var sentByMe: [Email] = SampleData.sentByMe
    private(set) var mode: DataMode = .sample
    private(set) var isLoading = false
    private(set) var isSummarizing = false
    var errorMessage: String?

    var lens: Lens?
    var chip: FeedChip = .forYou
    private(set) var hidden: Set<String> = []

    let me: Person = SampleData.me
    let gmail: GmailService
    let photos: PhotoProvider = PlaceholderPhotoProvider()
    private let log = Logger(subsystem: "com.grahamdeno.reelmail", category: "feed")

    init(gmail: GmailService = GmailService()) {
        self.gmail = gmail
    }

    var gmailConfigured: Bool { gmail.config.isConfigured }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        var emails = SampleData.emails
        mode = .sample
        if gmail.config.isConfigured, gmail.isSignedIn {
            do {
                emails = try await gmail.fetchInbox()
                mode = .gmail
                sentByMe = []
            } catch {
                errorMessage = error.localizedDescription
                log.error("Inbox load failed; staying in sample mode")
            }
        }
        // Instant fallback summaries first, then upgrade on device if Apple Intelligence is ready.
        let fallback = FallbackSummarizer()
        posts = emails.map { Post(email: $0, summary: fallback.summarizeSync(SummaryInput(email: $0))) }
        await upgradeSummaries()
    }

    func connectGmail() async {
        do {
            try await gmail.signIn()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnectGmail() async {
        gmail.signOut()
        await load()
    }

    private func upgradeSummaries() async {
        guard ModelStatus.current.isAvailable else { return }
        isSummarizing = true
        defer { isSummarizing = false }
        AppleIntelligenceSummarizer.prewarm()
        let ai = AppleIntelligenceSummarizer()
        for index in posts.indices {
            let input = SummaryInput(email: posts[index].email)
            if let summary = try? await ai.summarize(input), index < posts.count {
                posts[index].summary = summary
            }
        }
        log.info("Upgraded \(self.posts.count, privacy: .public) summaries on device")
    }

    // MARK: Feed

    var activePosts: [Post] { posts.filter { !hidden.contains($0.id) } }

    var visiblePosts: [Post] {
        activePosts.filter { (lens?.includes($0) ?? true) && chip.includes($0) }
    }

    func posts(for lens: Lens) -> [Post] { activePosts.filter(lens.includes) }

    var unreadCount: Int { activePosts.filter(\.email.isUnread).count }
    var needsReplyPosts: [Post] { activePosts.filter(\.summary.needsReply) }

    /// People with mail, those waiting on a reply first.
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

    func posts(from person: Person) -> [Post] {
        posts.filter { $0.email.from.id == person.id }
    }

    /// Their mail plus anything I sent them, oldest first, for the DM-style thread.
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

    // MARK: Actions (local only for now; Gmail is read-only)

    func archive(_ post: Post) { hidden.insert(post.id) }
    func snooze(_ post: Post) { hidden.insert(post.id) }
    func restoreAll() { hidden.removeAll() }

    func markRead(_ post: Post) {
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].email.isUnread = false }
    }
}
