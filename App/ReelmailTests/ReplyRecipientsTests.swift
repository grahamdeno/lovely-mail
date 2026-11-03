import XCTest
@testable import Reelmail

final class ReplyRecipientsTests: XCTestCase {
    private let mine: Set<String> = ["pat@gmail.com", "pat@work.example"]
    private let dana = Person(id: "dana@rink.example", name: "Dana Brooks", email: "dana@rink.example", hue: 0.3)

    private func mail(to: [String], cc: [String] = [], from: Person? = nil) -> Email {
        Email(id: "1", threadId: "t", from: from ?? dana, to: to, cc: cc, subject: "Game Sunday",
              date: Date(timeIntervalSince1970: 2_000_000_000), body: "Ice at nine.")
    }

    func testReplyGoesToTheSenderOnly() {
        let plan = ReplyRecipients.reply(mail(to: ["pat@gmail.com", "sam@club.example"]))
        XCTAssertEqual(plan, ReplyRecipients.Plan(to: ["dana@rink.example"], cc: []))
    }

    func testReplyAllPutsSenderFirstAndRemovesYou() {
        let email = mail(to: ["Pat <pat@gmail.com>", "Sam Lee <sam@club.example>"], cc: ["Lee Ortiz <lee@club.example>", "pat@work.example"])
        let plan = ReplyRecipients.replyAll(email, mine: mine)
        XCTAssertEqual(plan.to, ["dana@rink.example", "sam@club.example"])
        XCTAssertEqual(plan.cc, ["lee@club.example"], "both of your addresses are gone from Cc")
    }

    func testReplyAllRemovesDuplicatesIgnoringCase() {
        let email = mail(to: ["SAM@club.example", "sam@club.example"], cc: ["Sam <sam@club.example>", "DANA@rink.example"])
        let plan = ReplyRecipients.replyAll(email, mine: mine)
        XCTAssertEqual(plan.to, ["dana@rink.example", "SAM@club.example"])
        XCTAssertEqual(plan.cc, [], "anyone already in To is not repeated in Cc")
    }

    func testGmailDotsAndPlusTagsCountAsYou() {
        let email = mail(to: ["p.at+news@gmail.com", "sam@club.example"])
        XCTAssertEqual(ReplyRecipients.replyAll(email, mine: mine).to, ["dana@rink.example", "sam@club.example"])
    }

    func testOfferedOnlyWhenSomeoneElseIsOnTheMail() {
        XCTAssertFalse(ReplyRecipients.offersReplyAll(mail(to: ["pat@gmail.com"]), mine: mine, organization: false), "one to one")
        XCTAssertFalse(ReplyRecipients.offersReplyAll(mail(to: ["pat@gmail.com", "dana@rink.example"]), mine: mine, organization: false), "the sender again is not someone else")
        XCTAssertTrue(ReplyRecipients.offersReplyAll(mail(to: ["pat@gmail.com"], cc: ["sam@club.example"]), mine: mine, organization: false))
        XCTAssertFalse(ReplyRecipients.offersReplyAll(mail(to: ["pat@gmail.com", "sam@club.example"]), mine: mine, organization: true), "never for organization mail")
    }

    func testNameLists() {
        XCTAssertEqual(ReplyRecipients.nameList(["Sam"]), "Sam")
        XCTAssertEqual(ReplyRecipients.nameList(["Sam", "Lee"]), "Sam and Lee")
        XCTAssertEqual(ReplyRecipients.nameList(["Sam", "Lee", "Ann"]), "Sam, Lee and Ann")
        XCTAssertEqual(ReplyRecipients.nameList(["Sam", "Lee", "Ann", "Bo"]), "Sam, Lee and 2 others")
    }

    func testCaptionKeepsGroupIdentity() {
        let group = mail(to: ["pat@gmail.com", "Sam Lee <sam@club.example>", "lee@club.example", "ann@club.example", "bo@club.example"])
        XCTAssertEqual(ReplyRecipients.caption(group, mine: mine), "With Sam, Lee and 2 others")
        XCTAssertNil(ReplyRecipients.caption(mail(to: ["pat@gmail.com"]), mine: mine))
    }

    func testSummaryLine() {
        let email = mail(to: ["pat@gmail.com", "Sam Lee <sam@club.example>"], cc: ["Lee Ortiz <lee@club.example>"])
        XCTAssertEqual(ReplyRecipients.summaryLine(ReplyRecipients.reply(email), email: email), "To Dana")
        XCTAssertEqual(ReplyRecipients.summaryLine(ReplyRecipients.replyAll(email, mine: mine), email: email), "To Dana and Sam \u{00B7} Cc Lee")
    }

    func testComposeLinksCarryCcOnlyWhenPresent() throws {
        let withCc = try XCTUnwrap(GmailCompose.appURL(to: "a@x.example", cc: "b@x.example,c@x.example", subject: "Re: Hi", body: ""))
        XCTAssertTrue(withCc.absoluteString.contains("cc=b@x.example,c@x.example") || withCc.absoluteString.contains("cc=b@x.example%2Cc@x.example"))
        let without = try XCTUnwrap(GmailCompose.appURL(to: "a@x.example", subject: "Re: Hi", body: ""))
        XCTAssertFalse(without.absoluteString.contains("cc="))
        let web = try XCTUnwrap(GmailCompose.webURL(to: "a@x.example", cc: "b@x.example", subject: "Re: Hi", body: ""))
        XCTAssertTrue(web.absoluteString.contains("cc=b@x.example"))
        XCTAssertFalse(try XCTUnwrap(GmailCompose.webURL(to: "a@x.example", subject: "Re: Hi", body: "")).absoluteString.contains("cc="))
    }
}
