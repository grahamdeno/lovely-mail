import XCTest
@testable import Reelmail

/// Fictional fixtures only. No real names, amounts or addresses.
final class InsightParserTests: XCTestCase {
    private let day = InsightDates.parse("10/15/2026")!

    private func input(_ name: String, _ address: String, _ subject: String, _ body: String = "") -> InsightInput {
        InsightInput(id: "m1", fromName: name, fromAddress: address, subject: subject, date: day, body: body)
    }

    func testDatesParseAsUTCDays() {
        XCTAssertEqual(InsightDates.iso(InsightDates.parse("November 3, 2026")!), "2026-11-03")
        XCTAssertEqual(InsightDates.iso(InsightDates.parse("2/9/2027")!), "2027-02-09")
        XCTAssertNil(InsightDates.parse("soon"))
    }

    func testRegistrableDomain() {
        XCTAssertEqual(InsightText.registrable("mail.example.com"), "example.com")
        XCTAssertEqual(InsightText.registrable("a.b.example.co.uk"), "example.co.uk")
    }

    func testSenseMonth() {
        let body = "Your October 2026 report <https://x.example/a> 612 kWh used 40 kWh produced $4.29 per day Down $0.35 a day from September. Dryer $12.40 this month Water Heater $18.10 this month"
        let facts = InsightParsers.parse(input("Sense", "hello@mail.sense.com", "Your Sense report for October 2026", body))
        guard case .energyMonth(let e)? = facts.first else { return XCTFail("no energy month") }
        XCTAssertEqual(e.kwhUsed, 612)
        XCTAssertEqual(e.kwhProduced, 40)
        XCTAssertEqual(e.dollarsPerDay, 4.29, accuracy: 0.001)
        XCTAssertEqual(e.changePerDay ?? 0, -0.35, accuracy: 0.001)
        XCTAssertEqual(InsightDates.iso(e.month), "2026-10-01")
        XCTAssertEqual(e.devices.count, 2)
    }

    func testUsageAlertAndCycle() {
        let body = "Your usage as of October 14, 2026 is on track. Cost so far $88.12 | 9/20/2026 | 10/19/2026 | 29 |"
        let facts = InsightParsers.parse(input("Example Power", "alerts@examplepower.com", "Energy usage alert", body))
        guard case .usageAlert(let a)? = facts.first else { return XCTFail("no alert") }
        XCTAssertEqual(a.costToDate, 88.12, accuracy: 0.001)
        XCTAssertEqual(InsightDates.iso(a.cycleEnd!), "2026-10-19")
    }

    func testProgramOffer() {
        let body = "Earn up to $75 in bill credits by joining Smart Saver Program for enrolling your thermostat, water heater."
        let facts = InsightParsers.parse(input("Example Power", "news@examplepower.com", "Save with Smart Saver", body))
        guard case .offer(let o)? = facts.first(where: { if case .offer = $0 { return true } else { return false } }) else { return XCTFail("no offer") }
        XCTAssertEqual(o.credit, 75)
        XCTAssertEqual(o.devices.count, 2)
    }

    func testPaymentPosted() {
        let body = "Payment Amount: $120.50 Date Posted: October 12, 2026"
        let facts = InsightParsers.parse(input("Example Power", "bill@examplepower.com", "Payment received", body))
        guard case .bill(let b)? = facts.first else { return XCTFail("no bill") }
        XCTAssertEqual(b.kind, .payment)
        XCTAssertEqual(b.amount, 120.50)
        XCTAssertFalse(b.problem)
    }

    func testStatementWithWaterLine() {
        let body = "Amount Due $64.20 Due Date 11/05/2026 Water $31.00 Sewer $22.10"
        let facts = InsightParsers.parse(input("Example Water Utility", "billing@examplewater.org", "Your bill is ready", body))
        guard case .bill(let b)? = facts.first else { return XCTFail("no bill") }
        XCTAssertEqual(b.amount, 64.20)
        XCTAssertTrue(b.involvesWater)
        XCTAssertEqual(InsightDates.iso(b.dueOn!), "2026-11-05")
    }

    func testPaymentProblemAlarmPrecision() {
        let bad = ["Your payment failed", "Final notice: account past due", "Autopay was unsuccessful", "Service will be disconnected"]
        for s in bad { XCTAssertTrue(InsightParsers.hasPaymentProblem(subject: s, text: ""), s) }
        let fine = ["Your bill is ready", "Thanks for your payment", "Statement available", "Payment due on the 5th"]
        for s in fine { XCTAssertFalse(InsightParsers.hasPaymentProblem(subject: s, text: ""), s) }
        // Fine print and reminders are not problems.
        XCTAssertFalse(InsightParsers.hasPaymentProblem(subject: "Your bill is ready", text: "Payments received after the due date are considered past due and may incur a fee."))
        XCTAssertFalse(InsightParsers.hasPaymentProblem(subject: "Avoid a past due balance", text: ""))
        XCTAssertFalse(InsightParsers.hasPaymentProblem(subject: "Reminder: past due date is Nov 5", text: ""))
        // A real problem in the body counts even when the subject is bland.
        XCTAssertTrue(InsightParsers.hasPaymentProblem(subject: "Account update", text: "We were unable to process your payment of $40."))
        XCTAssertTrue(InsightParsers.hasPaymentProblem(subject: "Your payment was declined", text: ""))
    }

    func testRenewal() {
        let facts = InsightParsers.parse(input("Example Cloud", "billing@examplecloud.com", "You will be charged for your Storage Plan in 7 days"))
        guard case .renewal(let r)? = facts.first else { return XCTFail("no renewal") }
        XCTAssertEqual(r.what, "Storage Plan")
        XCTAssertEqual(InsightDates.iso(r.chargesOn), "2026-10-22")
    }

    func testAccountNoticeSubjectOnly() {
        let facts = InsightParsers.parse(input("Example Brokerage", "alerts@mail.fidelity.com", "Take action on your account", "balance $1,234,567 account 123456789"))
        guard case .account(let n)? = facts.first else { return XCTFail("no notice") }
        XCTAssertEqual(n.kind, .brokerage)
        XCTAssertTrue(n.asksAction)
        let encoded = String(data: try! JSONEncoder().encode(n), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("1,234,567"))
        XCTAssertFalse(encoded.contains("123456789"))
    }

    func testHealthMailYieldsOnlyAppointmentDates() {
        let subject = "Your appointment is scheduled for 11/20/2026 9:30 AM"
        let facts = InsightParsers.parse(input("Example Clinic", "no-reply@exampleclinic.org", subject, "Balance due $250.00 Amount Due $250.00"))
        XCTAssertEqual(facts.count, 1)
        guard case .appointment(let a)? = facts.first else { return XCTFail("no appointment") }
        XCTAssertTrue(a.hasTime)
        XCTAssertEqual(InsightDates.iso(a.start), "2026-11-20")
        let none = InsightParsers.parse(input("Example Clinic", "no-reply@exampleclinic.org", "Your statement", "Amount Due $250.00"))
        XCTAssertTrue(none.isEmpty)
    }

    func testStoreAddReplacesById() {
        var store = InsightStore()
        store.add(.appointment(Appointment(id: "a", start: day, hasTime: false)))
        store.add(.appointment(Appointment(id: "a", start: day, hasTime: true)))
        XCTAssertEqual(store.appointments.count, 1)
        XCTAssertTrue(store.appointments[0].hasTime)
        let data = try! JSONEncoder().encode(store)
        XCTAssertEqual(try! JSONDecoder().decode(InsightStore.self, from: data), store)
    }
}

final class EnergyInsightTests: XCTestCase {
    private func month(_ iso: String, _ perDay: Double, devices: [EnergyDevice] = []) -> EnergyMonth {
        EnergyMonth(id: iso, month: InsightDates.parse(iso)!, kwhUsed: 500, kwhProduced: 0, dollarsPerDay: perDay, changePerDay: nil, devices: devices)
    }

    func testHeadlineWithChange() {
        var m = month("2026-10-01", 4.29); m.changePerDay = -0.35
        XCTAssertEqual(EnergyInsights.headline(m), "$4.29 a day last month, down $0.35 from the month before")
        XCTAssertEqual(EnergyInsights.headline(nil), "No energy report found yet")
    }

    func testOfferWinsThenTopDeviceThenSpike() {
        let offer = ProgramOffer(id: "o", program: "Smart Saver", credit: 75, devices: ["thermostat"], seenOn: Date())
        XCTAssertTrue(EnergyInsights.suggestion(months: [month("2026-10-01", 4)], offer: offer)!.contains("$75"))
        let dev = [EnergyDevice(name: "Dryer", dollars: 22)]
        XCTAssertTrue(EnergyInsights.suggestion(months: [month("2026-10-01", 4, devices: dev)], offer: nil)!.contains("Dryer"))
        let spike = [month("2026-07-01", 3), month("2026-08-01", 3), month("2026-09-01", 3), month("2026-10-01", 4)]
        XCTAssertTrue(EnergyInsights.suggestion(months: spike, offer: nil)!.contains("percent above"))
        XCTAssertNil(EnergyInsights.suggestion(months: [month("2026-10-01", 3)], offer: nil))
    }

    func testSenseHiddenOnlyAfterSnapshot() {
        var store = InsightStore()
        XCTAssertFalse(EnergyInsights.shouldHideFromHome(domain: "sense.com", fromName: "Sense", store: store))
        store.add(.energyMonth(month("2026-10-01", 4)))
        XCTAssertTrue(EnergyInsights.shouldHideFromHome(domain: "sense.com", fromName: "Sense", store: store))
        XCTAssertFalse(EnergyInsights.shouldHideFromHome(domain: "example.com", fromName: "Other", store: store))
    }
}

@MainActor
final class EnergyHomeRuleTests: XCTestCase {
    func testSenseMailLeavesHomeOnlyAfterAReportIsRead() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engine = InsightEngine(storage: InsightStorage(directory: dir))
        XCTAssertTrue(engine.store.isEmpty)
        XCTAssertFalse(EnergyInsights.shouldHideFromHome(domain: "sense.com", fromName: "Sense", store: engine.store))
    }
}
