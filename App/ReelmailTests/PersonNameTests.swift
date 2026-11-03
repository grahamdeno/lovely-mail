import XCTest
@testable import Reelmail

/// Names, previews and quote stripping from Sprint 1 (Nov 3, 2026). Fictional addresses only.
final class PersonNameTests: XCTestCase {
    // MARK: Names from the From header

    func testAddressOnlyNamesKeepCaseAndSplitWords() {
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "DFAS-SmartDocs@payroll.example").name, "DFAS SmartDocs")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "pisa.recreation@club.example").name, "Pisa Recreation")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "front_desk@clinic.example").name, "Front Desk")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "<Records-Office@school.example>").name, "Records Office")
    }

    func testAddressStaysLowercaseEvenWhenTheNameKeepsCase() {
        let person = GmailMessageParser.person(fromHeader: "DFAS-SmartDocs@Payroll.example")
        XCTAssertEqual(person.email, "dfas-smartdocs@payroll.example")
    }

    func testGenericLocalPartUsesTheDomainsMainLabel() {
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "noreply@psu650nc.mg.infinitecampus.example").name, "Infinitecampus")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "no-reply@billing.acmepay.example").name, "Acmepay")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "info@mail.riverbank.co.uk").name, "Riverbank")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "Support@orchard.example").name, "Orchard")
    }

    func testLastCommaFirstBecomesFirstLast() {
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "Brooks, Dana <dana@mail.example>").name, "Dana Brooks")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "\"Van Allen, Robin Lee\" <robin@mail.example>").name, "Robin Lee Van Allen")
    }

    func testCommaNamesThatAreNotLastFirstStayAsWritten() {
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "Acme, Inc <hello@acme.example>").name, "Acme, Inc")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "Dana Brooks, Jr. <dana@mail.example>").name, "Dana Brooks, Jr.")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "Nair, Priya, Lee <p@mail.example>").name, "Nair, Priya, Lee")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "Front Desk, Oak Dental Clinic <fd@oak.example>").name, "Front Desk, Oak Dental Clinic")
    }

    func testSingleAndDoubleQuotesAreTrimmed() {
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "'Dana Brooks' <dana@mail.example>").name, "Dana Brooks")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "\"Dana Brooks\" <dana@mail.example>").name, "Dana Brooks")
        XCTAssertEqual(GmailMessageParser.person(fromHeader: "'Brooks, Dana' <dana@mail.example>").name, "Dana Brooks")
    }

    func testInitialsSplitOnSpacesHyphensAndDots() {
        func initials(_ name: String) -> String { Person(id: "x", name: name, email: "x@mail.example", hue: 0).initials }
        XCTAssertEqual(initials("DFAS SmartDocs"), "DS")
        XCTAssertEqual(initials("Dana Brooks"), "DB")
        XCTAssertEqual(initials("Mary-Jane"), "MJ")
        XCTAssertEqual(initials("pisa.recreation"), "PR")
        XCTAssertEqual(initials("Infinitecampus"), "I")
        XCTAssertEqual(initials(""), "?")
    }

    // MARK: Previews

    func testFirstSentenceSkipsAbbreviationsAndInitials() {
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "Ms. Rivera asked about Friday. Please call."), "Ms. Rivera asked about Friday.")
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "Dr. Patel moved the visit to noon. See you then."), "Dr. Patel moved the visit to noon.")
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "J. Smith sent the forms over today. Thanks."), "J. Smith sent the forms over today.")
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "We met at St. Andrews for lunch. It was fun."), "We met at St. Andrews for lunch.")
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "Bring snacks, e.g. fruit or crackers. Thanks."), "Bring snacks, e.g. fruit or crackers.")
    }

    func testFirstSentenceNeedsThreeWords() {
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "Thanks. Can you send the form by Friday?"), "Thanks. Can you send the form by Friday?")
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "Hi all. The game is moved to Saturday. Bring water."), "Hi all. The game is moved to Saturday.")
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "Ms."), "Ms.")
        XCTAssertEqual(FallbackSummarizer.firstSentence(of: "It's been ages!"), "It's been ages!")
        XCTAssertNotEqual(FallbackSummarizer.firstSentence(of: "Ms. Lee is out today. Back Monday."), "Ms.")
    }

    func testAppleIntelligenceBlurbIsUsedAsIs() {
        let blurb = "Ms. Rivera asks you to sign the form. Due Friday."
        let body = String(repeating: "The permission form for the spring trip needs a signature from a parent. ", count: 4)
        let email = Email(id: "a", threadId: "t", from: Person(id: "r@school.example", name: "Ms. Rivera", email: "r@school.example", hue: 0.2),
                          to: ["pat@lovely.example"], subject: "Form", date: Date(), body: body)
        var summary = FallbackSummarizer().summarizeSync(SummaryInput(email: email))
        summary.blurb = blurb
        summary.engine = .appleIntelligence
        XCTAssertEqual(ConversationPresentation.rowText(email, summary: summary), blurb)
        summary.engine = .fallback
        XCTAssertEqual(ConversationPresentation.rowText(email, summary: summary), "Ms. Rivera asks you to sign the form.")
    }

    // MARK: Secrets

    func testTemporaryPasswordAnnouncementIsNotASecret() {
        XCTAssertFalse(FallbackSummarizer.isSensitive("your temporary password will come in a separate email."))
        XCTAssertFalse(FallbackSummarizer.isSensitive("a temporary password will be sent to you separately"))
        XCTAssertTrue(FallbackSummarizer.isSensitive("your temporary password is tulip7"))
        XCTAssertTrue(FallbackSummarizer.isSensitive("your password is tulip7"))
        XCTAssertTrue(FallbackSummarizer.isSensitive("password: tulip7"))
        XCTAssertTrue(FallbackSummarizer.isSensitive("your code is 123456"))
    }

    func testKeyLikeTokensAreSensitive() {
        XCTAssertTrue(FallbackSummarizer.isSensitive("use sk-abcdefghijklmnopqrstuvwx for the demo"))
        XCTAssertTrue(FallbackSummarizer.isSensitive("token a1b2c3d4e5f6a7b8c9d0a1b2c3d4e5f6 expires soon"))
        XCTAssertFalse(FallbackSummarizer.isSensitive("sk-short is not a key"))
        XCTAssertFalse(FallbackSummarizer.isSensitive("the word internationalizationandlocalizationconsiderations is long"))
        XCTAssertFalse(FallbackSummarizer.isSensitive("call 12345678901234567890123456789012 now"))
        XCTAssertFalse(FallbackSummarizer.isSensitive("do not ask-and-receive-more-than-you-need-or-want"))
    }

    // MARK: Quote and forward stripping

    func testOutlookHeaderBlockEndsAuthoredTextEvenForOneLine() {
        let body = "Received, thanks.\nFrom: Pat Owner\nSent: Monday\nTo: Dana\nSubject: Forms\n\nCan you send me the form?"
        XCTAssertEqual(ReplySignals.authoredText(body), "Received, thanks.")
        XCTAssertNil(ReplySignals.askSentence(in: body))
        let dated = "Thanks.\nFrom: Pat Owner\nDate: Monday\nCan you send me the form?"
        XCTAssertEqual(ReplySignals.authoredText(dated), "Thanks.")
    }

    func testFromLineWithoutHeaderBlockIsKept() {
        XCTAssertEqual(ReplySignals.authoredText("Ok.\nFrom: the trail crew we got new signs."), "Ok.\nFrom: the trail crew we got new signs.")
    }

    func testUnderscoreRuleReactionAndWrapStopAuthoredText() {
        XCTAssertEqual(ReplySignals.authoredText("Got it.\n__________\nCan you send it?"), "Got it.")
        XCTAssertEqual(ReplySignals.authoredText("Got it.\nDana reacted to your message:\n\"Can you send it?\""), "Got it.")
        XCTAssertEqual(ReplySignals.authoredText("Got it.\nOn Mon, Nov 2, 2026 at 3:00 PM Dana <d@mail.example> wrote:\n> Can you send it?"), "Got it.")
        XCTAssertEqual(ReplySignals.authoredText("Got it.\nOn Mon, Nov 2, 2026 at 3:00 PM Dana <d@mail.example>\nwrote:\n> Can you send it?"), "Got it.")
        XCTAssertEqual(ReplySignals.authoredText("Got it.\n---------- Forwarded message ---------\nCan you send it?"), "Got it.")
        XCTAssertEqual(ReplySignals.authoredText("Got it.\n_ _ _ short rule stays"), "Got it.\n_ _ _ short rule stays")
    }

    func testCurlyApostrophesMatchCourtesyAndMachineRules() {
        XCTAssertTrue(ReplySignals.isCourtesy("Please don\u{2019}t hesitate to reach out."))
        XCTAssertNil(ReplySignals.askSentence(in: "Thanks. Please don\u{2019}t hesitate to let me know."))
        XCTAssertTrue(ReplySignals.isCourtesy("Please let me know if you have any additional questions."))
        XCTAssertTrue(ReplySignals.isCourtesy("Let me know if there\u{2019}s anything else."))
        XCTAssertTrue(ReplySignals.isCourtesy("Let me know if you need anything."))
        XCTAssertTrue(ReplySignals.isCourtesy("Feel welcome to stop by."))
        XCTAssertFalse(ReplySignals.isCourtesy("Can you send the form by Friday?"))
    }

    func testCalendarResponsesAndGroupNoticesAreMachineMail() {
        for subject in ["Accepted: Sprint review", "Declined: Sprint review", "Tentative: Sprint review",
                        "New time proposed: Sprint review", "Invitation: Sprint review"] {
            XCTAssertTrue(ReplySignals.isMachineText(subject: subject, body: "Can you join?"), subject)
        }
        XCTAssertFalse(ReplySignals.isMachineText(subject: "Sprint review notes", body: "Can you join?"))
        XCTAssertTrue(ReplySignals.isMachineText(subject: "Notice", body: "This is a group email, please reply to sender only."))
    }

    func testSenderLocalPartsThatAreSystems() {
        for local in ["admin", "sender", "assistance", "policy", "claims"] {
            XCTAssertTrue(SenderSignals.looksAutomated(address: local + "@company.example"), local)
        }
        XCTAssertFalse(SenderSignals.looksAutomated(address: "dana@company.example"))
    }

    // MARK: Summarizer input

    func testSummaryInputUsesAuthoredTextUnlessItIsTiny() {
        let from = Person(id: "d@mail.example", name: "Dana", email: "d@mail.example", hue: 0.1)
        func input(_ body: String) -> SummaryInput {
            SummaryInput(email: Email(id: "i", threadId: "t", from: from, to: ["pat@lovely.example"], subject: "Forms",
                                      date: Date(), body: body))
        }
        let long = "The forms are in the blue folder by the front door, and the rest are online."
        XCTAssertEqual(input(long + "\nOn Mon, Nov 2, 2026 at 3:00 PM Pat <p@mail.example> wrote:\n> Where are the forms?").body, long)
        let tiny = "Thanks.\n-----Original Message-----\nWhere are the forms kept at the office?"
        XCTAssertEqual(input(tiny).body, tiny)
    }

    func testSummaryInputKeepsUnsubscribeFooterSoNewslettersStayNewsletters() {
        let from = Person(id: "n@mail.example", name: "Weekly", email: "n@mail.example", hue: 0.1)
        let body = "This week in the garden: the tomatoes are in and the beans are climbing well.\nUnsubscribe at any time."
        let email = Email(id: "n", threadId: "t", from: from, to: ["pat@lovely.example"], subject: "Garden", date: Date(), body: body)
        XCTAssertEqual(FallbackSummarizer().summarizeSync(SummaryInput(email: email)).category, .newsletter)
    }

    func testNamesBuiltFromAnAddressAreNotPeople() {
        XCTAssertFalse(PersonSignals.looksLikePerson(name: "DFAS SmartDocs", email: "dfas-smartdocs@mail.example", youWrote: false))
        XCTAssertFalse(PersonSignals.looksLikePerson(name: "Infinitecampus", email: "noreply@psu.infinitecampus.example", youWrote: false))
        XCTAssertTrue(PersonSignals.looksLikePerson(name: "Dana Brooks", email: "dana.brooks@school.example", youWrote: false))
        XCTAssertTrue(PersonSignals.looksLikePerson(name: "DFAS SmartDocs", email: "dfas-smartdocs@mail.example", youWrote: true), "You wrote to them")
    }

    func testTrackingIdsInLinksAreNotSecrets() {
        XCTAssertFalse(FallbackSummarizer.isSensitive("your order shipped: https://track.shop.example/a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8"))
        XCTAssertTrue(FallbackSummarizer.isSensitive("here is the token a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8 keep it safe"))
    }
}

