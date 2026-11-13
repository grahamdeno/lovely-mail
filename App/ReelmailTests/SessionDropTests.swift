import XCTest
@testable import Reelmail

/// Blue bar drop (owner, Nov 13, 2026): what the page says in words, and the dot's flight. All mail is fictional.
final class SessionDropTests: XCTestCase {
    private func msg(text: String = "", ask: String? = nil, health: Bool = false) -> SessionMessage {
        SessionMessage(id: "m", threadId: "t", fromName: "Northline Outfitters", fromAddress: "orders@northline.example",
                       subject: "Your order has shipped", date: Date(timeIntervalSince1970: 1_794_312_000), text: text,
                       section: .updates, category: .updates, isPerson: false, ask: ask, isHealth: health,
                       isFirstTimeSender: false, asksForAction: false, hasDates: false)
    }

    private func summary(_ blurb: String, engine: SummaryEngine = .appleIntelligence, sensitive: Bool = false) -> EmailSummary {
        EmailSummary(headline: "", blurb: blurb, needsReply: false, category: .updates, imageQuery: "", sensitive: sensitive,
                     dates: [], engine: engine)
    }

    // MARK: The words on the page

    func testSummaryLeadsAndTheEmailFillsTheRest() {
        let t = SessionCardText.make(msg(text: "Your rain shell left our warehouse."), summary: summary("Arrives Tuesday."))
        XCTAssertEqual(t.lead, "Arrives Tuesday.")
        XCTAssertFalse(t.leadIsAsk)
        XCTAssertEqual(t.excerpt, "Your rain shell left our warehouse.")
    }

    func testAnAskLeadsInItsOwnWords() {
        let t = SessionCardText.make(msg(text: "Hi! Can you drive Saturday? Thanks.", ask: "Can you drive Saturday?"),
                                     summary: summary("Asks about Saturday."))
        XCTAssertEqual(t.lead, "Can you drive Saturday?")
        XCTAssertTrue(t.leadIsAsk)
        XCTAssertNotNil(t.excerpt)
    }

    func testFallbackSummaryIsNotRepeated() {
        // The fallback summary is the email's first words, so only the email's words show.
        let t = SessionCardText.make(msg(text: "Your rain shell left our warehouse this morning."),
                                     summary: summary("Your rain shell left our warehouse", engine: .fallback))
        XCTAssertNil(t.lead)
        XCTAssertEqual(t.excerpt, "Your rain shell left our warehouse this morning.")
    }

    func testHealthAndSensitiveMailShowNoOwnWords() {
        let health = SessionCardText.make(msg(text: "Your results are ready.", health: true), summary: summary("Results ready."))
        XCTAssertNil(health.excerpt)
        XCTAssertEqual(health.lead, "Results ready.")
        let code = SessionCardText.make(msg(text: "Your code is 482913."), summary: summary("A sign-in code.", sensitive: true))
        XCTAssertNil(code.excerpt)
        // Nothing else to say: the summary still shows, even from the fallback.
        let bare = SessionCardText.make(msg(text: "Code 482913", health: true), summary: summary("Code", engine: .fallback))
        XCTAssertEqual(bare.lead, "Code")
    }

    func testCleaningCollapsesSpaceAndCutsAtAWord() {
        XCTAssertEqual(SessionCardText.clean("  Hello   there \n\n\n\nSecond   line\n\n"), "Hello there\n\nSecond line")
        let long = Array(repeating: "word", count: 400).joined(separator: " ")
        let cut = SessionCardText.clean(long)
        XCTAssertLessThanOrEqual(cut.count, SessionCardText.excerptLimit + 1)
        XCTAssertTrue(cut.hasSuffix("word\u{2026}"))
    }

    // MARK: The dot's flight

    private func fly(_ fps: Double = 120) -> (flight: DropFlight, landings: [Double], maxX: Double, apexX: Double, frames: Int) {
        var f = DropFlight()
        var landings: [Double] = []
        var maxX = f.x, apexX = f.x, frames = 0
        var wasRising = true
        while !f.finished && frames < 2_000 {
            if f.step(1 / fps) != nil { landings.append(f.elapsed) }
            maxX = max(maxX, f.x)
            if wasRising, f.vy > 0, f.bounces == 0 { apexX = f.x; wasRising = false }
            frames += 1
        }
        return (f, landings, maxX, apexX, frames)
    }

    func testFlightGoesRightThenBackLeftOfCenter() {
        let r = fly()
        XCTAssertGreaterThan(r.maxX, 290, "flies up and to the right")
        XCTAssertLessThan(r.apexX, DropFlight.width / 2, "back left of center by the top of the arc")
    }

    func testThreeBouncesThenThroughTheBarQuickly() {
        let r = fly()
        XCTAssertEqual(r.landings.count, 3)
        XCTAssertTrue(r.flight.finished)
        XCTAssertLessThan(r.flight.elapsed, 1.9, "fast: under two seconds end to end")
        // Each bounce is shorter than the one before: no hang at the bottom.
        let gaps = zip(r.landings.dropFirst(), r.landings).map { $0 - $1 }
        XCTAssertGreaterThan(gaps[0], gaps[1])
    }

    func testFlightNeverStops() {
        // No joints: until it is through the bar it is always moving.
        var f = DropFlight()
        var frames = 0
        while !f.through && frames < 2_000 {
            let before = (f.x, f.y)
            _ = f.step(1.0 / 120)
            XCTAssertGreaterThan(hypot(f.x - before.0, f.y - before.1), 0.05, "moving at \(f.elapsed)s")
            frames += 1
        }
    }

    func testSameFlightAtThirtyFramesASecond() {
        let slow = fly(30), fast = fly(120)
        XCTAssertEqual(slow.landings.count, 3)
        XCTAssertEqual(slow.flight.elapsed, fast.flight.elapsed, accuracy: 0.15)
    }

    func testBarRisesWithThePull() {
        let bar = SessionDropBar()
        XCTAssertEqual(bar.height, 20)
        bar.pull = 0.5
        XCTAssertEqual(bar.height, 55)
        bar.pull = 2
        XCTAssertEqual(bar.height, 90)
    }
}
