import XCTest
@testable import Reelmail

/// Scores the sorting rules against a labeled, fictional corpus (Fixtures/sorting-corpus.json).
/// The "tune" split is what the rules were adjusted against; "holdout" was written at the same time and never tuned on.
/// The scorecard prints in the CI log as lines starting with "SCORECARD".
final class SortingScorecardTests: XCTestCase {
    private struct Corpus: Decodable {
        let me: String
        let name: String
        let otherAddresses: [String]
        let cases: [Case]
    }
    private struct Case: Decodable {
        let id: String
        let split: String
        let expect: String
        let name: String
        let email: String
        let subject: String
        let body: String
        let daysAgo: Double
        var to: [String]?
        var cc: [String]?
        var bulk: Bool?
        var promotional: Bool?
        var repliedDaysAgo: Double?
    }

    private struct Tally {
        var hit: [FeedSection: Int] = [:], falsePos: [FeedSection: Int] = [:], falseNeg: [FeedSection: Int] = [:]
        var total = 0, correct = 0
        func precision(_ s: FeedSection) -> Double { ratio(hit[s, default: 0], falsePos[s, default: 0]) }
        func recall(_ s: FeedSection) -> Double { ratio(hit[s, default: 0], falseNeg[s, default: 0]) }
        private func ratio(_ a: Int, _ b: Int) -> Double { a + b == 0 ? 1 : Double(a) / Double(a + b) }
    }

    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func load() throws -> Corpus {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sorting-corpus", withExtension: "json"),
                                "sorting-corpus.json is missing from the test bundle")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    func testSortingScorecard() throws {
        let corpus = try load()
        let fallback = FallbackSummarizer()
        let me = Person(id: corpus.me, name: corpus.name, email: corpus.me, hue: 0.5)
        var sent: [Email] = [Email(id: "sent-old", threadId: "t-old", from: me, to: ["x@lovely.example"], subject: "Hi",
                                   date: now.addingTimeInterval(-86_400 * 60), body: "Thanks", isFromMe: true)]
        for c in corpus.cases {
            if let replied = c.repliedDaysAgo {
                sent.append(Email(id: "reply-" + c.id, threadId: "t-" + c.id, from: me, to: [c.email], subject: "Re: " + c.subject,
                                  date: now.addingTimeInterval(-replied * 86_400), body: "Sure.", isFromMe: true))
            }
        }
        let context = TriageContext(account: corpus.me, sent: sent, otherAddresses: corpus.otherAddresses, now: now)

        var tallies: [String: Tally] = ["tune": Tally(), "holdout": Tally(), "all": Tally()]
        var misses: [String] = []
        for c in corpus.cases {
            let expected = try XCTUnwrap(Self.section(named: c.expect), "Unknown section \(c.expect) in \(c.id)")
            let from = Person(id: c.email, name: c.name, email: c.email, hue: 0.3)
            let email = Email(id: c.id, threadId: "t-" + c.id, from: from, to: c.to ?? [corpus.me], cc: c.cc ?? [],
                              subject: c.subject, date: now.addingTimeInterval(-c.daysAgo * 86_400), body: c.body,
                              bulk: c.bulk ?? false, promotional: c.promotional ?? false)
            let post = Post(email: email, summary: fallback.summarizeSync(SummaryInput(email: email)))
            let result = FeedTriage.assess(post, route: .inbox, context: context)
            for key in [c.split, "all"] {
                var t = tallies[key, default: Tally()]
                t.total += 1
                if result.section == expected { t.correct += 1; t.hit[expected, default: 0] += 1 }
                else { t.falsePos[result.section, default: 0] += 1; t.falseNeg[expected, default: 0] += 1 }
                tallies[key] = t
            }
            if result.section != expected {
                misses.append("SCORECARD miss \(c.id) [\(c.split)] expected \(expected.title), got \(result.section.title): \(result.reason)")
            }
        }

        for key in ["tune", "holdout", "all"] {
            let t = tallies[key]!
            print("SCORECARD \(key): \(t.correct)/\(t.total) correct")
            for s in FeedSection.allCases {
                print("SCORECARD   \(key) \(s.title): precision \(Int((t.precision(s) * 100).rounded()))%, recall \(Int((t.recall(s) * 100).rounded()))%")
            }
        }
        misses.forEach { print($0) }

        // Floors. Raising a floor is fine; lowering one needs a reason in the PR.
        let tune = tallies["tune"]!, all = tallies["all"]!
        XCTAssertGreaterThanOrEqual(Double(tune.correct) / Double(tune.total), 0.95, "Tuning set accuracy fell")
        XCTAssertGreaterThanOrEqual(all.precision(.waiting), 0.95, "Waiting on you precision fell")
        XCTAssertGreaterThanOrEqual(all.recall(.waiting), 0.85, "Waiting on you recall fell")
        for s in FeedSection.allCases where s != .waiting {
            XCTAssertGreaterThanOrEqual(all.precision(s), 0.90, "\(s.title) precision fell")
            XCTAssertGreaterThanOrEqual(all.recall(s), 0.90, "\(s.title) recall fell")
        }
    }

    func testCorpusIsWellFormed() throws {
        let corpus = try load()
        XCTAssertGreaterThanOrEqual(corpus.cases.count, 100)
        XCTAssertEqual(Set(corpus.cases.map(\.id)).count, corpus.cases.count, "Duplicate ids")
        for s in FeedSection.allCases {
            XCTAssertTrue(corpus.cases.contains { $0.split == "holdout" && Self.section(named: $0.expect) == s },
                          "\(s.title) has no holdout example")
        }
        // Fictional data only.
        for c in corpus.cases { XCTAssertTrue(c.email.hasSuffix(".example"), "\(c.id) uses a real-looking domain") }
    }

    private static func section(named name: String) -> FeedSection? {
        switch name {
        case "waiting": return .waiting
        case "notes": return .notes
        case "people": return .people
        case "dated": return .dated
        case "updates": return .updates
        case "reading": return .reading
        default: return nil
        }
    }
}
