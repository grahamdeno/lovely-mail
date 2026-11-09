import SwiftUI

/// Settings > Inbox session > Conversation engine. Apple only by default; Claude or Grok when the owner adds a key.
struct EngineSettingsView: View {
    @Environment(Router.self) private var router
    @State private var engine = EngineSettings().engine
    @State private var compare = EngineSettings().compare
    @State private var claudeKey = ""
    @State private var grokKey = ""
    @State private var claudeModel = EngineSettings().claudeModel
    @State private var grokModel = EngineSettings().grokModel
    @State private var hasClaude = EngineSettings.hasKey(.claude)
    @State private var hasGrok = EngineSettings.hasKey(.grok)
    @State private var examplesCleared = false
    @State private var details = OwnerDetails.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Who understands what you say in a session. Apple Intelligence does the routine work either way.")
                    .font(.callout).foregroundStyle(CalmStyle.secondary)

                Picker("Engine", selection: $engine) {
                    ForEach(EngineKind.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: engine) { _, new in EngineSettings().engine = new }
                .accessibilityIdentifier("engine.picker")

                Text(explanation).font(.callout)

                keyCard(.claude, key: $claudeKey, model: $claudeModel, has: $hasClaude)
                keyCard(.grok, key: $grokKey, model: $grokModel, has: $hasGrok)

                Toggle(isOn: $compare) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Compare Claude and Grok").font(.body)
                        Text("Both answer each request side by side and you pick one. Needs both keys.").font(.caption).foregroundStyle(CalmStyle.secondary)
                    }
                }
                .disabled(!(hasClaude && hasGrok))
                .onChange(of: compare) { _, new in EngineSettings().compare = new }
                .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))

                usageCard

                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR DETAILS FOR FORMS").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                    Text("Used only when Lovely fills a website form for you. Stays on this iPhone until a form needs it.")
                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                    detailField("Full name", $details.fullName, .name)
                    detailField("Email", $details.email, .emailAddress)
                    detailField("Phone", $details.phone, .telephoneNumber)
                    detailField("Address", $details.address, .fullStreetAddress)
                }
                .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                .onChange(of: details) { _, new in new.save() }

                VStack(alignment: .leading, spacing: 6) {
                    Text("WHAT IS SENT").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                    Text("With Claude or Grok on, Lovely sends the email's own words (no quoted history, codes or account numbers), its sender and subject, what you said, and Lovely's instructions. Health mail is never sent; Apple handles it on this iPhone. Keys stay in this iPhone's Keychain.")
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
        .onDisappear { EngineSettings().claudeModel = claudeModel; EngineSettings().grokModel = grokModel }
    }

    private func detailField(_ title: String, _ value: Binding<String>, _ type: UITextContentType) -> some View {
        TextField(title, text: value)
            .textContentType(type).autocorrectionDisabled()
            .padding(10).background(CalmStyle.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var explanation: String {
        switch engine {
        case .apple: return "Everything stays on this iPhone. Short commands work well; long replies and judgment calls are weaker."
        case .claude: return hasClaude ? "Claude understands your replies and drafts. Health mail still stays on this iPhone." : "Add a Claude key below to use Claude. Until then, Apple handles it."
        case .grok: return hasGrok ? "Grok understands your replies and drafts. Health mail still stays on this iPhone." : "Add a Grok key below to use Grok. Until then, Apple handles it."
        }
    }

    private func keyCard(_ kind: EngineKind, key: Binding<String>, model: Binding<String>, has: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.name).font(.headline)
                Spacer()
                Text(has.wrappedValue ? "Key saved" : "No key").font(.caption.weight(.semibold))
                    .foregroundStyle(has.wrappedValue ? CalmStyle.green : CalmStyle.secondary)
            }
            SecureField(kind == .claude ? "Anthropic API key" : "xAI API key", text: key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10).background(CalmStyle.background, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("engine.key.\(kind.rawValue)")
            HStack {
                Button("Save key") {
                    EngineSettings.setKey(key.wrappedValue, for: kind)
                    key.wrappedValue = ""
                    has.wrappedValue = EngineSettings.hasKey(kind)
                }
                .buttonStyle(CalmActionStyle(prominent: true)).disabled(key.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                if has.wrappedValue {
                    Button("Remove", role: .destructive) {
                        EngineSettings.setKey("", for: kind); has.wrappedValue = false
                        if kind == engine { engine = .apple }
                    }
                    .buttonStyle(CalmActionStyle())
                }
            }
            TextField("Model", text: model)
                .textInputAutocapitalization(.never).autocorrectionDisabled().font(.caption)
                .padding(8).background(CalmStyle.background, in: RoundedRectangle(cornerRadius: 8))
                .onSubmit {
                    if kind == .claude { EngineSettings().claudeModel = model.wrappedValue } else { EngineSettings().grokModel = model.wrappedValue }
                }
            Text("Model id. Leave it as is unless \(kind.name) renames its models.").font(.caption2).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var usageCard: some View {
        let week = EngineUsage().thisWeek()
        return VStack(alignment: .leading, spacing: 8) {
            Text("THIS WEEK").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            ForEach(EngineKind.allCases) { kind in
                let calls = week.calls[kind.rawValue] ?? 0
                let picks = week.picks[kind.rawValue] ?? 0
                HStack {
                    Text(kind == .apple ? "Apple" : kind.name)
                    Spacer()
                    Text("\(calls) calls" + (kind.isCloud ? String(format: " · about $%.2f", EngineUsage.estimatedCost(week, kind)) : "")
                         + (picks > 0 ? " · picked \(picks)" : ""))
                        .font(.callout).foregroundStyle(CalmStyle.secondary)
                }
            }
        }
        .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Testing tools: every enabled engine against the fictional scorecard sentences. Costs a few cloud calls per run.
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
                            .disabled(running != nil || !EngineSettings.hasKey(kind))
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
        let engine = EngineRouter.engine(kind)
        Task {
            var out: [EngineScorecard.Result] = []
            for c in EngineScorecard.cases {
                if let quick = SessionQuickCommands.parse(c.said, kids: EngineScorecard.kids, fromPerson: c.item.message.isPerson) {
                    out.append(EngineScorecard.check(c, quick)); continue
                }
                let request = EngineRouter.request(for: c.item, said: c.said, ownerName: "Pat", kids: EngineScorecard.kids, examples: [])
                do {
                    let answer = try await engine.interpret(request)
                    EngineUsage().recordCall(answer)
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
