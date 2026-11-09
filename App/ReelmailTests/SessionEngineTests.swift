import XCTest
@testable import Reelmail

/// Sprint 7 inbox session engine. All mail here is fictional.
final class SessionEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let kids = [
        KidProfile(id: "k1", name: "Avery", school: "Pine Ridge Middle", teacherNames: ["Ms. Okafor"], activities: ["lacrosse", "band"]),
        KidProfile(id: "k2", name: "Rowan", school: "Maple Elementary", teacherNames: [], activities: ["swim"]),
    ]

    private func msg(_ id: String, from name: String = "Sender", address: String = "news@sender.example",
                     subject: String = "Hello", text: String = "", section: FeedSection = .updates,
                     category: PostCategory = .updates, person: Bool = false, ask: String? = nil,
                     health: Bool = false, firstTime: Bool = false, action: Bool = false, dates: Bool = false,
                     daysAgo: Double = 1) -> SessionMessage {
        SessionMessage(id: id, threadId: "t-" + id, fromName: name, fromAddress: address, subject: subject,
                       date: now.addingTimeInterval(-daysAgo * 86_400), text: text, section: section, category: category,
                       isPerson: person, ask: ask, isHealth: health, isFirstTimeSender: firstTime,
                       asksForAction: action, hasDates: dates)
    }

    private func plan(_ m: [SessionMessage], memory: DrawerMemory = DrawerMemory(),
                      model: [String: DrawerGuess] = [:]) -> SessionPlan {
        SessionPlanner.plan(m, memory: memory, kids: kids, modelGuesses: model)
    }

    private var statement: SessionMessage {
        msg("stmt", from: "Brokerage Co.", address: "donotreply@mail.brokerage.example",
            subject: "Your account eStatement is available", text: "Your eStatement is ready. Log in to view it.")
    }

    // MARK: Drawers

    func testDrawerLabelsAndKidsSubDrawers() {
        XCTAssertEqual(DrawerChoice(.money).labelName, "Lovely/Money")
        XCTAssertEqual(DrawerChoice(.kids, child: "Avery").labelName, "Lovely/Kids/Avery")
        XCTAssertEqual(DrawerChoice(.kids, child: "Avery").title, "Kids · Avery")
        XCTAssertNil(DrawerChoice(.money, child: "Avery").child, "Only Kids has sub-drawers")
        XCTAssertNil(DrawerChoice(.kids, child: "A/B").child, "A slash would make a deeper label")
        XCTAssertNil(DrawerChoice(.kids, child: "  ").child)
    }

    func testMemoryByAddressThenCompanyDomainButNeverSharedDomains() {
        var memory = DrawerMemory()
        memory.remember(DrawerChoice(.money), for: "Alerts@Mail.Brokerage.example")
        XCTAssertEqual(memory.recall("alerts@mail.brokerage.example"), DrawerChoice(.money))
        XCTAssertEqual(memory.recall("docs@statements.brokerage.example"), DrawerChoice(.money), "Same company domain")

        memory.remember(DrawerChoice(.people), for: "friend@gmail.com")
        XCTAssertEqual(memory.recall("friend@gmail.com"), DrawerChoice(.people))
        XCTAssertNil(memory.recall("stranger@gmail.com"), "Public providers are never remembered as a whole")

        memory.remember(DrawerChoice(.kids), for: "noreply@psu1.mg.infinitecampus.org")
        XCTAssertNil(memory.recall("noreply@other.mg.infinitecampus.org"), "Shared sending services are address only")

        memory.forget("alerts@mail.brokerage.example")
        XCTAssertEqual(memory.recall("alerts@mail.brokerage.example"), DrawerChoice(.money), "Domain memory still applies")
    }

    func testMemoryIsSavedPerAccount() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SessionEngineTests"))
        defaults.removePersistentDomain(forName: "SessionEngineTests")
        var memory = DrawerMemory()
        memory.remember(DrawerChoice(.house), for: "billing@power.example")
        memory.save(account: "Owner@Lovely.example", defaults: defaults)
        XCTAssertEqual(DrawerMemory.load(account: "owner@lovely.example", defaults: defaults), memory)
        XCTAssertEqual(DrawerMemory.load(account: "someone@lovely.example", defaults: defaults), DrawerMemory())
    }

    func testRuleGuesses() {
        func guess(_ subject: String, _ text: String = "", address: String = "info@company.example",
                   category: PostCategory = .updates, person: Bool = false) -> DrawerChoice? {
            DrawerGuesser.guess(.init(fromAddress: address, fromName: "X", subject: subject, text: text,
                                      category: category, isPerson: person), kids: kids)?.choice
        }
        XCTAssertEqual(guess("Your account eStatement is available"), DrawerChoice(.money))
        XCTAssertEqual(guess("Your order has shipped", "Tracking number 1Z"), DrawerChoice(.orders))
        XCTAssertEqual(guess("Receipt for your order #4411"), DrawerChoice(.orders), "An order receipt is an order")
        XCTAssertEqual(guess("Your itinerary for March"), DrawerChoice(.travel))
        XCTAssertEqual(guess("Your electric bill is ready"), DrawerChoice(.house))
        XCTAssertEqual(guess("Lacrosse practice moved", "Practice is now Thursday."), DrawerChoice(.kids, child: "Avery"))
        XCTAssertEqual(guess("Weekly update", address: "noreply@psu1.mg.infinitecampus.org"), DrawerChoice(.kids))
        XCTAssertEqual(guess("Lunch Saturday?", person: true), DrawerChoice(.people))
        XCTAssertNil(guess("Something happened", "A note with no clues."))
    }

    func testWholeWordsOnly() {
        XCTAssertFalse(DrawerGuesser.hasAny("a note for every parent", DrawerGuesser.houseWords), "rent inside parent")
        XCTAssertFalse(DrawerGuesser.hasAny("my husband says hi", DrawerGuesser.schoolWords), "band inside husband")
        XCTAssertTrue(DrawerGuesser.hasAny("rent is due friday", DrawerGuesser.houseWords))
        XCTAssertTrue(DrawerGuesser.hasAny("see order #4411", DrawerGuesser.orderWords))
    }

    func testKidMatchNeedsOneKidAndIgnoresShortTerms() {
        XCTAssertEqual(DrawerGuesser.matchKid(haystack: "swim meet saturday", kids: kids)?.name, "Rowan")
        let twins = [KidProfile(id: "a", name: "A", school: "Oak School", teacherNames: [], activities: []),
                     KidProfile(id: "b", name: "B", school: "Oak School", teacherNames: [], activities: [])]
        XCTAssertNil(DrawerGuesser.matchKid(haystack: "oak school picture day", kids: twins), "Two matches: parent drawer")
    }

    // MARK: Grouping and batch rules

    func testRoutineStatementGoesInTheBatchWithItsDrawer() {
        let item = plan([statement]).items[0]
        XCTAssertEqual(item.group, .quick)
        XCTAssertEqual(item.suggestion, .putAway(DrawerChoice(.money)))
        XCTAssertNil(item.heldBecause)
    }

    func testMemoryBeatsRules() {
        var memory = DrawerMemory()
        memory.remember(DrawerChoice(.house), for: statement.fromAddress)
        let item = plan([statement], memory: memory).items[0]
        XCTAssertEqual(item.drawer?.confidence, .remembered)
        XCTAssertEqual(item.suggestion, .putAway(DrawerChoice(.house)))
        XCTAssertTrue(item.drawer?.reason.contains("before") ?? false)
    }

    func testWaitingIsFirstAndAsksForAReply() {
        let p = plan([statement,
                      msg("ask", from: "Coach Reyes", address: "coach@club.example", section: .waiting, person: true,
                          ask: "Can you confirm the roster?", daysAgo: 0.5)])
        XCTAssertEqual(p.items.first?.id, "ask")
        XCTAssertEqual(p.items.first?.suggestion, .reply)
        XCTAssertEqual(p.items.first?.heldBecause, "Asks: Can you confirm the roster?")
    }

    func testNeverInABatch() {
        let held: [SessionMessage] = [
            msg("person", from: "Aunt Jo", address: "jo@gmail.com", subject: "Lake photos", section: .people, person: true),
            msg("note", from: "Me", address: "me@work.example", subject: "Garage code", section: .notes),
            msg("health", subject: "Your appointment", text: "Your statement is ready", health: true),
            msg("pay", subject: "Payment failed", text: "Your statement is ready", action: true),
            msg("new", subject: "Your statement is ready", firstTime: true),
            msg("unsure", subject: "Something happened", text: "No clues here."),
        ]
        let p = plan(held)
        XCTAssertTrue(p.quick.isEmpty)
        XCTAssertEqual(p.oneAtATime.count, held.count)
        XCTAssertTrue(p.oneAtATime.allSatisfy { $0.heldBecause != nil })
        XCTAssertEqual(p.items.first { $0.id == "unsure" }?.heldBecause, "Not sure where this goes")
        XCTAssertEqual(p.items.first { $0.id == "person" }?.suggestion, .decide)
    }

    func testModelGuessAloneIsNotEnoughForABatch() {
        let unsure = msg("unsure", subject: "Something happened", text: "No clues here.")
        let guess = DrawerGuess(choice: DrawerChoice(.reference), confidence: .model, reason: "Apple Intelligence")
        let item = plan([unsure], model: ["unsure": guess]).items[0]
        XCTAssertEqual(item.group, .oneAtATime)
        XCTAssertEqual(item.suggestion, .putAway(DrawerChoice(.reference)), "Suggested, but the owner confirms it alone")
    }

    func testHealthAndActionNeverHideInReading() {
        let p = plan([msg("nl", subject: "This week's reads", section: .reading, category: .newsletter),
                      msg("hl", subject: "Wellness tips", section: .reading, health: true)])
        XCTAssertEqual(p.items.first { $0.id == "nl" }?.group, .reading)
        XCTAssertEqual(p.items.first { $0.id == "nl" }?.suggestion, .archive)
        XCTAssertEqual(p.items.first { $0.id == "hl" }?.group, .oneAtATime)
    }

    func testDatesAreAddedBeforeFiling() {
        let notice = msg("school", address: "noreply@psu1.mg.infinitecampus.org", subject: "Concert moved to Saturday",
                         text: "The band concert is now Saturday at 6:30.", dates: true)
        XCTAssertEqual(plan([notice]).items[0].suggestion, .addDatesThenPutAway(DrawerChoice(.kids, child: "Avery")))
    }

    func testActionDetectionAndAutopay() {
        XCTAssertTrue(SessionMessage.detectsAction(subject: "Please eSign your lease renewal", text: ""))
        XCTAssertTrue(SessionMessage.detectsAction(subject: "Invoice", text: "Please pay by Friday."))
        XCTAssertFalse(SessionMessage.detectsAction(subject: "Your bill", text: "Payment due Nov 12. Autopay is on."))
        XCTAssertFalse(SessionMessage.detectsAction(subject: "Statement ready", text: "Log in to view your statement."))
    }

    // MARK: Order, estimate, pages, progress

    func testOrderInsideGroups() {
        let p = plan([
            msg("q-new", subject: "Your statement is ready", daysAgo: 1),
            msg("q-old", subject: "Your statement is ready", daysAgo: 5),
            msg("person-old", from: "Sam", address: "sam@gmail.com", section: .people, person: true, daysAgo: 9),
            msg("pay", subject: "Payment failed", action: true, daysAgo: 2),
            msg("ask", from: "Lee", address: "lee@gmail.com", section: .waiting, person: true, daysAgo: 1),
            msg("nl", section: .reading, category: .newsletter, daysAgo: 20),
        ])
        XCTAssertEqual(p.items.map(\.id), ["ask", "pay", "person-old", "q-old", "q-new", "nl"])
    }

    func testEstimate() {
        XCTAssertEqual(plan([]).estimatedMinutes, 0)
        XCTAssertEqual(plan([statement]).estimatedMinutes, 1)
        let decisions = (0..<4).map { msg("p\($0)", section: .people, person: true) }
        let quick = (0..<6).map { msg("q\($0)", subject: "Your statement is ready") }
        XCTAssertEqual(plan(decisions + quick).estimatedMinutes, 4, "160 s + 36 s = 196 s")
    }

    func testBatchesArePaged() {
        let quick = (0..<23).map { msg("q\($0)", subject: "Your statement is ready") }
        XCTAssertEqual(SessionPlanner.batches(plan(quick)).map(\.count), [10, 10, 3])
    }

    func testProgress() {
        let p = plan([msg("a", section: .people, person: true, daysAgo: 3),
                      msg("b", section: .people, person: true, daysAgo: 2),
                      statement])
        var progress = SessionProgress(plan: p)
        XCTAssertEqual(progress.next(in: p)?.id, "a")
        progress.markSkipped("a")
        XCTAssertEqual(progress.next(in: p)?.id, "b", "Skipped goes to the end")
        progress.markHandled("b")
        progress.markHandled("stmt")
        XCTAssertEqual(progress.next(in: p)?.id, "a", "Then the skipped item comes back")
        progress.markLeftUnread("a")
        XCTAssertTrue(progress.isDone, "Left unread on purpose counts as dealt with")
        XCTAssertEqual(progress.fraction, 1)
        progress.undo("stmt")
        XCTAssertFalse(progress.isDone)
        XCTAssertEqual(progress.next(in: p)?.id, "stmt")
    }

    // MARK: From the app's model

    func testBuildsFromAPost() {
        let fallback = FallbackSummarizer()
        let me = "owner@lovely.example"
        let robot = Person(id: "r", name: "Brokerage Co.", email: "donotreply@mail.brokerage.example", hue: 0.2)
        let email = Email(id: "m1", threadId: "t1", from: robot, to: [me], subject: "Your account eStatement is available",
                          date: now, body: "Your eStatement is ready. Log in to view it.\n\nOn Mon, someone wrote:\n> please pay now")
        let post = Post(email: email, summary: fallback.summarizeSync(SummaryInput(email: email)))
        let m = SessionMessage(post: post, assessment: TriageAssessment(section: .updates, reason: "Account notice"),
                               isFirstTimeSender: false)
        XCTAssertFalse(m.isPerson, "Automated")
        XCTAssertFalse(m.asksForAction, "Quoted text is not the author's ask")
        XCTAssertEqual(SessionPlanner.plan([m], memory: DrawerMemory(), kids: []).items[0].group, .quick)

        let note = SessionMessage(post: post, assessment: TriageAssessment(section: .notes, reason: "Note to self"),
                                  isFirstTimeSender: false)
        XCTAssertFalse(note.isPerson)
    }
}
