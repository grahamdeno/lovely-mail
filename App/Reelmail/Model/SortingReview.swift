import Foundation
import Observation

/// Your verdicts on where Lovely sorted a message: right, or which section it belongs in.
/// Stored on this phone only (message ids and section numbers, never subjects or bodies).
/// Verdicts never change sorting by themselves; they are a scorecard you can share for tuning.
@MainActor
@Observable
final class SortingReview {
    struct Verdict: Codable, Equatable {
        /// The section Lovely showed when you reviewed it.
        var shown: Int
        /// The section you said it belongs in. Equal to `shown` when Lovely was right.
        var correct: Int
        var reviewedAt: Date

        var isRight: Bool { shown == correct }
    }

    private(set) var verdicts: [String: Verdict] = [:]
    private let defaults: UserDefaults
    private let key: String

    init(accountID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "reelmail.review.v1." + accountID
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([String: Verdict].self, from: data) {
            verdicts = saved
        }
    }

    func verdict(for messageID: String) -> Verdict? { verdicts[messageID] }

    func mark(_ messageID: String, shown: FeedSection, correct: FeedSection, now: Date = Date()) {
        verdicts[messageID] = Verdict(shown: shown.rawValue, correct: correct.rawValue, reviewedAt: now)
        save()
    }

    func clear(_ messageID: String) { verdicts[messageID] = nil; save() }
    func reset() { verdicts = [:]; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(verdicts) { defaults.set(data, forKey: key) }
    }
}

/// Builds the shareable review summary. Pure, so it is tested without views.
enum SortingReviewSummary {
    struct Item {
        let verdict: SortingReview.Verdict
        let reason: String
        let senderFirstName: String
        let senderAddress: String
        let subject: String?
    }

    /// Counts per section, plus each miss with the rule's reason. Sender names and addresses are replaced,
    /// and subjects appear only when `subjects` is true (and never for private messages; pass nil for those).
    static func text(_ items: [Item], includeSubjects: Bool, date: Date = Date()) -> String {
        var lines = ["Lovely sorting review, " + date.formatted(date: .abbreviated, time: .omitted)]
        let right = items.filter(\.verdict.isRight).count
        let percent = items.isEmpty ? 0 : Int((Double(right) / Double(items.count) * 100).rounded())
        lines.append("Reviewed \(items.count), right \(right) (\(percent)%)")
        lines.append("")
        for section in FeedSection.allCases {
            let shown = items.filter { $0.verdict.shown == section.rawValue }
            let belongs = items.filter { $0.verdict.correct == section.rawValue }
            guard !shown.isEmpty || !belongs.isEmpty else { continue }
            let shownRight = shown.filter(\.verdict.isRight).count
            let found = belongs.filter(\.verdict.isRight).count
            lines.append("\(section.title): shown \(shown.count), right \(shownRight); belongs \(belongs.count), found \(found)")
        }
        let misses = items.filter { !$0.verdict.isRight }
        if !misses.isEmpty {
            lines.append("")
            lines.append("Misses:")
            for m in misses {
                let shown = FeedSection(rawValue: m.verdict.shown)?.title ?? "?"
                let correct = FeedSection(rawValue: m.verdict.correct)?.title ?? "?"
                var line = "- Shown in \(shown), belongs in \(correct). Reason: \(anonymize(m))"
                if includeSubjects, let subject = m.subject { line += " Subject: \(subject)" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func anonymize(_ item: Item) -> String {
        var reason = item.reason
        if !item.senderAddress.isEmpty { reason = reason.replacingOccurrences(of: item.senderAddress, with: "[address]") }
        if item.senderFirstName.count > 1 { reason = reason.replacingOccurrences(of: item.senderFirstName, with: "Sender") }
        return reason
    }
}
