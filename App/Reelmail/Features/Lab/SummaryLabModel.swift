import Foundation
import Observation

/// One timed summarizer run.
struct LabResult: Identifiable {
    let id = UUID()
    let label: String
    let summary: EmailSummary?
    let error: String?
    let milliseconds: Double
}

enum LabEngineChoice: String, CaseIterable, Identifiable {
    case auto = "Auto", appleIntelligence = "Apple Intelligence", fallback = "Fallback"
    var id: String { rawValue }
}

/// Step-3 test: how good and how fast are on-device summaries? Runs on sample data or pasted text.
@MainActor
@Observable
final class SummaryLabModel {
    var choice: LabEngineChoice = .auto
    var pasted: String = SampleData.labPasteExample
    private(set) var results: [LabResult] = []
    private(set) var pastedResult: LabResult?
    private(set) var running = false
    private(set) var progress = 0

    var status: ModelStatus { ModelStatus.current }

    func summarizer() -> any EmailSummarizer {
        switch choice {
        case .auto: return SummarizerFactory.best()
        case .appleIntelligence: return AppleIntelligenceSummarizer()
        case .fallback: return FallbackSummarizer()
        }
    }

    func runSamples() async {
        guard !running else { return }
        running = true
        progress = 0
        results = []
        defer { running = false }
        let s = summarizer()
        if s.engine == .appleIntelligence { AppleIntelligenceSummarizer.prewarm() }
        for email in SampleData.emails {
            results.append(await Self.time(s, SummaryInput(email: email), label: email.from.name))
            progress += 1
        }
    }

    func runPasted() async {
        guard !running else { return }
        running = true
        defer { running = false }
        pastedResult = await Self.time(summarizer(), SummaryInput(pasted: pasted), label: "Pasted text")
    }

    static func time(_ summarizer: any EmailSummarizer, _ input: SummaryInput, label: String) async -> LabResult {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let summary = try await summarizer.summarize(input)
            return LabResult(label: label, summary: summary, error: nil, milliseconds: ms(clock.now - start))
        } catch {
            return LabResult(label: label, summary: nil, error: String(describing: error), milliseconds: ms(clock.now - start))
        }
    }

    static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    // MARK: Stats

    var successes: [LabResult] { results.filter { $0.summary != nil } }
    var averageMs: Double? { Self.mean(successes.map(\.milliseconds)) }
    var medianMs: Double? { Self.median(successes.map(\.milliseconds)) }
    var maxMs: Double? { successes.map(\.milliseconds).max() }
    var averageHeadlineWords: Double? { Self.mean(successes.compactMap { $0.summary.map { Double(TextClamp.wordCount($0.headline)) } }) }
    var averageBlurbWords: Double? { Self.mean(successes.compactMap { $0.summary.map { Double(TextClamp.wordCount($0.blurb)) } }) }
    var needsReplyCount: Int { successes.filter { $0.summary?.needsReply == true }.count }

    static func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
