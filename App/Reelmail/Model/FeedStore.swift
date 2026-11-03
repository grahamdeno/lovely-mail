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
    /// Set when a Trash request was refused because this sign-in predates the Trash permission.
    private(set) var needsTrashPermission = false
    /// Set when Google's consent left out Gmail access (the Gmail box unticked), so nothing can be read.
    private(set) var needsMailAccess = false
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
    /// Your right/wrong verdicts on sorting, for the demo and for the signed-in account.
    let demoReview: SortingReview
    private(set) var accountReview: SortingReview?
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
        demoReview = SortingReview(accountID: "demo-home-v1", defaults: triageDefaults)
    }

    /// Review verdicts for what is on screen now. Nil in live mode until the account is known.
    var review: SortingReview? { mode == .gmail ? accountReview : demoReview }

    var gmailConfigured: Bool { gmail.config.isConfigured }

    /// Rules that apply to what is on screen now.
    var rules: LocalTriageRules { mode == .gmail ? (accountRules ?? demoRulesPlaceholder) : demoRules }
    /// Until the account is known, live mode has no rules; this empty, unsaved set keeps views simple.
    private let demoRulesPlaceholder = LocalTriageRules(accountID: "unknown-account", defaults: UserDefaults(suiteName: "reelmail.transient") ?? .standard)

    var me: Person {
        if let account {
            // Your display name as it appears on mail you sent, so the avatar shows your initials.
            let name = sentByMe.first(where: { $0.isFromMe && !$0.from.name.isEmpty && !$0.from.name.contains("@") })?.from.name ?? "You"
            return Person(id: account, name: name, email: account, hue: 0.62)
        }
        return SampleData.me
    }

    // MARK: Loading

    /// Loads mail. The work runs in its own task, so leaving the screen or letting go of pull-to-refresh
    /// does not cancel a load that is waiting out Gmail's rate limit (build 1009 showed CancellationError).
    func load() async {
        await Task { await self.performLoad() }.value
    }

    private func performLoad() async {
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
        bump()
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
            // A cancelled load (app closed mid-load) is not an error worth showing; the next open retries.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            if let e = error as? GmailService.GmailError, e.needsReconnect { needsReconnect = true }
            if case GmailService.GmailError.mailAccessNotGranted = error { needsMailAccess = true }
            errorMessage = "Gmail could not refresh. Previously loaded mail, if any, is unchanged. \(error.localizedDescription)"
            return
        }
        guard current == revision else { return }
        needsReconnect = false; needsMailAccess = false
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
        bump()
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
            for pending in pendingOtherAddresses { accountRules?.setOtherAddress(pending, true) }
            pendingOtherAddresses = []
            accountReview = SortingReview(accountID: "gmail-" + MailCache.accountKey(address), defaults: triageDefaults)
        }
    }

    private func persist() {
        bump()
        guard mode == .gmail, let account, let cacheStore else { return }
        let snapshot = MailboxSnapshot(account: account, inbox: posts.map(\.email), sent: sentByMe,
                                       fetchedAt: lastFetched ?? Date(), inboxTruncated: inboxTruncated)
        let cache = MailCache(snapshot: snapshot, summaries: summaries, hidden: hidden, seen: seen)
        do { try cacheStore.save(cache) } catch { errorMessage = "Loaded mail could not be saved on this phone. It will reload next time." }
    }

    func connectGmail() async {
        do { try await gmail.signIn(); needsReconnect = false; needsTrashPermission = false; needsMailAccess = false; await load() }
        catch {
            if case GmailService.GmailError.mailAccessNotGranted = error { needsMailAccess = true; needsReconnect = true }
            errorMessage = error.localizedDescription
        }
    }

    func disconnectGmail() async {
        bump(); revision += 1; gmail.signOut(); cacheStore?.removeAll()
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
                bump()
            }
        }
        if changed { persist() }
    }

    // MARK: Reading the feed

    /// Everything the screens need, worked out once per change instead of once per screen draw.
    /// (Sorting 120 messages with text rules on every draw is what made switching tabs lag.)
    private struct Derived {
        var context: TriageContext
        var assessments: [String: TriageAssessment] = [:]
        var automated: Set<String> = []
        var postsByID: [String: Post] = [:]
        var active: [Post] = []
        var people: [Person] = []
        /// Senders of automated mail: companies, schools' systems, apps.
        var organizations: [Person] = []
        /// Post ids from organizations: automated mail and blind-copy lists.
        var organizationPosts: Set<String> = []
        /// One person with several addresses (same full name): canonical id → every Person it stands for.
        var aliases: [String: [Person]] = [:]
        var waitingPeople: Set<String> = []
        var unreadPeople: Set<String> = []
        var duplicateNames: Set<String> = []
        var theirs: [String: [Email]] = [:]
        var sentTo: [String: [Email]] = [:]
        var lastContact: [String: Date] = [:]
        var noteCount = 0
    }
    @ObservationIgnored private var derivedCache: Derived?
    @ObservationIgnored private var derivedKey = ""
    @ObservationIgnored private var dataVersion = 0
    private func bump() { dataVersion &+= 1 }

    private var derived: Derived {
        // Reading these registers the dependencies, so views refresh when any of them change.
        let rules = self.rules
        let key = "\(dataVersion)|\(ObjectIdentifier(rules).hashValue)|\(rules.revision)|\(posts.count)|\(sentByMe.count)|\(hidden.count)|\(mode.rawValue)|\(account ?? "")|\(lastFetched?.timeIntervalSince1970 ?? 0)"
        if let cache = derivedCache, key == derivedKey { return cache }
        let built = buildDerived(rules: rules)
        derivedCache = built
        derivedKey = key
        return built
    }

    private func buildDerived(rules: LocalTriageRules) -> Derived {
        let context = TriageContext(account: mode == .gmail ? account : SampleData.me.email, sent: sentByMe,
                                    otherAddresses: rules.otherAddresses,
                                    now: mode == .gmail ? (lastFetched ?? Date()) : Date())
        var d = Derived(context: context)
        for post in posts {
            let decision = rules.decision(messageID: post.id, sender: post.email.from.email)
            let a = FeedTriage.assess(post, route: decision.destination, routeReason: decision.reason,
                                      notWaiting: rules.isNotWaiting(messageID: post.id, sender: post.email.from.email),
                                      context: context)
            d.assessments[post.id] = a
            d.postsByID[post.id] = post
            if FeedTriage.automatedReason(post.email) != nil { d.automated.insert(post.id) }
            d.theirs[post.email.from.id, default: []].append(post.email)
            guard !hidden.contains(post.id), decision.destination != .filtered else { continue }
            d.active.append(post)
            if a.section == .notes { d.noteCount += 1 }
            if post.email.isUnread { d.unreadPeople.insert(post.email.from.id) }
            if a.section == .waiting { d.waitingPeople.insert(post.email.from.id) }
        }
        for mail in sentByMe { for address in Set(mail.recipients.map { $0.lowercased() }) { d.sentTo[address, default: []].append(mail) } }

        var seenIDs = Set<String>()
        var waiting: [Person] = []; var rest: [Person] = []
        let wrote = Set(d.sentTo.keys.map(TriageContext.canonical))
        // Organizations: automated mail, lists sent as a blind copy, and senders who don't read as a person
        // (you've never written to them and the name is a company's: "National Life Group", an address alone).
        func isOrganization(_ post: Post) -> Bool {
            if d.automated.contains(post.id) || context.addressing(of: post.email) == .blindCopy { return true }
            let from = post.email.from
            return !PersonSignals.looksLikePerson(name: from.name, email: from.email,
                                                  youWrote: wrote.contains(TriageContext.canonical(from.email)))
        }
        var byName: [String: String] = [:]
        let separate = rules.separatePeople
        for post in d.active where !isOrganization(post) && d.assessments[post.id]?.section != .notes && !context.isMine(post.email) {
            let p = post.email.from
            guard seenIDs.insert(p.id).inserted else { continue }
            // Same full name from another address: the same person (unless you said otherwise).
            if !separate.contains(p.email.lowercased()), let key = PersonSignals.mergeKey(for: p.name) {
                if let canonical = byName[key] { d.aliases[canonical, default: []].append(p); continue }
                byName[key] = p.id
            }
            d.aliases[p.id] = [p]
            if d.waitingPeople.contains(p.id) { waiting.append(p) } else { rest.append(p) }
        }
        // A merged person is waiting or unread when any of their addresses is.
        for (canonical, persons) in d.aliases where persons.count > 1 {
            if persons.contains(where: { d.waitingPeople.contains($0.id) }) { d.waitingPeople.insert(canonical) }
            if persons.contains(where: { d.unreadPeople.contains($0.id) }) { d.unreadPeople.insert(canonical) }
        }
        let waitingIDs = d.waitingPeople
        d.people = (waiting + rest).sorted { waitingIDs.contains($0.id) && !waitingIDs.contains($1.id) }
        for post in d.active where isOrganization(post) { d.organizationPosts.insert(post.id) }
        for post in d.active where isOrganization(post) && d.assessments[post.id]?.section != .notes && !context.isMine(post.email) {
            let p = post.email.from
            guard seenIDs.insert(p.id).inserted else { continue }
            d.organizations.append(p)
        }
        var names: [String: Int] = [:]
        for p in d.people { names[p.name, default: 0] += 1; d.lastContact[p.id] = Self.thread(for: p, in: d).last?.date }
        for p in d.organizations { d.lastContact[p.id] = Self.thread(for: p, in: d).last?.date }
        d.duplicateNames = Set(names.filter { $0.value > 1 }.keys)
        return d
    }

    private static func thread(for person: Person, in d: Derived) -> [Email] {
        let persons = d.aliases[person.id] ?? [person]
        var seen = Set<String>()
        return persons.flatMap { (d.theirs[$0.id] ?? []) + (d.sentTo[$0.email.lowercased()] ?? []) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date < $1.date }
    }

    /// Every address a person writes from, when several were merged by name.
    func addresses(of person: Person) -> [String] { (derived.aliases[person.id] ?? [person]).map(\.email) }

    /// "Not the same person": stop merging this address into someone with the same name.
    func separate(address: String) { rules.setSeparatePerson(address, true); bump() }

    /// Who you are and what you replied to, measured against the last refresh (or now, before one).
    var triageContext: TriageContext { derived.context }

    func assessment(for post: Post) -> TriageAssessment {
        let d = derived
        if let known = d.assessments[post.id] { return known }
        let decision = rules.decision(messageID: post.id, sender: post.email.from.email)
        return FeedTriage.assess(post, route: decision.destination, routeReason: decision.reason,
                                 notWaiting: rules.isNotWaiting(messageID: post.id, sender: post.email.from.email), context: d.context)
    }

    func section(for post: Post) -> FeedSection { assessment(for: post).section }
    /// True when a system, list or notice sent it (not a person).
    func isAutomated(_ post: Post) -> Bool { derived.automated.contains(post.id) }

    /// Everything not hidden and not filtered by a rule.
    var activePosts: [Post] { derived.active }

    /// The feed in priority order: sections top to bottom, newest first within each.
    var sections: [(section: FeedSection, posts: [Post])] {
        let d = derived
        var grouped: [FeedSection: [Post]] = [:]
        for post in d.active {
            let section = d.assessments[post.id]?.section ?? .people
            if filter.includes(section) { grouped[section, default: []].append(post) }
        }
        return FeedSection.allCases.compactMap { s in
            guard let items = grouped[s], !items.isEmpty else { return nil }
            return (s, items.sorted { $0.email.date > $1.email.date })
        }
    }

    /// The Home "All" view.
    var digest: HomeDigest {
        let d = derived
        let overrides = rules.organizationOverrides
        return HomeDigest.make(active: d.active, section: { d.assessments[$0.id]?.section ?? .people },
                               isOrganization: { d.organizationPosts.contains($0.id) },
                               groupKey: { OrganizationKey.key(for: $0.email.from, overrides: overrides) },
                               now: mode == .gmail ? (lastFetched ?? Date()) : Date())
    }

    var waitingCount: Int { derived.active.filter { derived.assessments[$0.id]?.section == .waiting }.count }
    var noteCount: Int { derived.noteCount }
    var topics: [MailTopic] { MailTopic.make(posts: activePosts, sent: sentByMe) }

    /// Messages a saved rule keeps out of the feed, for review and undo.
    var filteredPosts: [Post] {
        posts.filter { rules.decision(messageID: $0.id, sender: $0.email.from.email).destination == .filtered }
    }
    var filteredDemoPosts: [Post] { mode == .sample ? filteredPosts : [] }
    var hiddenPosts: [Post] { posts.filter { hidden.contains($0.id) } }
    var unreadCount: Int { activePosts.filter(\.email.isUnread).count }
    var needsReplyPosts: [Post] { activePosts.filter { derived.assessments[$0.id]?.section == .waiting } }

    var people: [Person] { derived.people }
    /// Senders of automated mail, for the People tab's Organizations view.
    var organizations: [Person] { derived.organizations }

    /// Every organization in loaded mail (not only recent), grouped by company.
    var organizationGroups: [HomeDigest.OrganizationGroup] {
        let d = derived
        let overrides = rules.organizationOverrides
        return HomeDigest.OrganizationGroup.group(d.active.filter { d.organizationPosts.contains($0.id) && d.assessments[$0.id]?.section != .notes },
                                                  key: { OrganizationKey.key(for: $0.email.from, overrides: overrides) })
    }

    func organizationGroup(_ key: String) -> HomeDigest.OrganizationGroup? { organizationGroups.first { $0.id == key } }

    /// "Merge with…": every sender of `group` joins `target`.
    func merge(_ group: HomeDigest.OrganizationGroup, into target: HomeDigest.OrganizationGroup) {
        for sender in group.senders { rules.setOrganization(sender: sender.address, groupKey: target.id) }
        bump()
    }

    /// "Split this sender out" into its own group, or back to automatic grouping with `nil`.
    func splitOut(sender: String, _ split: Bool = true) {
        rules.setOrganization(sender: sender, groupKey: split ? OrganizationKey.splitKey(for: sender) : nil)
        bump()
    }

    /// The summary at the top of an organization's page.
    func profile(for group: HomeDigest.OrganizationGroup) -> PersonProfile {
        let d = derived
        let theirs = group.posts.map(\.email)
        var asks: [String: String] = [:]
        for email in theirs {
            if let a = d.assessments[email.id], a.section == .waiting { asks[email.id] = a.ask ?? FallbackSummarizer.firstSentence(of: email.body) }
        }
        let addresses = Set(group.senders.map(\.address))
        let mine = sentByMe.filter { mail in mail.recipients.contains { addresses.contains($0.lowercased()) } }
        let lead = Person(id: group.id, name: group.name, email: group.senders.first?.address ?? "", hue: 0.5)
        return PersonProfile.make(person: lead, theirs: theirs, mine: mine, waitingAsk: asks, isOrganization: true,
                                  now: mode == .gmail ? (lastFetched ?? Date()) : Date())
    }

    enum ContactKind: String, CaseIterable, Identifiable {
        case people = "People", organizations = "Organizations", all = "All"
        var id: String { rawValue }
    }

    func contacts(_ kind: ContactKind) -> [Person] {
        switch kind {
        case .people: return derived.people
        case .organizations: return derived.organizations
        case .all: return derived.people + derived.organizations
        }
    }
    func needsReply(_ person: Person) -> Bool { derived.waitingPeople.contains(person.id) }
    func hasUnread(_ person: Person) -> Bool { derived.unreadPeople.contains(person.id) }
    func sharesName(_ person: Person) -> Bool { derived.duplicateNames.contains(person.name) }
    func lastContact(_ person: Person) -> Date { derived.lastContact[person.id] ?? .distantPast }
    func posts(from person: Person) -> [Post] { posts.filter { $0.email.from.id == person.id } }
    func conversation(with person: Person) -> [Email] { Self.thread(for: person, in: derived) }

    /// The summary at the top of a person's page.
    func profile(for person: Person) -> PersonProfile {
        let d = derived
        let persons = d.aliases[person.id] ?? [person]
        let theirs = persons.flatMap { d.theirs[$0.id] ?? [] }
        var asks: [String: String] = [:]
        for email in theirs {
            if let a = d.assessments[email.id], a.section == .waiting { asks[email.id] = a.ask ?? FallbackSummarizer.firstSentence(of: email.body) }
        }
        var seenMine = Set<String>()
        let mine = persons.flatMap { d.sentTo[$0.email.lowercased()] ?? [] }.filter { seenMine.insert($0.id).inserted }
        return PersonProfile.make(person: person, theirs: theirs, mine: mine, waitingAsk: asks,
                                  isOrganization: d.organizations.contains(where: { $0.id == person.id }),
                                  now: mode == .gmail ? (lastFetched ?? Date()) : Date())
    }
    func post(for email: Email) -> Post? { derived.postsByID[email.id] }
    func search(_ query: String) -> [Post] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return activePosts.filter {
            $0.email.from.name.lowercased().contains(q) || $0.email.subject.lowercased().contains(q)
                || $0.summary.headline.lowercased().contains(q) || $0.email.body.lowercased().contains(q)
        }.sorted { $0.email.date > $1.email.date }
    }

    // MARK: Trash (the only change Lovely makes to Gmail, and only when you ask)

    /// Moves a message to Gmail's Trash (recoverable for 30 days). It leaves Lovely at once; if Gmail refuses,
    /// it comes back and the reason is shown. In demo mode this only hides the fictional message.
    func moveToTrash(_ post: Post) async {
        hidden.insert(post.id); persist()
        guard mode == .gmail else { return }
        do { try await gmail.trash(messageID: post.id) }
        catch { trashFailed(post, error) }
    }

    /// Undo for `moveToTrash`.
    func restoreFromTrash(_ post: Post) async {
        if mode == .gmail {
            do { try await gmail.untrash(messageID: post.id) }
            catch { errorMessage = "Gmail could not take that message out of Trash. Open Trash in Gmail to restore it. \(error.localizedDescription)"; return }
        }
        hidden.remove(post.id); persist()
    }

    private func trashFailed(_ post: Post, _ error: Error) {
        hidden.remove(post.id); persist()
        if let e = error as? GmailService.GmailError {
            switch e {
            case .needsTrashPermission: needsTrashPermission = true
            case .sessionExpired, .notSignedIn: needsReconnect = true
            default: break
            }
        }
        errorMessage = "That message was not moved to Trash. \(error.localizedDescription)"
    }

    // MARK: Your other addresses

    /// Addresses you said are yours. Mail from them is "Notes to self". Saved on this phone, per account.
    var otherAddresses: [String] { rules.otherAddresses }
    enum AddAddressResult: Equatable { case added, pending, invalid, notSaved(String) }

    /// Adds another address of yours. Before the Gmail account is known (first load still running or failed),
    /// the address waits and is saved to that account's rules as soon as the account is known.
    @discardableResult
    func addOtherAddress(_ address: String) -> AddAddressResult {
        let key = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard LocalTriageRules.looksLikeAddress(key) else { return .invalid }
        guard mode == .sample || accountRules != nil else {
            pendingOtherAddresses.insert(key)
            return .pending
        }
        if let error = rules.persistenceError { return .notSaved(error) }
        return rules.setOtherAddress(key, true) ? .added : .notSaved("Lovely could not save that address on this phone.")
    }
    /// Addresses added before the account was known.
    private(set) var pendingOtherAddresses: Set<String> = []
    func removeOtherAddress(_ address: String) {
        guard mode == .sample || accountRules != nil else { return }
        rules.setOtherAddress(address, false)
    }

    // MARK: Local actions

    func hide(_ post: Post) { hidden.insert(post.id); persist() }
    func unhide(_ post: Post) { hidden.remove(post.id); persist() }
    func restoreAll() { hidden.removeAll(); persist() }
    func markRead(_ post: Post) {
        bump()
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].email.isUnread = false }
        if seen.insert(post.id).inserted { persist() }
    }
    /// Your correction: this message (or everything from this sender) is not waiting on you. Local only.
    func markNotWaiting(_ post: Post, wholeSender: Bool) {
        guard mode == .sample || accountRules != nil else { return }
        if wholeSender { rules.setNotWaiting(sender: post.email.from.email, true) }
        else { rules.setNotWaiting(messageID: post.id, true) }
    }
    func undoNotWaiting(_ post: Post) {
        guard mode == .sample || accountRules != nil else { return }
        rules.setNotWaiting(messageID: post.id, false)
        rules.setNotWaiting(sender: post.email.from.email, false)
    }
    func isMarkedNotWaiting(_ post: Post) -> Bool { rules.isNotWaiting(messageID: post.id, sender: post.email.from.email) }

    func setSenderRule(_ address: String, destination: LocalMailDestination?) {
        guard mode == .sample || accountRules != nil else { return }
        rules.setSender(address, destination: destination)
    }
    func setMessageRule(_ id: String, destination: LocalMailDestination?) {
        guard mode == .sample || accountRules != nil else { return }
        rules.setMessage(id, destination: destination)
    }
}
