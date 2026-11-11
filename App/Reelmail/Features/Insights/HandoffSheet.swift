import SwiftUI

/// Hand to Grok from one email (owner, Nov 11, 2026: "The only Grok path left is Hand to Grok"). The task is his to
/// edit; the prompt carries the stop line, the task and at most three facts (never from health mail), and one tap POSTs
/// it to his Grok Bot routine. Only a 200 counts as sent; otherwise the share sheet opens and the sheet says why.
/// Replaces the old copy-for-Claude-or-Grok sheet and the in-app form filler.
struct HandToGrokSheet: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var task: String
    let facts: [GrokFact]
    /// Health mail: no prompt is written for it at all.
    var blocked = false
    var onSent: () -> Void = {}
    @State private var sending = false
    @State private var note: String?
    @State private var shareText: ShareText?

    init(task: String, facts: [GrokFact], blocked: Bool = false, onSent: @escaping () -> Void = {}) {
        _task = State(initialValue: task)
        self.facts = facts
        self.blocked = blocked
        self.onSent = onSent
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hand to Grok").font(.title2.weight(.bold))
                if blocked {
                    Text("Health mail stays on this iPhone, so Lovely does not write a prompt for it.").foregroundStyle(CalmStyle.secondary)
                    Spacer()
                } else {
                    TextField("What should Grok do?", text: $task, axis: .vertical)
                        .lineLimit(2...6)
                        .padding(12).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("handToGrok.task")
                    Text("Grok Bot stops and asks you before it submits, pays, signs, sends, deletes anything, or uploads an ID or personal document. Its report comes back under Grok reports.")
                        .font(.callout).foregroundStyle(CalmStyle.secondary)
                    if let note { Text(note).font(.callout).foregroundStyle(CalmStyle.roseInk) }
                    Spacer()
                    sendButton
                }
            }
            .padding(20)
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
            .toolbar { Button("Cancel") { dismiss() } }
            .sheet(item: $shareText) { item in ActivityView(text: item.text).ignoresSafeArea().presentationDetents([.medium, .large]) }
        }
        .presentationDetents([.medium, .large])
    }

    private var cleanTask: String { task.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder private var sendButton: some View {
        let title = sending ? "Sending\u{2026}" : "Send to Grok"
        if let me = store.grokReportAddress, store.actions != nil, !store.grokReportsFiled {
            let preview = GrokHandoff.filterPreview(owner: me)
            Text(preview.lines.first ?? "").font(.caption).foregroundStyle(CalmStyle.secondary)
            SessionConfirmButton(title: title, previews: [preview], enabled: !sending && !cleanTask.isEmpty, identifier: "handToGrok.send") { approvals in
                store.setUpGrokReports(confirmed: approvals[0])
                deliver()
            }
        } else {
            Button(title) { deliver() }
                .buttonStyle(SessionButtonStyle()).disabled(sending || cleanTask.isEmpty).accessibilityIdentifier("handToGrok.send")
        }
    }

    private func deliver() {
        let t = cleanTask
        guard !t.isEmpty, !sending, !blocked else { return }
        sending = true
        let prompt = GrokHandoff.prompt(task: t, facts: facts, reportTo: store.grokReportAddress ?? "my email address")
        Task {
            let result = await GrokWebhook.send(task: t, prompt: prompt)
            sending = false
            if result.accepted {
                GrokHandoffLog().add(.init(id: UUID(), question: t, task: t, title: GrokHandoff.shortTitle(t), sentAt: Date(), report: nil))
                onSent()
                dismiss()
            } else {
                note = result.note
                UIPasteboard.general.string = prompt
                shareText = ShareText(text: prompt)
            }
        }
    }
}

extension HandToGrokSheet {
    /// From an open email or a note: the task names the email; the facts are its sender and subject (redacted).
    init(post: Post) {
        let health = HealthMail.isHealth(address: post.email.from.email, name: post.email.from.name, subject: post.email.subject)
        self.init(task: "Do what this email from \(post.email.from.name) asks: \(post.email.subject)",
                  facts: GrokHandoff.facts(from: post.email.from.name, subject: post.email.subject, isHealth: health),
                  blocked: health || post.summary.sensitive)
    }
}
