import XCTest
@testable import Reelmail

/// 30 fictional sentences with every date each should yield. Floors: precision 95%, recall 85%.
final class ComingUpCorpusTests: XCTestCase {
    private struct Corpus: Decodable {
        struct Case: Decodable { let id: String; let text: String; let expect: [String] }
        let cases: [Case]
    }
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private var sent: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))! }

    private func text(_ d: MailDate) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = d.hasTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return f.string(from: d.start)
    }

    func testDatesCorpus() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dates-corpus", withExtension: "json"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(corpus.cases.count, 30)
        var tp = 0, fp = 0, fn = 0
        var problems: [String] = []
        for c in corpus.cases {
            let person = Person(id: "dana@mail.example", name: "Dana", email: "dana@mail.example", hue: 0.3)
            let email = Email(id: c.id, threadId: c.id, from: person, to: ["pat@lovely.example"], subject: "Note", date: sent, body: c.text)
            let found = MailDates.extract(email, now: sent, calendar: calendar).map(text)
            tp += found.filter(c.expect.contains).count
            fp += found.filter { !c.expect.contains($0) }.count
            fn += c.expect.filter { !found.contains($0) }.count
            if Set(found) != Set(c.expect) { problems.append("\(c.id) \(c.text) expected \(c.expect) got \(found)") }
        }
        let precision = tp + fp == 0 ? 1 : Double(tp) / Double(tp + fp)
        let recall = tp + fn == 0 ? 1 : Double(tp) / Double(tp + fn)
        print("SCORECARD dates: precision \(Int((precision * 100).rounded()))%, recall \(Int((recall * 100).rounded()))%, \(problems.count) of \(corpus.cases.count) sentences differ")
        for p in problems { print("SCORECARD dates miss " + p) }
        XCTAssertGreaterThanOrEqual(precision, 0.95, "Dates precision fell: \(problems)")
        XCTAssertGreaterThanOrEqual(recall, 0.85, "Dates recall fell: \(problems)")
    }

    /// Several reminders in one conversation show once, from the newest message.
    func testOneEntryPerConversation() {
        func post(_ id: String, daysAgo: Double, body: String) -> Post {
            let person = Person(id: "rink@rink.example", name: "Rink", email: "rink@rink.example", hue: 0.3)
            let email = Email(id: id, threadId: "game", from: person, to: ["pat@lovely.example"], subject: "Game Sunday",
                              date: sent.addingTimeInterval(-daysAgo * 86_400), body: body)
            return Post(email: email, summary: FallbackSummarizer().summarizeSync(SummaryInput(email: email)))
        }
        let older = post("m1", daysAgo: 1, body: "Game is Sunday at 9 PM.")
        let newer = post("m2", daysAgo: 0, body: "Reminder: game is Sunday at 9 PM, arrive by 8:30.")
        let entries = ComingUp.entries(posts: [older, newer], section: { _ in .people }, now: sent, calendar: calendar)
        XCTAssertEqual(entries.map(\.id), ["m2"])
    }
}
