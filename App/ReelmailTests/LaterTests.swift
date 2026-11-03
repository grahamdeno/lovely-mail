import XCTest
@testable import Reelmail

final class LaterScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // Nov 2, 2026 is a Monday.
    func testMondayMorningOffersEveningTomorrowAndWeekend() {
        let options = LaterSchedule.options(now: date(2, 9), calendar: calendar)
        XCTAssertEqual(options.map(\.title), ["This evening", "Tomorrow", "This weekend"])
        XCTAssertEqual(options[0].date, date(2, 18))
        XCTAssertEqual(options[1].date, date(3, 8))
        XCTAssertEqual(options[2].date, date(7, 9))
    }

    func testThursdayAfterFiveSkipsEveningAndOffersNextWeek() {
        let options = LaterSchedule.options(now: date(5, 17, 30), calendar: calendar)
        XCTAssertEqual(options.map(\.title), ["Tomorrow", "This weekend", "Next week"])
        XCTAssertEqual(options[2].date, date(9, 8))
    }

    func testSaturdayHasNoWeekendOption() {
        let options = LaterSchedule.options(now: date(7, 10), calendar: calendar)
        XCTAssertEqual(options.map(\.title), ["This evening", "Tomorrow", "Next week"])
    }

    func testSundayNightDoesNotOfferMondayTwice() {
        let options = LaterSchedule.options(now: date(8, 23), calendar: calendar)
        XCTAssertEqual(options.map(\.title), ["Tomorrow"])
        XCTAssertEqual(options[0].date, date(9, 8))
    }

    func testPendingAndPrune() {
        let now = date(2, 9)
        XCTAssertTrue(LaterSchedule.isPending(date(3, 8), now: now))
        XCTAssertFalse(LaterSchedule.isPending(date(2, 8), now: now))
        let kept = LaterSchedule.pruned(["a": date(3, 8), "b": date(3, 8)], keeping: ["a"])
        XCTAssertEqual(Set(kept.keys), ["a"])
        XCTAssertEqual(LaterSchedule.earliestCustom(now: now), now.addingTimeInterval(3600))
    }
}

@MainActor
final class LaterStoreTests: XCTestCase {
    func testPutOffHidesFromHomeThenReturnsFirstInToDo() async {
        let client = FakeInboxClient()
        let defaults = UserDefaults(suiteName: "later-\(UUID())")!
        let store = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await store.load()
        let post = store.posts[0]
        // The fixture message asks something, so it sits in Waiting on you; either way it is on Home.
        func onHome() -> [String] { store.digest.waiting.map(\.id) + store.digest.todo.map(\.id) }
        XCTAssertEqual(onHome(), [post.id])

        store.putOff(post, until: Date().addingTimeInterval(3600))
        XCTAssertTrue(store.isPutOff(post))
        XCTAssertTrue(onHome().isEmpty)
        XCTAssertEqual(store.laterPosts.map(\.post.id), [post.id])
        XCTAssertEqual(store.lastPutOff?.post.id, post.id)

        // The time passes: it is back, tagged, and in To do.
        store.putOff(post, until: Date().addingTimeInterval(-60))
        XCTAssertFalse(store.isPutOff(post))
        XCTAssertTrue(store.isBackFromLater(post))
        XCTAssertEqual(onHome(), [post.id])
        XCTAssertTrue(store.laterPosts.isEmpty)

        store.bringBack(post.id)
        XCTAssertFalse(store.isBackFromLater(post))
    }

    func testLaterIsSavedPerAccountAndDroppedWhenRead() async {
        let client = FakeInboxClient()
        let defaults = UserDefaults(suiteName: "later2-\(UUID())")!
        let first = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await first.load()
        first.putOff(first.posts[0], until: Date().addingTimeInterval(7200))
        let second = FeedStore(gmail: client, summarizeOnDevice: false, triageDefaults: defaults, cacheStore: nil)
        await second.load()
        XCTAssertTrue(second.isPutOff(second.posts[0]), "Later survives a relaunch")
    }
}
