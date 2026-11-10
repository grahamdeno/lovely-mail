#if DEBUG
import Foundation
import SwiftUI

// UI audit fixtures. This whole file is compiled only into Debug builds (the unit tests and the UI audit).
// Release and TestFlight builds do not contain it; scripts/privacy_guard.py and the TestFlight workflow both check that.
// Everything here is fictional: .example addresses, invented names, no network.

/// Which launch arguments switch the app into fixture mode, and which condition to simulate.
enum FixtureMode {
    static let flag = "-uiTestFixtures"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    enum Condition: String {
        case normal
        /// Gmail refuses the saved sign-in (it expires every 7 days in Testing mode).
        case expired = "-uiTestExpired"
        /// Google did not grant mail access at sign-in.
        case missingPermission = "-uiTestNoPermission"
        case offline = "-uiTestOffline"
        case empty = "-uiTestEmpty"
        /// Not connected: the first launch, which shows sample mail and the Connect screen.
        case signedOut = "-uiTestSignedOut"
    }

    static var condition: Condition {
        let args = ProcessInfo.processInfo.arguments
        return [Condition.expired, .missingPermission, .offline, .empty, .signedOut].first { args.contains($0.rawValue) } ?? .normal
    }

    /// `-uiTestAppearance light|dark|neon` picks the app's own appearance setting. Without it the system setting applies.
    static var appearance: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestAppearance"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// Builds the store for a fixture launch, or nil for a normal launch.
    @MainActor
    static func makeStoreIfRequested() -> FeedStore? {
        guard isRequested else { return nil }
        resetPhoneState()
        let client = FixtureGmailClient(condition: condition)
        let triage = UserDefaults(suiteName: "reelmail.uitest.triage") ?? .standard
        triage.removePersistentDomain(forName: "reelmail.uitest.triage")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("reelmail-uitest-\(UUID().uuidString)", isDirectory: true)
        let engine = InsightEngine(storage: InsightStorage(directory: scratch))
        let store = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: triage, cacheStore: nil, veto: nil, insights: engine)
        store.httpTransport = client.unsubscribeTransport
        return store
    }

    /// A fixture launch always starts from the same typed settings: a household, two children, a Shoebox address and its allowlist.
    private static func resetPhoneState() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("lovely.") { defaults.removeObject(forKey: key) }
        // The UI audit's jobs tap the tab bar; the split pill (Nov 9) is tested by its own job later.
        defaults.set(false, forKey: "lovely.nav.splitPill")
        if let appearance { defaults.set(appearance, forKey: Appearance.storageKey) }
        InsightSettings().save(InsightSettingsData(
            households: [Household(id: "fx-home", name: "Maple Street house")],
            kids: [
                KidProfile(id: "fx-ava", name: "Ava", school: "Oakridge Elementary", teacherNames: ["Ms. Rivera"], activities: ["Soccer"]),
                KidProfile(id: "fx-noah", name: "Noah", school: "Hillview Middle School", teacherNames: [], activities: ["Robotics"])
            ]))
        ForwardAllowlist().add(FixtureData.shoebox)
        ShoeboxRule.setAddress(FixtureData.shoebox)
    }
}

/// Everything the fake Gmail and the fake transport were asked to do, in order. The audit tests read it through an invisible
/// accessibility element, so every Send, Trash, Undo, filter and forward is checked against what would have gone to Gmail.
@MainActor
@Observable
final class FixtureLog {
    static let shared = FixtureLog()
    private(set) var lines: [String] = []
    private var counter = 0

    func add(_ line: String) { lines.append("\(lines.count + 1). \(line)") }
    func nextID() -> Int { counter += 1; return counter }
}

struct FixtureRequestsOverlay: View {
    var body: some View {
        Color.clear
            .frame(width: 2, height: 2)
            .accessibilityElement()
            .accessibilityLabel("Fixture requests")
            .accessibilityValue(FixtureLog.shared.lines.joined(separator: "\n"))
            .accessibilityIdentifier("fixture.requests")
            .allowsHitTesting(false)
    }
}

/// A Gmail that lives in memory. It never touches the network and never needs a Google account.
@MainActor
final class FixtureGmailClient: GmailInboxClient {
    let config = GmailConfig(clientID: "100000000000-uitestfixture.apps.googleusercontent.com")
    private(set) var signedIn: Bool
    var isSignedIn: Bool { signedIn }
    private let condition: FixtureMode.Condition
    private var inbox: [Email]
    private let sent: [Email]
    private var trashed: Set<String> = []

    init(condition: FixtureMode.Condition) {
        self.condition = condition
        signedIn = condition != .signedOut
        inbox = condition == .empty ? [] : FixtureData.inbox()
        sent = condition == .empty ? [] : FixtureData.sent()
    }

    private var visible: [Email] { inbox.filter { !trashed.contains($0.id) }.sorted { $0.date > $1.date } }

    func fetchMailbox(known: MailboxSnapshot?, limits: ImportLimits) async throws -> MailboxSnapshot {
        FixtureLog.shared.add("CLIENT fetchMailbox")
        switch condition {
        case .expired: throw GmailService.GmailError.sessionExpired
        case .missingPermission: throw GmailService.GmailError.mailAccessNotGranted
        case .offline: throw URLError(.notConnectedToInternet)
        default: break
        }
        return MailboxSnapshot(account: FixtureData.account, inbox: visible, sent: sent.sorted { $0.date > $1.date }, fetchedAt: Date())
    }

    func trash(messageID: String) async throws { FixtureLog.shared.add("CLIENT trash \(messageID)"); trashed.insert(messageID) }
    func untrash(messageID: String) async throws { FixtureLog.shared.add("CLIENT untrash \(messageID)"); trashed.remove(messageID) }
    func markRead(messageID: String) async throws { FixtureLog.shared.add("CLIENT markRead \(messageID)"); setUnread(messageID, false) }
    func markUnread(messageID: String) async throws { FixtureLog.shared.add("CLIENT markUnread \(messageID)"); setUnread(messageID, true) }

    private func setUnread(_ id: String, _ value: Bool) {
        guard let i = inbox.firstIndex(where: { $0.id == id }) else { return }
        inbox[i].isUnread = value
    }

    func threadSenders(threadID: String) async throws -> [ThreadSender] { [] }

    func listMessageIDs(query: String, limit: Int) async throws -> (ids: [String], truncated: Bool, query: String) {
        if query.hasPrefix("newer_than") { return (visible.map(\.id), false, query) }
        if query.hasPrefix("from:") {
            // The Shoebox backfill: the last days of one sender's mail.
            let ids = visible.filter { query.contains($0.from.email) }.map(\.id)
            return (Array(ids.prefix(limit)), false, query)
        }
        if query.contains("older_than"), query.contains("to:") {
            // "Have I ever seen this sender?" Everyone but the first-time sender has history.
            return (query.contains(FixtureData.firstTimeSender.email) ? [] : ["fx-history"], false, query)
        }
        return ([], false, query)
    }

    func getMetadata(id: String) async throws -> MessageStub {
        guard let e = inbox.first(where: { $0.id == id }) else { throw GmailService.GmailError.http(404) }
        let unsub = FixtureData.unsubscribeLink(for: e)
        return MessageStub(id: e.id, fromName: e.from.name, fromAddress: e.from.email, subject: e.subject, date: e.date,
                           listUnsubscribe: unsub, listUnsubscribePost: unsub == nil ? nil : "List-Unsubscribe=One-Click")
    }

    func getMessage(id: String, account: String?) async throws -> Email {
        guard let e = inbox.first(where: { $0.id == id }) else { throw GmailService.GmailError.http(404) }
        return e
    }

    func signIn() async throws {
        FixtureLog.shared.add("CLIENT signIn")
        // The audit stops before Google's own sign-in page.
        throw GmailService.GmailError.cancelled
    }

    func signOut() { FixtureLog.shared.add("CLIENT signOut"); signedIn = false }

    // MARK: Fake transport

    /// One JSON answer that every write the app makes can decode: an id, an empty label list and the verified Shoebox address.
    nonisolated private static func answer(for request: URLRequest, id: Int) -> (Data, URLResponse) {
        var forwarding: [[String: String]] = []
        for address in ForwardAllowlist().addresses { forwarding.append(["forwardingEmail": address, "verificationStatus": "accepted"]) }
        let json: [String: Any] = ["id": "fx-\(id)", "labels": [Any](), "forwardingAddresses": forwarding]
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    /// Records the request and answers success. Nothing is sent anywhere.
    func makeActions() -> GmailActions {
        GmailActions(token: { "fixture-token" }, transport: { request in
            let line = await FixtureRecorder.describe(request)
            let id = await MainActor.run { () -> Int in FixtureLog.shared.add(line); return FixtureLog.shared.nextID() }
            return Self.answer(for: request, id: id)
        }, allowlist: ForwardAllowlist(), filters: FilterRegistry(), labels: LovelyLabels(), activity: ActivityLog())
    }

    /// One-click unsubscribe requests are recorded and answered with success.
    var unsubscribeTransport: (URLRequest) async throws -> (Data, URLResponse) {
        { request in
            let line = "UNSUBSCRIBE \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")"
            await MainActor.run { FixtureLog.shared.add(line) }
            return (Data(), HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
}

enum FixtureRecorder {
    /// "POST /path to=a@b.example subject=..." The recipient and subject come from the message being sent, when there is one.
    static func describe(_ request: URLRequest) async -> String {
        let method = request.httpMethod ?? "GET"
        let path = (request.url?.path ?? "").replacingOccurrences(of: "/gmail/v1/users/me", with: "")
        var line = "\(method) \(path)"
        guard let body = request.httpBody, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return line }
        if let raw = json["raw"] as? String, let text = decodeBase64URL(raw) {
            for header in ["To", "Subject"] {
                if let value = text.components(separatedBy: "\r\n").first(where: { $0.hasPrefix(header + ": ") }) {
                    line += " \(header.lowercased())=" + String(value.dropFirst(header.count + 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        if let criteria = json["criteria"] as? [String: Any], let from = criteria["from"] as? String { line += " from=\(from)" }
        if let action = json["action"] as? [String: Any], let forward = action["forward"] as? String { line += " forward=\(forward)" }
        if let name = json["name"] as? String { line += " name=\(name)" }
        return line
    }

    private static func decodeBase64URL(_ s: String) -> String? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// The fictional inbox. Dates are relative to the launch, so "today" always looks like today.
enum FixtureData {
    static let account = "owner@lovelytest.example"
    static let shoebox = "household-demo@inmyshoebox.com"
    static let me = Person(id: "fx-me", name: "Graham D", email: account, hue: 0.62)

    static let brightwater = Person(id: "fx-brightwater", name: "Brightwater Utilities", email: "billing@brightwater.example", hue: 0.60)
    static let cedar = Person(id: "fx-cedar", name: "Cedar Gas Co.", email: "billing@cedargas.example", hue: 0.05)
    static let sense = Person(id: "fx-sense", name: "Sense Energy", email: "reports@sense-energy.example", hue: 0.40)
    static let oakridge = Person(id: "fx-oakridge", name: "Oakridge Elementary", email: "office@oakridge-elem.example", hue: 0.30)
    static let rivera = Person(id: "fx-rivera", name: "Ms. Rivera", email: "rivera@oakridge-elem.example", hue: 0.33)
    static let hillview = Person(id: "fx-hillview", name: "Hillview Middle School", email: "office@hillview-ms.example", hue: 0.58)
    static let streamly = Person(id: "fx-streamly", name: "Streamly Plus", email: "billing@streamly.example", hue: 0.80)
    static let weekendRead = Person(id: "fx-weekend", name: "The Weekend Read", email: "hello@weekendread.example", hue: 0.08)
    static let trailNotes = Person(id: "fx-trail", name: "Trail Notes", email: "hello@trailnotes.example", hue: 0.25)
    static let firstTimeSender = Person(id: "fx-jordan", name: "Jordan Pike", email: "jordan@pikeandco.example", hue: 0.15)
    static let juniper = Person(id: "fx-juniper", name: "Juniper Dental", email: "care@juniperdental.example", hue: 0.45)
    static let maya = Person(id: "fx-maya", name: "Maya Chen", email: "maya@chen-family.example", hue: 0.02)
    static let dana = Person(id: "fx-dana", name: "Dana Brooks", email: "dana@riversidefc.example", hue: 0.33)
    static let leo = Person(id: "fx-leo", name: "Leo Park", email: "leo.park@mailbox.example", hue: 0.47)
    static let rosa = Person(id: "fx-rosa", name: "Rosa Marin", email: "rosa.m@familymail.example", hue: 0.95)
    static let ben = Person(id: "fx-ben", name: "Ben Adeyemi", email: "ben@adeyemi-co.example", hue: 0.52)

    private static func ago(_ hours: Double) -> Date { Date().addingTimeInterval(-hours * 3600) }

    private static func day(_ offset: Int, _ format: String = "MMMM d, yyyy") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format
        return f.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date())
    }

    private static func lastMonth() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMMM yyyy"
        return f.string(from: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
    }

    /// Only the newsletters offer one-click unsubscribe.
    static func unsubscribeLink(for email: Email) -> String? {
        guard [weekendRead.email, trailNotes.email].contains(email.from.email) else { return nil }
        return "<https://unsubscribe.\(email.from.email.split(separator: "@").last ?? "news.example")/u/\(email.id)>"
    }

    static func inbox() -> [Email] {
        [
            Email(id: "fx-new", threadId: "thr-new", from: firstTimeSender, to: [account], subject: "Quick question about Saturday", date: ago(1),
                  body: "Hi Graham, we haven't met. I run the neighborhood clean-up and wondered if you could lend a truck on Saturday morning. Could you let me know?"),
            Email(id: "fx-bill", threadId: "thr-bill", from: brightwater, to: [account], subject: "Your Brightwater Utilities bill is ready", date: ago(2),
                  body: "Statement for last month.\nAmount Due: $142.18\nDue Date: \(day(11))\nWater $48.10\nSewer $31.02\nTrash $18.00\nPay online or set up autopay.", bulk: true),
            Email(id: "fx-fail", threadId: "thr-fail", from: cedar, to: [account], subject: "Autopay failed: your gas payment was declined", date: ago(3),
                  body: "Your automatic payment failed. We couldn't process your payment of $64.20.\nAmount Due: $64.20\nDue Date: \(day(3))\nPlease update your payment method.", bulk: true),
            Email(id: "fx-group", threadId: "thr-potluck", from: maya, to: [account, dana.email, leo.email], cc: [rosa.email],
                  subject: "Potluck Saturday: who brings what?", date: ago(4),
                  body: "Hi all, the potluck is at our place at 5. Graham, can you bring the salad? Dana has drinks and Leo has the rolls. Rosa, please bring dessert."),
            Email(id: "fx-sense", threadId: "thr-sense", from: sense, to: [account], subject: "Your \(lastMonth()) Sense energy report", date: ago(5),
                  body: "Your home energy summary.\n612 kWh used. 301 kWh produced.\nYou spent $3.84/day, up $0.40 per day.\nAlways On $41 this month", bulk: true),
            Email(id: "fx-dana", threadId: "thr-dana", from: dana, to: [account], subject: "Carpool Thursday?", date: ago(6),
                  body: "Can you drive on Thursday? I can take Saturday. Let me know which works."),
            Email(id: "fx-kid1", threadId: "thr-kid1", from: oakridge, to: [account], subject: "Ava's field trip permission slip due Friday", date: ago(7),
                  body: "Hello families, Ms. Rivera's class visits the science museum next week. Please return the signed slip by Friday so Ava can come along.", bulk: true),
            Email(id: "fx-ben", threadId: "thr-ben", from: ben, to: [account], subject: "Contract draft for review", date: ago(8),
                  body: "Graham, the draft is attached in the shared folder. Could you review section 3 by Wednesday?"),
            Email(id: "fx-news1", threadId: "thr-news1", from: weekendRead, to: [account], subject: "Ten books worth your weekend", date: ago(9),
                  body: "This week: ten books, two essays and a recipe. Unsubscribe any time.", bulk: true, promotional: true),
            Email(id: "fx-news2", threadId: "thr-news2", from: trailNotes, to: [account], subject: "Trail Notes: autumn routes", date: ago(12),
                  body: "Five loop hikes under six miles, with parking notes.", bulk: true, promotional: true),
            Email(id: "fx-self", threadId: "thr-self", from: me, to: [account], subject: "Reminder: passport photos", date: ago(18),
                  body: "Get passport photos taken before the renewal appointment.", isUnread: false, isFromMe: true),
            Email(id: "fx-rivera", threadId: "thr-rivera", from: rivera, to: [account], subject: "Ava did great on the reading check", date: ago(26),
                  body: "Just a note that Ava did wonderfully on her reading check this week."),
            Email(id: "fx-renew", threadId: "thr-renew", from: streamly, to: [account], subject: "You'll be charged for your Streamly Plus annual plan in 14 days", date: ago(28),
                  body: "Your Streamly Plus annual plan renews soon. You will be charged for your Streamly Plus annual plan in 14 days. Manage your plan any time.", bulk: true),
            Email(id: "fx-noah", threadId: "thr-noah", from: hillview, to: [account], subject: "Noah: Robotics club moves to Thursday", date: ago(30),
                  body: "Robotics club meets Thursday at 3:30 this week. Noah's team should bring their kits.", bulk: true),
            Email(id: "fx-health", threadId: "thr-health", from: juniper, to: [account], subject: "Appointment reminder: scheduled for \(day(6)) at 2:30 PM", date: ago(40),
                  body: "This is a reminder of your upcoming visit.", bulk: true),
            Email(id: "fx-leo", threadId: "thr-leo", from: leo, to: [account], subject: "Re: lawnmower", date: ago(50),
                  body: "You can keep it through the weekend, no rush.", isUnread: false)
        ]
    }

    static func sent() -> [Email] {
        [
            Email(id: "fx-sent1", threadId: "thr-sent1", from: me, to: [maya.email], subject: "Re: weekend plans", date: ago(60),
                  body: "Sounds good, see you then.", isUnread: false, isFromMe: true),
            Email(id: "fx-sent2", threadId: "thr-sent2", from: me, to: [dana.email], subject: "Practice schedule", date: ago(72),
                  body: "Thanks for sending the schedule.", isUnread: false, isFromMe: true)
        ]
    }
}
#endif
