import XCTest
@testable import Reelmail

final class PersonProfileTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let dana = Person(id: "dana@mail.example", name: "Dana Brooks", email: "dana@mail.example", hue: 0.2)
    private let me = Person(id: "pat@lovely.example", name: "Pat Owner", email: "pat@lovely.example", hue: 0.5)

    private func mail(_ id: String, from: Person, thread: String, hoursAgo: Double, body: String, mine: Bool = false) -> Email {
        Email(id: id, threadId: thread, from: from, to: [mine ? dana.email : me.email], subject: "Re: Team photo",
              date: now.addingTimeInterval(-hoursAgo * 3600), body: body, isFromMe: mine)
    }

    func testBluntSummaryCountsReplyTimeAndOpenItems() {
        let theirs = [mail("a", from: dana, thread: "t1", hoursAgo: 100, body: "Photos are up."),
                      mail("b", from: dana, thread: "t2", hoursAgo: 2, body: "Can he make the final?")]
        let mine = [mail("m1", from: me, thread: "t1", hoursAgo: 95, body: "Thanks! I'll send the carpool list tonight.", mine: true)]
        let p = PersonProfile.make(person: dana, theirs: theirs, mine: mine, waitingAsk: ["b": "Can he make the final?"],
                                   isOrganization: false, now: now)
        XCTAssertEqual(p.total, 3)
        XCTAssertEqual(p.fromYou, 1)
        XCTAssertEqual(p.usualReply, 5 * 3600)
        XCTAssertEqual(p.open.first?.text, "Can he make the final?")
        XCTAssertTrue(p.open.first?.theirs ?? false)
        XCTAssertTrue(p.shortVersion.contains("You've traded 3 emails with Dana"), p.shortVersion)
        XCTAssertTrue(p.shortVersion.contains("You usually reply within 5 hr."), p.shortVersion)
        XCTAssertTrue(p.shortVersion.contains("Waiting on you"), p.shortVersion)
        XCTAssertEqual(p.topics, ["Team photo"])
    }

    func testPromiseIsOpenUntilTheyWriteAgain() {
        let mine = [mail("m1", from: me, thread: "t1", hoursAgo: 30, body: "I\u{2019}ll send the form Friday.", mine: true)]
        let open = PersonProfile.make(person: dana, theirs: [], mine: mine, waitingAsk: [:], isOrganization: false, now: now)
        XCTAssertEqual(open.open.map(\.text), ["I\u{2019}ll send the form Friday."])
        XCTAssertTrue(open.shortVersion.contains("You owe them"), open.shortVersion)
        let answered = PersonProfile.make(person: dana, theirs: [mail("x", from: dana, thread: "t1", hoursAgo: 1, body: "Got it")],
                                          mine: mine, waitingAsk: [:], isOrganization: false, now: now)
        XCTAssertTrue(answered.open.isEmpty)
        XCTAssertTrue(answered.shortVersion.hasSuffix("Nothing open."), answered.shortVersion)
    }

    func testOrganizationsAreSaidPlainly() {
        let bank = Person(id: "statements@bank.example", name: "First Harbor Bank", email: "statements@bank.example", hue: 0.1)
        let p = PersonProfile.make(person: bank, theirs: [mail("s", from: bank, thread: "t", hoursAgo: 5, body: "Statement ready")],
                                   mine: [], waitingAsk: [:], isOrganization: true, now: now)
        XCTAssertTrue(p.shortVersion.hasPrefix("An organization, not a person. 1 emails"), p.shortVersion)
        XCTAssertTrue(p.shortVersion.contains("You've never written back."))
    }

    func testHomeDigestFoldsOldMailAndGroupsOrganizations() {
        func post(_ id: String, _ from: Person, daysAgo: Double, unread: Bool) -> Post {
            let e = Email(id: id, threadId: id, from: from, to: [me.email], subject: "S", date: now.addingTimeInterval(-daysAgo * 86_400),
                          body: "Hi", isUnread: unread)
            return Post(email: e, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: e)))
        }
        let bank = Person(id: "statements@bank.example", name: "First Harbor Bank", email: "statements@bank.example", hue: 0.1)
        let posts = [post("w", dana, daysAgo: 1, unread: false), post("n", dana, daysAgo: 1, unread: true),
                     post("p", dana, daysAgo: 2, unread: false), post("o1", bank, daysAgo: 3, unread: false),
                     post("o2", bank, daysAgo: 4, unread: false), post("old", dana, daysAgo: 30, unread: false)]
        let d = HomeDigest.make(active: posts, section: { $0.id == "w" ? .waiting : ($0.email.from.id == bank.id ? .updates : .people) },
                                isOrganization: { $0.email.from.id == bank.id }, now: now)
        XCTAssertEqual(d.waiting.map(\.id), ["w"])
        XCTAssertEqual(d.new.map(\.id), ["n"])
        XCTAssertEqual(d.people.map(\.id), ["p"])
        XCTAssertEqual(d.organizations.map(\.name), ["First Harbor Bank"])
        XCTAssertEqual(d.organizations.first?.posts.count, 2)
        XCTAssertEqual(d.earlier.map(\.id), ["old"])
        XCTAssertEqual(HomeDigest.organizationName(Person(id: "x", name: "x@getsongbpm.com", email: "sender@getsongbpm.com", hue: 0)), "Getsongbpm")
    }
}
