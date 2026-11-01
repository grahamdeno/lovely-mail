import SwiftUI

/// Debug screen: run the summarizer over the sample emails or pasted text and see quality + latency.
struct SummaryLabView: View {
    @State private var model = SummaryLabModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RM.Space.m) {
                InfoCard(title: "Model", value: model.status.title, detail: model.status.detail)

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
                .buttonStyle(RMButtonStyle(kind: .ghostLight))
                .background(Color.white)
                .rmCorner(RM.Radius.button)
                .disabled(model.running)

                if !model.results.isEmpty { stats }

                ForEach(model.results) { LabResultCard(result: $0) }

                Text("Paste an email").font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
                    .padding(.top, RM.Space.s)
                TextEditor(text: $model.pasted)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(minHeight: 160)
                    .padding(RM.Space.s)
                    .background(RM.Palette.surface)
                    .rmCorner(RM.Radius.card)
                Button {
                    Task { await model.runPasted() }
                } label: {
                    Label("Summarize pasted text", systemImage: "text.badge.checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(RMButtonStyle(kind: .ghostDark))
                .disabled(model.running || model.pasted.isEmpty)
                if let r = model.pastedResult { LabResultCard(result: r) }

                Text("Everything here runs on this iPhone. Nothing is sent anywhere, and email text is never logged.")
                    .font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
            }
            .padding(RM.Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RM.Palette.sheet)
        .navigationTitle("Summary Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stats: some View {
        let f = { (x: Double?) in x.map { String(format: "%.0f", $0) } ?? "–" }
        let w = { (x: Double?) in x.map { String(format: "%.1f", $0) } ?? "–" }
        return VStack(spacing: RM.Space.s) {
            HStack(spacing: RM.Space.s) {
                StatTile(value: f(model.averageMs) + " ms", label: "average")
                StatTile(value: f(model.medianMs) + " ms", label: "median")
                StatTile(value: f(model.maxMs) + " ms", label: "slowest")
            }
            HStack(spacing: RM.Space.s) {
                StatTile(value: w(model.averageHeadlineWords), label: "headline words")
                StatTile(value: w(model.averageBlurbWords), label: "blurb words")
                StatTile(value: "\(model.needsReplyCount)", label: "need reply", highlight: model.needsReplyCount > 0)
            }
            if model.successes.count < model.results.count {
                Text("\(model.results.count - model.successes.count) failed")
                    .font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
            }
        }
    }
}

struct LabResultCard: View {
    let result: LabResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.label).font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
                Spacer()
                Text(String(format: "%.0f ms", result.milliseconds))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RM.Palette.secondary)
            }
            if let s = result.summary {
                Text(s.headline).font(RM.Typo.callout.weight(.semibold)).foregroundStyle(.white)
                Text(s.blurb).font(RM.Typo.caption).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 6) {
                    Tag(s.engine == .appleIntelligence ? "AI" : "fallback")
                    Tag(s.category.label)
                    if s.needsReply { NeedsReplyTag(onLight: false) }
                    if s.sensitive { Tag("sensitive") }
                }
                Text("photo: \(s.imageQuery)" + (s.dates.isEmpty ? "" : " · dates: " + s.dates.joined(separator: ", ")))
                    .font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
            } else if let e = result.error {
                Text(e).font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
            }
        }
        .padding(RM.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RM.Palette.surface)
        .rmCorner(RM.Radius.card)
    }
}

private struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(RM.Typo.micro)
            .foregroundStyle(RM.Palette.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: RM.Radius.button, style: .continuous)
                .strokeBorder(RM.Palette.hairline))
    }
}
