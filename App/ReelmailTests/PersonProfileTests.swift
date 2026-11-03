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
        XCTAssertTrue(p.shortVersion.hasPrefix("First Harbor Bank. 1 email since"), p.shortVersion)
        XCTAssertTrue(p.shortVersion.contains("You've never written back."))
        XCTAssertTrue(p.shortVersion.hasSuffix("Nothing needs you."), p.shortVersion)
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
                     post("o2", bank, daysAgo: 4, unread: false), post("old", dana, daysAgo: 30, unread: false),
                     post("oldUnread", bank, daysAgo: 60, unread: true)]
        let d = HomeDigest.make(active: posts, section: { $0.id == "w" ? .waiting : ($0.email.from.id == bank.id ? .updates : .people) },
                                isOrganization: { $0.email.from.id == bank.id }, now: now)
        XCTAssertEqual(d.waiting.map(\.id), ["w"])
        XCTAssertEqual(d.todo.map(\.id), ["oldUnread", "n"], "Unread is the to-do, oldest first, however old")
        XCTAssertEqual(d.people.map(\.id), ["p"])
        XCTAssertEqual(d.organizations.map(\.name), ["First Harbor Bank"])
        XCTAssertEqual(d.organizations.first?.posts.count, 2)
        XCTAssertEqual(d.earlier.map(\.id), ["old"], "Only read mail folds into Earlier")
        XCTAssertEqual(HomeDigest.age(of: now.addingTimeInterval(-21 * 86_400), now: now), "3 weeks")
        XCTAssertEqual(HomeDigest.age(of: now.addingTimeInterval(-3 * 86_400), now: now), "3 days")
        XCTAssertEqual(HomeDigest.organizationName(Person(id: "x", name: "x@getsongbpm.com", email: "sender@getsongbpm.com", hue: 0)), "Getsongbpm")
    }

    func testFirstNameKeepsTitlesAndArticlesWhole() {
        XCTAssertEqual(Person(id: "a", name: "St. Andrews Reserve", email: "a@x.example", hue: 0).firstName, "St. Andrews Reserve")
        XCTAssertEqual(Person(id: "b", name: "Dr. Patel", email: "b@x.example", hue: 0).firstName, "Dr. Patel")
        XCTAssertEqual(Person(id: "c", name: "The Rink", email: "c@x.example", hue: 0).firstName, "The Rink")
        XCTAssertEqual(Person(id: "d", name: "Dana Brooks", email: "d@x.example", hue: 0).firstName, "Dana")
    }

    func testUnreadStateComesFromGmailEachRefresh() {
        func e(_ id: String, unread: Bool) -> Email {
            Email(id: id, threadId: id, from: dana, to: [me.email], subject: "S", date: now, body: "Hi", isUnread: unread)
        }
        let cached = [e("readElsewhere", unread: true), e("stillUnread", unread: true), e("markedUnread", unread: false)]
        let fresh = GmailService.applyUnread(cached, unread: ["stillUnread", "markedUnread"], complete: true)
        XCTAssertEqual(fresh.map(\.isUnread), [false, true, true])
        let partial = GmailService.applyUnread(cached, unread: ["markedUnread"], complete: false)
        XCTAssertEqual(partial.map(\.isUnread), [true, true, true], "An incomplete unread list never marks mail read")
    }

    func testEmailScreenRules() {
        let body = "Please log onto our website (www.livestandrewsreserve.com) and eSign it today. Call 910.313.6100."
        let linked = EmailPresentation.linked(body)
        let links = linked.runs.compactMap(\.link).map(\.absoluteString)
        XCTAssertTrue(links.contains { $0.contains("livestandrewsreserve.com") }, "\(links)")
        XCTAssertTrue(links.contains { $0.hasPrefix("tel:") && $0.contains("9103136100") }, "\(links)")
        XCTAssertEqual(String(linked.characters), body, "Linking never changes the text")

        let solo = Email(id: "a", threadId: "a", from: dana, to: ["Graham <graham.denoyer@gmail.com>"], subject: "S", date: now, body: "Hi")
        XCTAssertFalse(EmailPresentation.showsRecipients(solo, mine: ["grahamdenoyer@gmail.com"]), "Mail only to you needs no To line")
        var group = solo; group.cc = ["team@school.example"]
        XCTAssertTrue(EmailPresentation.showsRecipients(group, mine: ["grahamdenoyer@gmail.com"]), "Group mail keeps its recipients")

        XCTAssertFalse(EmailPresentation.showsSummary(solo))
        XCTAssertEqual(EmailPresentation.dateLine(now.addingTimeInterval(-8 * 86_400), now: now).hasSuffix("8 days ago"), true)
    }
}

