import XCTest
@testable import Reelmail

/// Fictional calendar text only.
final class PhotoEventsTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }

    func testTimeRanges() {
        XCTAssertEqual(PhotoEvents.timeRange("9:00 AM – 10:30 AM Sprint Review")?.0, 540)
        XCTAssertEqual(PhotoEvents.timeRange("9:00 AM – 10:30 AM Sprint Review")?.1, 630)
        XCTAssertEqual(PhotoEvents.timeRange("9:00 AM – 10:30 AM Sprint Review")?.2, "Sprint Review")
        XCTAssertEqual(PhotoEvents.timeRange("11-1pm Planning")?.0, 660)
        XCTAssertEqual(PhotoEvents.timeRange("13:00-14:00 Standup")?.1, 840)
        XCTAssertNil(PhotoEvents.timeRange("Room 3-4"))
    }

    func testListParsing() {
        let lines = [PhotoTextLine(text: "Tuesday, November 10", x: 0.1, y: 0.1),
                     PhotoTextLine(text: "9:00 AM - 9:30 AM Team standup", x: 0.1, y: 0.2),
                     PhotoTextLine(text: "1:00 PM - 2:00 PM", x: 0.1, y: 0.3),
                     PhotoTextLine(text: "Design review", x: 0.1, y: 0.35)]
        let events = PhotoEvents.parse(lines, now: at(9, 12), calendar: cal)
        XCTAssertEqual(events.map(\.title), ["Team standup", "Design review"])
        XCTAssertEqual(events.first?.start, at(10, 9))
        XCTAssertEqual(events.last?.end, at(10, 14))
    }

    func testDuplicatesMatchTitleAndTime() {
        let e = PhotoEvent(title: "Sprint Review", start: at(10, 10), end: at(10, 11))
        XCTAssertTrue(PhotoEvents.isDuplicate(e, of: [("sprint review – ATLAS", at(10, 10), at(10, 11))]))
        XCTAssertTrue(PhotoEvents.isDuplicate(e, of: [("Sprint Review meeting", at(10, 10, 15), at(10, 11))]))
        XCTAssertFalse(PhotoEvents.isDuplicate(e, of: [("Sprint Review", at(11, 10), at(11, 11))]), "Another day is not a duplicate")
        XCTAssertFalse(PhotoEvents.isDuplicate(e, of: [("Lunch", at(10, 10), at(10, 11))]), "Another title is not a duplicate")
    }

    /// Claude answers with the calendar_events tool; Lovely reads it into events.
    func testClaudeCalendarAnswerParses() throws {
        let json = """
        {"content":[{"type":"tool_use","name":"calendar_events","input":{"events":[
          {"title":"Sprint Review","day":"2026-11-10","start":"10:00","end":"11:00","all_day":false},
          {"title":"Offsite","day":"2026-11-12","start":"","end":"","all_day":true}]}}]}
        """
        let events = try CalendarPhotoReader.parse(Data(json.utf8))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].title, "Sprint Review")
        XCTAssertTrue(events[1].allDay)
        XCTAssertTrue(CalendarPhotoReader.prompt(today: "2026-11-09", timeZone: "America/New_York").contains("calendar_events"))
    }
}
