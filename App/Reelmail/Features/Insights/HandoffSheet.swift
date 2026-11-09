import SwiftUI

/// Turns one email into a prompt for an outside agent, for tasks Lovely cannot do inside Gmail.
/// Secrets and identifiers are removed first; irreversible steps are listed first and marked.
struct HandoffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let post: Post
    @AppStorage(HandoffAgent.key) private var agentRaw = HandoffAgent.grok.rawValue
    @State private var goal = ""
    @State private var facts = ""
    @State private var irreversible = ""
    @State private var copied: HandoffAgent?

    private var task: HandoffTask {
        func lines(_ s: String) -> [String] { s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return HandoffTask(goal: goal, facts: lines(facts), steps: [], irreversible: lines(irreversible))
    }

    var body: some View {
        NavigationStack {
            Form {
            Group {
                Section("Goal") { TextField("What should the agent do?", text: $goal, axis: .vertical) }
                Section("Irreversible steps (the agent stops before these)") { TextField("One per line", text: $irreversible, axis: .vertical) }
                Section("What it needs to know") { TextField("One per line", text: $facts, axis: .vertical) }
                Section {
                    Picker("Usual agent", selection: $agentRaw) { ForEach(HandoffAgent.allCases) { Text($0.name).tag($0.rawValue) } }.pickerStyle(.segmented)
                    ForEach(orderedAgents) { agent in
                        Button(copied == agent ? "Copied for \(agent.name)" : "Copy for \(agent.name)") {
                            UIPasteboard.general.string = HandoffPrompt.build(task, agent: agent, keepEmails: [])
                            copied = agent
                        }
                    }
                } footer: { Text("Codes, passwords, account numbers and other people's email addresses are removed. Check the text before you send it.") }
            }
            .listRowBackground(CalmStyle.card)
        }
        .calmForm()
            .navigationTitle("Hand off").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task {
                goal = "Do what this email from \(post.email.from.name) asks: \(post.email.subject)"
                facts = Redactor.redact(String(post.email.body.prefix(600)), keepEmails: [])
                irreversible = HandoffPrompt.detectIrreversible(in: post.email.body).joined(separator: "\n")
            }
        }
    }

    private var orderedAgents: [HandoffAgent] {
        let first = HandoffAgent(rawValue: agentRaw) ?? .grok
        return [first] + HandoffAgent.allCases.filter { $0 != first }
    }
}
