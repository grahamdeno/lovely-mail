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
    /// Set when Gmail needs a fresh sign-in. Loaded mail stays on screen.
    private(set) var needsReconnect = false
    private(set) var account: String?
    private(set) var lastFetched: Date?
    private(set) var inboxTruncated = false
    var errorMessage: String?
    var filter: FeedFilter = .all
    private(set) var hidden: Set<String> = []
    private(set) var seen: Set<String> = []
    let gmail: any GmailInboxClient
    /// Rules for fictional demo mail. Never applied to a real account.
    let demoRules: LocalTriageRules
    /// Rules for the signed-in account. Created when the account is known.
    private(set) var accountRules: LocalTriageRules?
    private let summarizeOnDevice: Bool
    private let triageDefaults: UserDefaults
    private let cacheStore: MailCacheStore?
    private var summaries: [String: EmailSummary] = [:]
    private var revision = 0

    init(gmail: (any GmailInboxClient)? = nil, summarizeOnDevice: Bool = true,
         triageDefaults: UserDefaults = .standard, cacheStore: MailCacheStore? = .standard) {
        self.gmail = gmail ?? GmailService()
        self.summarizeOnDevice = summarizeOnDevice
        self.triageDefaults = triageDefaults
        self.cacheStore = cacheStore
        demoRules = LocalTriageRules(accountID: "demo-home-v1", defaults: triageDefaults)
    }

    var gmailConfigured: Bool { gmail.config.isConfigured }

    /// Rules that apply to what is on screen now.
    var rules: LocalTriageRules { mode == .gmail ? (accountRules ?? demoRulesPlaceholder) : demoRules }
    /// Until the account is known, live mode has no rules; this empty, unsaved set keeps views simple.
    private var demoRulesPlaceholder: LocalTriageRules { LocalTriageRules(accountID: "unknown-account", defaults: UserDefaults(suiteName: "reelmail.transient") ?? .standard) }

    var me: Person {
        if let account { return Person(id: account, name: "You", email: account, hue: 0.62) }
        return SampleData.me
    }

    // MARK: Loading

    func load() async {
        revision += 1
        let current = revision
        isLoading = true; isSummarizing = false; errorMessage = nil
        defer { if revision == current { isLoading = false } }
        if gmail.isSignedIn || mode == .gmail {
            await loadGmail(revision: current)
        } else {
            loadSample()
            await upgradeSummaries(revision: current)
        }
    }

    private func loadSample() {
        mode = .sample; account = nil; accountRules = nil; needsReconnect = false
        sentByMe = SampleData.sentByMe
        let fallback = FallbackSummarizer()
        posts = SampleData.emails.map { Post(email: $0, summary: fallback.summarizeSync(SummaryInput(email: $0))) }
    }

    private func loadGmail(revision current: Int) async {
        if mode != .gmail { posts = []; hidden.removeAll(); seen.removeAll(); summaries = [:] }
        mode = .gmail
        if posts.isEmpty, let cached = cacheStore?.loadCurrent() { apply(cached) }
        guard gmailConfigured, gmail.isSignedIn else {
            needsReconnect = true
            errorMessage = "Gmail needs reconnecting. No demo mail has been substituted."
            return
        }
        let known = MailboxSnapshot(account: account ?? "", inbox: posts.map(\.email), sent: sentByMe, fetchedAt: lastFetched ?? .distantPast)
        let snapshot: MailboxSnapshot
        do { snapshot = try await gmail.fetchMailbox(known: known, limits: .standard) }
        catch {
            guard current == revision else { return }
            if let e = error as? GmailService.GmailError, e.needsReconnect { needsReconnect = true }
            errorMessage = "Gmail could not refresh. Previously loaded mail, if any, is unchanged. \(error.localizedDescription)"
            return
        }
        guard current == revision else { return }
        needsReconnect = false
        setAccount(snapshot.account)
        sentByMe = snapshot.sent
        lastFetched = snapshot.fetchedAt
        inboxTruncated = snapshot.inboxTruncated
        let fallback = FallbackSummarizer()
        posts = snapshot.inbox.map { email in
            Post(email: email, summary: summaries[email.id] ?? fallback.summarizeSync(SummaryInput(email: email)))
        }
        let live = Set(posts.map(\.id))
        summaries = summaries.filter { live.contains($0.key) }
        persist()
        await upgradeSummaries(revision: current)
    }

    private func apply(_ cache: MailCache) {
        setAccount(cache.snapshot.account)
        summaries = cache.summaries
        hidden = cache.hidden
        seen = cache.seen
        sentByMe = cache.snapshot.sent
        lastFetched = cache.snapshot.fetchedAt
        inboxTruncated = cache.snapshot.inboxTruncated
        let fallback = FallbackSummarizer()
        posts = cache.snapshot.inbox.map { email in
            var e = email; if cache.seen.contains(email.id) { e.isUnread = false }
            return Post(email: e, summary: cache.summaries[email.id] ?? fallback.summarizeSync(SummaryInput(email: email)))
        }
    }

    private func setAccount(_ address: String) {
        guard !address.isEmpty else { return }
        if account != address {
            account = address
            accountRules = LocalTriageRules(accountID: "gmail-" + MailCache.accountKey(address), defaults: triageDefaults)
        }
    }

    private func persist() {
        guard mode == .gmail, let account, let cacheStore else { return }
        let snapshot = MailboxSnapshot(account: account, inbox: posts.map(\.email), sent: sentByMe,
                                       fetchedAt: lastFetched ?? Date(), inboxTruncated: inboxTruncated)
        let cache = MailCache(snapshot: snapshot, summaries: summaries, hidden: hidden, seen: seen)
        do { try cacheStore.save(cache) } catch { errorMessage = "Loaded mail could not be saved on this phone. It will reload next time." }
    }

    func connectGmail() async {
        do { try await gmail.signIn(); needsReconnect = false; await load() }
        catch { errorMessage = error.localizedDescription }
    }

    func disconnectGmail() async {
        revision += 1; gmail.signOut(); cacheStore?.removeAll()
        posts = []; sentByMe = []; hidden.removeAll(); seen.removeAll(); summaries = [:]
        filter = .all; mode = .sample; account = nil; accountRules = nil; needsReconnect = false
        lastFetched = nil; inboxTruncated = false
        await load()
    }

    /// Apple Intelligence pass over posts that still carry the fallback summary. Results are saved.
    private func upgradeSummaries(revision current: Int) async {
        guard summarizeOnDevice, ModelStatus.current.isAvailable, current == revision else { return }
        let todo = posts.filter { $0.summary.engine != .appleIntelligence }
        guard !todo.isEmpty else { return }
        isSummarizing = true
        defer { if current == revision { isSummarizing = false } }
        AppleIntelligenceSummarizer.prewarm()
        let ai = AppleIntelligenceSummarizer()
        var changed = false
        for post in todo {
            guard current == revision else { return }
            let summary = try? await ai.summarize(SummaryInput(email: post.email))
            guard current == revision else { return }
            if let summary, let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index].summary = summary
                summaries[post.id] = summary
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: Reading the feed

    private var replies: [String: Date] { FeedTriage.latestReplies(in: sentByMe) }

    func section(for post: Post) -> FeedSection {
        FeedTriage.section(for: post, route: rules.decision(messageID: post.id, sender: post.email.from.email).destination, replies: replies)
    }

    /// Everything not hidden and not filtered by a rule.
    var activePosts: [Post] {
        posts.filter { !hidden.contains($0.id) && rules.decision(messageID: $0.id, sender: $0.email.from.email).destination != .filtered }
    }

    /// The feed in priority order: sections top to bottom, newest first within each.
    var sections: [(section: FeedSection, posts: [Post])] {
        let grouped = Dictionary(grouping: activePosts.filter { filter.includes(section(for: $0)) }, by: section(for:))
        return FeedSection.allCases.compactMap { s in
            guard let items = grouped[s], !items.isEmpty else { return nil }
            return (s, items.sorted { $0.email.date > $1.email.date })
        }
    }

    var waitingCount: Int { activePosts.filter { section(for: $0) == .waiting }.count }
    var topics: [MailTopic] { MailTopic.make(posts: activePosts, sent: sentByMe) }

    /// Messages a saved rule keeps out of the feed, for review and undo.
    var filteredPosts: [Post] {
        posts.filter { rules.decision(messageID: $0.id, sender: $0.email.from.email).destination == .filtered }
    }
    var filteredDemoPosts: [Post] { mode == .sample ? filteredPosts : [] }
    var hiddenPosts: [Post] { posts.filter { hidden.contains($0.id) } }
    var unreadCount: Int { activePosts.filter(\.email.isUnread).count }
    var needsReplyPosts: [Post] { activePosts.filter { section(for: $0) == .waiting } }

    var people: [Person] {
        var seenIDs = Set<String>()
        var waiting: [Person] = []; var rest: [Person] = []
        for post in activePosts where !post.email.isAutomated {
            let p = post.email.from
            guard seenIDs.insert(p.id).inserted else { continue }
            if needsReply(p) { waiting.append(p) } else { rest.append(p) }
        }
        return waiting + rest
    }
    func needsReply(_ person: Person) -> Bool {
        activePosts.contains { $0.email.from.id == person.id && section(for: $0) == .waiting }
    }
    func posts(from person: Person) -> [Post] { posts.filter { $0.email.from.id == person.id } }
    func conversation(with person: Person) -> [Email] {
        let theirs = posts.filter { $0.email.from.id == person.id }.map(\.email)
        let mine = sentByMe.filter { $0.recipients.contains(person.email) }
        return (theirs + mine).sorted { $0.date < $1.date }
    }
    func post(for email: Email) -> Post? { posts.first { $0.id == email.id } }
    func search(_ query: String) -> [Post] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return activePosts.filter {
            $0.email.from.name.lowercased().contains(q) || $0.email.subject.lowercased().contains(q)
                || $0.summary.headline.lowercased().contains(q) || $0.email.body.lowercased().contains(q)
        }.sorted { $0.email.date > $1.email.date }
    }

    // MARK: Local actions (Gmail is never changed)

    func hide(_ post: Post) { hidden.insert(post.id); persist() }
    func unhide(_ post: Post) { hidden.remove(post.id); persist() }
    func restoreAll() { hidden.removeAll(); persist() }
    func markRead(_ post: Post) {
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].email.isUnread = false }
        if seen.insert(post.id).inserted { persist() }
    }
    func setSenderRule(_ address: String, destination: LocalMailDestination?) {
        guard mode == .sample || accountRules != nil else { return }
        rules.setSender(address, destination: destination)
    }
    func setMessageRule(_ id: String, destination: LocalMailDestination?) {
        guard mode == .sample || accountRules != nil else { return }
        rules.setMessage(id, destination: destination)
    }
}
