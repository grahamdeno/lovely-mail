import XCTest
@testable import Reelmail

/// Sprint 8 card moves: thresholds, the page's big fact, what a pull does, the likely drawers. All mail is fictional.
final class SessionCardTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // Tuesday, Nov 10, 2026, 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_312_000)

    private func msg(from name: String = "Cape Fear Power", subject: String = "Hello", text: String = "",
                     section: FeedSection = .updates, person: Bool = false, ask: String? = nil,
                     health: Bool = false, firstTime: Bool = false) -> SessionMessage {
        SessionMessage(id: "m", threadId: "t", fromName: name, fromAddress: "x@sender.example", subject: subject,
                       date: now, text: text, section: section, category: .updates, isPerson: person, ask: ask,
                       isHealth: health, isFirstTimeSender: firstTime, asksForAction: false, hasDates: false)
    }

    private func day(_ offset: Int, hour: Int? = nil) -> MailDate {
        let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        let at = hour.map { calendar.date(byAdding: .hour, value: $0, to: start)! } ?? start
        return MailDate(start: at, hasTime: hour != nil, phrase: "", sentence: "")
    }

    // MARK: Motion

    func testResistanceFollowsThenHalves() {
        XCTAssertEqual(SessionCardMotion.resisted(30), 30)
        XCTAssertEqual(SessionCardMotion.resisted(140), 90)
        XCTAssertEqual(SessionCardMotion.resisted(-140), -90)
    }

    func testDirectionNeedsClearlySideways() {
        XCTAssertEqual(SessionCardMotion.direction(dx: -40, dy: 10, slideStart: 0), .sideways)
        XCTAssertEqual(SessionCardMotion.direction(dx: -30, dy: 25, slideStart: 0), .vertical)
        // Rightward only moves an open Trash.
        XCTAssertEqual(SessionCardMotion.direction(dx: 40, dy: 5, slideStart: 0), .vertical)
        XCTAssertEqual(SessionCardMotion.direction(dx: 40, dy: 5, slideStart: -112), .sideways)
    }

    func testSlideStopsSoftlyPastTheWord() {
        XCTAssertEqual(SessionCardMotion.slide(start: 0, dx: -50), -50)
        XCTAssertEqual(SessionCardMotion.slide(start: 0, dx: 30), 0)
        XCTAssertEqual(SessionCardMotion.slide(start: 0, dx: -212), -147, accuracy: 0.01)
    }

    func testReleaseLines() {
        XCTAssertEqual(SessionCardMotion.release(dy: -120, predictedDy: -120), .skip)
        XCTAssertEqual(SessionCardMotion.release(dy: -40, predictedDy: -160), .skip, "a quick flick up counts")
        XCTAssertEqual(SessionCardMotion.release(dy: -20, predictedDy: -160), .springBack, "a twitch does not")
        XCTAssertEqual(SessionCardMotion.release(dy: 170, predictedDy: 170), .putAway)
        XCTAssertEqual(SessionCardMotion.release(dy: 120, predictedDy: 400), .springBack, "putting away needs the full pull")
    }

    // MARK: The big fact

    func testBillShowsAmountAndDueDay() {
        let m = msg(subject: "Your November bill is ready", text: "Amount due: $142.18. Please pay by Friday.")
        let hero = SessionHero.make(m, dates: [day(3)], now: now, calendar: calendar)
        XCTAssertEqual(hero, SessionHero(label: "Due Friday", value: "$142.18"))
    }

    func testAdPricesAreNotAmounts() {
        XCTAssertNil(SessionHero.amount(in: "Shop now: 50% off jackets from $19.99"))
        XCTAssertNil(SessionHero.amount(in: "Coffee was great, see you soon"))
        XCTAssertEqual(SessionHero.amount(in: "Your balance is $1,420.50"), "$1,420.50")
        XCTAssertEqual(SessionHero.amount(in: "Total due $1420.50 today"), "$1420.50")
    }

    func testHealthMailNeverShowsAmounts() {
        let m = msg(from: "Clinic Portal", subject: "Your balance", text: "Amount due: $80.00", health: true)
        let hero = SessionHero.make(m, dates: [], now: now, calendar: calendar)
        XCTAssertFalse(hero.value.contains("$"))
    }

    func testDateWithTime() {
        let m = msg(from: "Sarah Mills", subject: "Dinner Saturday?", section: .waiting, person: true, ask: "Are you free Saturday at 7?")
        let hero = SessionHero.make(m, dates: [day(4, hour: 19)], now: now, calendar: calendar)
        XCTAssertEqual(hero, SessionHero(label: "Waiting on you", value: "Saturday 7 PM"))
    }

    func testTodayTomorrowAndLater() {
        XCTAssertEqual(SessionHero.dayLabel(day(0), now: now, calendar: calendar, withTime: true), "Today")
        XCTAssertEqual(SessionHero.dayLabel(day(1, hour: 9), now: now, calendar: calendar, withTime: true), "Tomorrow 9 AM")
        XCTAssertEqual(SessionHero.dayLabel(day(10), now: now, calendar: calendar, withTime: true), "Nov 20")
    }

    func testWaitingWithoutDateShowsFirstName() {
        let m = msg(from: "Sarah Mills", section: .waiting, person: true, ask: "Can you call me?")
        XCTAssertEqual(SessionHero.make(m, dates: [], now: now, calendar: calendar), SessionHero(label: "Waiting on you", value: "Sarah"))
    }

    func testNewSenderAndPlainSender() {
        XCTAssertEqual(SessionHero.make(msg(from: "Hearth & Co, LLC", firstTime: true), dates: [], now: now, calendar: calendar),
                       SessionHero(label: "New sender", value: "Hearth & Co"))
        XCTAssertEqual(SessionHero.make(msg(from: "Parcel Post"), dates: [], now: now, calendar: calendar).value, "Parcel Post")
    }

    // MARK: What a pull does

    private func item(_ s: SessionSuggestion, drawer: DrawerChoice? = nil) -> SessionItem {
        SessionItem(message: msg(), group: .oneAtATime, suggestion: s,
                    drawer: drawer.map { DrawerGuess(choice: $0, confidence: .rule, reason: "r") })
    }

    func testPullTargets() {
        let fin = DrawerChoice(.finance)
        XCTAssertEqual(SessionPullTarget.make(item(.putAway(fin)), dateLabel: nil), .putAway(fin, dateLabel: nil))
        XCTAssertEqual(SessionPullTarget.make(item(.addDatesThenPutAway(fin)), dateLabel: "Fri, Nov 13"), .putAway(fin, dateLabel: "Fri, Nov 13"))
        XCTAssertEqual(SessionPullTarget.make(item(.archive), dateLabel: nil), .archive)
        XCTAssertEqual(SessionPullTarget.make(item(.decide), dateLabel: nil), .chooseDrawer)
        XCTAssertEqual(SessionPullTarget.make(item(.decide, drawer: fin), dateLabel: nil), .putAway(fin, dateLabel: nil))
        // A reply suggestion pulled down means handled: its drawer, else Community.
        XCTAssertEqual(SessionPullTarget.make(item(.reply), dateLabel: nil), .putAway(DrawerChoice(.personal), dateLabel: nil))
    }

    func testPullLabelsNameTheDestination() {
        XCTAssertEqual(SessionPullTarget.archive.label, "Archive")
        XCTAssertEqual(SessionPullTarget.chooseDrawer.releaseLabel, "Let go to choose a drawer")
        let t = SessionPullTarget.putAway(DrawerChoice(.finance), dateLabel: nil)
        XCTAssertTrue(t.label.hasPrefix("Put away in "))
        XCTAssertTrue(t.releaseLabel.hasPrefix("Let go: Put away in "))
    }

    // MARK: Likely drawers

    func testLikelyPutsTheGuessFirstAndMatchesWords() {
        let m = msg(from: "Hearth & Co", subject: "Your chimney quote is ready", text: "Quote for inspection and cleaning.")
        let picks = DrawerLikely.top(m, guess: nil, visible: Drawer.builtIns)
        XCTAssertEqual(picks.count, 3)
        XCTAssertEqual(picks.first?.choice.drawer, .home)
        XCTAssertTrue(picks.first?.reason.contains("chimney") ?? false)

        let guess = DrawerGuess(choice: DrawerChoice(.travel), confidence: .rule, reason: "Travel")
        XCTAssertEqual(DrawerLikely.top(m, guess: guess, visible: Drawer.builtIns).first?.choice.drawer, .travel)
    }

    func testLikelyNeverRepeatsAndHealthStaysHealth() {
        let m = msg(subject: "Hello", text: "")
        let picks = DrawerLikely.top(m, guess: nil, visible: Drawer.builtIns, limit: 5)
        XCTAssertEqual(Set(picks.map(\.choice.drawer)).count, picks.count)
        XCTAssertTrue(picks.allSatisfy { !$0.reason.isEmpty })

        let h = msg(subject: "Appointment", health: true)
        XCTAssertEqual(DrawerLikely.top(h, guess: nil, visible: Drawer.builtIns).map(\.choice.drawer), [.health])
    }
}
