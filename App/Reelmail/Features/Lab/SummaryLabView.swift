import SwiftUI

/// Debug screen: run the summarizer over the sample emails or pasted text and see quality + latency.
struct SummaryLabView: View {
    @State private var model = SummaryLabModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ProfileCard(title: "Model", value: model.status.title, detail: model.status.detail)

                Picker("Engine", selection: $model.choice) {
                    ForEach(LabEngineChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Button {
                    Task { await model.runSamples() }
                } label: {
                    Label(model.running ? "Running \(model.progress)/\(SampleData.emails.count)…" : "Run on \(SampleData.emails.count) sample emails",
                          systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CalmActionStyle(prominent: true))
                .disabled(model.running)

                if !model.results.isEmpty { stats }

                ForEach(model.results) { LabResultCard(result: $0) }

                Text("Paste an email").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                    .padding(.top, 8)
                TextEditor(text: $model.pasted)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
                Button {
                    Task { await model.runPasted() }
                } label: {
                    Label("Summarize pasted text", systemImage: "text.badge.checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(CalmActionStyle())
                .disabled(model.running || model.pasted.isEmpty)
                if let r = model.pastedResult { LabResultCard(result: r) }

                Text("Everything here runs on this iPhone. Nothing is sent anywhere, and email text is never logged.")
                    .font(.lovely(.caption2)).foregroundStyle(CalmStyle.secondary)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Summary Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stats: some View {
        let f = { (x: Double?) in x.map { String(format: "%.0f", $0) } ?? "–" }
        let w = { (x: Double?) in x.map { String(format: "%.1f", $0) } ?? "–" }
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatTile(value: f(model.averageMs) + " ms", label: "average")
                StatTile(value: f(model.medianMs) + " ms", label: "median")
                StatTile(value: f(model.maxMs) + " ms", label: "slowest")
            }
            HStack(spacing: 8) {
                StatTile(value: w(model.averageHeadlineWords), label: "headline words")
                StatTile(value: w(model.averageBlurbWords), label: "blurb words")
                StatTile(value: "\(model.needsReplyCount)", label: "need reply", highlight: model.needsReplyCount > 0)
            }
            if model.successes.count < model.results.count {
                Text("\(model.results.count - model.successes.count) failed")
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
        }
    }
}

struct LabResultCard: View {
    let result: LabResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.label).font(.lovely(.caption2)).foregroundStyle(CalmStyle.secondary)
                Spacer()
                Text(String(format: "%.0f ms", result.milliseconds))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CalmStyle.secondary)
            }
            if let s = result.summary {
                Text(s.headline).font(.lovely(.subheadline, .semibold)).foregroundStyle(CalmStyle.ink)
                Text(s.blurb).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                HStack(spacing: 6) {
                    Tag(s.engine == .appleIntelligence ? "AI" : "fallback")
                    Tag(s.category.label)
                    if s.needsReply { Tag("needs reply") }
                    if s.sensitive { Tag("sensitive") }
                }
                Text("photo: \(s.imageQuery)" + (s.dates.isEmpty ? "" : " · dates: " + s.dates.joined(separator: ", ")))
                    .font(.lovely(.caption2)).foregroundStyle(CalmStyle.secondary)
            } else if let e = result.error {
                Text(e).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.lovely(.caption2))
            .foregroundStyle(CalmStyle.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(CalmStyle.divider))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var highlight = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.lovely(.headline)).foregroundStyle(highlight ? CalmStyle.blue : CalmStyle.ink).lineLimit(1)
            Text(label).font(.lovely(.caption2)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
