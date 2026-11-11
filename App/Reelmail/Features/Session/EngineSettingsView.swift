import SwiftUI

/// Settings > AI > Conversation engine. Apple Intelligence on this iPhone is the only engine (owner, Nov 11, 2026):
/// no keys, no picker, nothing sent to Claude or Grok. Web tasks are offered as Hand to Grok.
struct EngineSettingsView: View {
    @Environment(Router.self) private var router
    @State private var examplesCleared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Intelligence").font(.headline)
                    Text("Understands what you say in a session, answers questions about your mail, and reads calendar photos, all on this iPhone. Health mail never leaves it.")
                        .font(.callout).foregroundStyle(CalmStyle.secondary)
                    Label(ModelStatus.current.isAvailable ? "On" : "Off on this iPhone", systemImage: ModelStatus.current.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(ModelStatus.current.isAvailable ? CalmStyle.green : CalmStyle.roseInk)
                        .accessibilityIdentifier("engine.apple.status")
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 6) {
                    Text("WHAT GOES OUT").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                    Text("Nothing goes to Claude or to the Grok API. Anything that needs the web (a form, a sign-up, a search on a site) becomes a Hand to Grok task: you see it first, and one tap sends it to your Grok Bot.")
                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                }

                Button { router.open(.engineScorecard) } label: { Label("Engine scorecard", systemImage: "checklist").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
                Button(role: .destructive) { SessionExampleStore().clear(); examplesCleared = true } label: {
                    Text(examplesCleared ? "Learned examples cleared" : "Clear learned examples").frame(maxWidth: .infinity)
                }
                .buttonStyle(CalmActionStyle())
            }
            .padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .navigationTitle("Conversation engine").navigationBarTitleDisplayMode(.inline)
    }
}

/// Testing tools: Apple Intelligence against the fictional scorecard sentences, on this iPhone.
struct EngineScorecardView: View {
    @State private var results: [EngineKind: [EngineScorecard.Result]] = [:]
    @State private var running: EngineKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(EngineScorecard.cases.count) made-up requests, each with the right answer. Run an engine to see how many it gets right.")
                    .font(.callout).foregroundStyle(CalmStyle.secondary)
                ForEach(EngineKind.allCases) { kind in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(kind.name).font(.headline)
                            Spacer()
                            if let r = results[kind] {
                                Text("\(r.filter(\.passed).count) of \(r.count)").font(.headline).foregroundStyle(CalmStyle.blue)
                            }
                        }
                        Button(running == kind ? "Running…" : "Run") { run(kind) }
                            .buttonStyle(CalmActionStyle(prominent: true))
                            .disabled(running != nil)
                        if let r = results[kind] {
                            ForEach(r.filter { !$0.passed }) { miss in
                                let c = EngineScorecard.cases.first { $0.id == miss.id }
                                Text("Missed: \u{201C}\(c?.said ?? miss.id)\u{201D} wanted \(c?.action ?? "") \(c?.drawer ?? ""), got \(miss.got)")
                                    .font(.caption).foregroundStyle(CalmStyle.secondary)
                            }
                        }
                    }
                    .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Engine scorecard").navigationBarTitleDisplayMode(.inline)
    }

    private func run(_ kind: EngineKind) {
        running = kind
        let engine = EngineRouter.engine()
        Task {
            var out: [EngineScorecard.Result] = []
            for c in EngineScorecard.cases {
                if let quick = SessionQuickCommands.parse(c.said, kids: EngineScorecard.kids, fromPerson: c.item.message.isPerson) {
                    out.append(EngineScorecard.check(c, quick)); continue
                }
                let request = EngineRouter.request(for: c.item, said: c.said, ownerName: "Pat", kids: EngineScorecard.kids, examples: [])
                do {
                    let answer = try await engine.interpret(request)
                    out.append(EngineScorecard.check(c, answer.command))
                } catch {
                    out.append(EngineScorecard.Result(id: c.id, passed: false, got: error.localizedDescription))
                }
            }
            results[kind] = out
            running = nil
        }
    }
}
