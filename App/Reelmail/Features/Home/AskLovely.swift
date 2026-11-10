import FoundationModels
import SwiftUI

/// Ask Lovely, a two-week experiment (owner, Nov 9: "intriguing, not sure how much I'd use it"). Counts asks on this
/// phone; after 14 days Home asks whether to keep it. Off removes the field.
struct AskLovelyUsage {
    static let enabledKey = "lovely.ask.enabled"
    static let countKey = "lovely.ask.count"
    static let sinceKey = "lovely.ask.since"
    static let decidedKey = "lovely.ask.decided"
    static let trialDays = 14
    var defaults: UserDefaults = .standard

    var count: Int { defaults.integer(forKey: Self.countKey) }
    /// When the trial started (set by `start()` when Home first shows the field; never written while drawing).
    var since: Date? { defaults.object(forKey: Self.sinceKey) as? Date }
    func start(now: Date = Date()) { if since == nil { defaults.set(now, forKey: Self.sinceKey) } }
    func recordAsk() { start(); defaults.set(count + 1, forKey: Self.countKey) }
    /// Time to ask whether to keep it.
    func trialOver(now: Date = Date()) -> Bool {
        guard let since, !defaults.bool(forKey: Self.decidedKey) else { return false }
        return now.timeIntervalSince(since) >= Double(Self.trialDays) * 86_400
    }
}

/// The slim field above the tabs on Home, with two suggested questions when there is room.
struct AskLovelyBar: View {
    @Environment(Router.self) private var router
    @AppStorage(AskLovelyUsage.enabledKey) private var enabled = true
    @AppStorage(AskLovelyUsage.decidedKey) private var decided = false
    var showSuggestions: Bool
    @State private var text = ""

    static let suggestions = ["What did school send this week?", "Who's waiting on me?"]

    var body: some View {
        if enabled {
            VStack(spacing: 6) {
                let usage = AskLovelyUsage()
                if usage.trialOver() {
                    HStack(spacing: 8) {
                        Text("You asked Lovely \(usage.count) time\(usage.count == 1 ? "" : "s") in two weeks. Keep it?")
                            .font(.caption).foregroundStyle(CalmStyle.secondary)
                        Spacer(minLength: 4)
                        Button("Keep") { decided = true }.font(.caption.weight(.semibold))
                        Button("Remove") { enabled = false; decided = true }.font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.roseInk)
                    }
                } else if showSuggestions {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Self.suggestions, id: \.self) { q in
                                Button(q) { ask(q) }
                                    .font(.caption).foregroundStyle(CalmStyle.blue)
                                    .padding(.horizontal, 10).frame(minHeight: 30)
                                    .background(CalmStyle.blue.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Ask Lovely about your mail", text: $text)
                        .submitLabel(.search).onSubmit { ask(text) }
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous).strokeBorder(CalmStyle.divider))
                        .accessibilityIdentifier("home.ask")
                    Button { ask(text) } label: {
                        Image(systemName: "arrow.up").font(.body.weight(.semibold)).foregroundStyle(CalmStyle.onBlue)
                            .frame(width: 44, height: 44).background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous))
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Ask Lovely")
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(CalmStyle.background)
            .onAppear { AskLovelyUsage().start() }
        }
    }

    private func ask(_ q: String) {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        AskLovelyUsage().recordAsk()
        text = ""
        router.open(.askLovely(question))
    }
}

/// Apple Intelligence's version of the search, when there is no Claude key.
@Generable
struct AppleMailQuestion {
    @Guide(description: "One Gmail search query using operators like from:, to:, subject:, newer_than:30d.")
    var query: String
    @Guide(description: "One short sentence for the owner about what you are looking for.")
    var say: String
}

/// Questions and answers about his mail: each question becomes a read-only Gmail search, shown as results he can open.
struct AskLovelyView: View {
    @Environment(FeedStore.self) private var store
    var firstQuestion: String = ""
    /// Set when opened from the Money, Energy or Kids bubble: the page's facts go along with every question.
    var topic: PageFacts.Topic? = nil
    @State private var turns: [Turn] = []
    @State private var text = ""
    @State private var working = false
    @FocusState private var typing: Bool

    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var question: String
        var answer: String = ""
        /// The Gmail search behind the answer, shown underneath as sources.
        var query: String?
        var problem: String?
        var engine: String = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if turns.isEmpty { starter }
                        ForEach(turns) { turn in
                            Text(turn.question).font(.body).foregroundStyle(CalmStyle.onBlue)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: 18))
                                .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 48)
                            VStack(alignment: .leading, spacing: 10) {
                                if !turn.answer.isEmpty {
                                    SelectableText(text: EmailPresentation.linked(turn.answer))
                                }
                                if let p = turn.problem { Text(p).font(.callout).foregroundStyle(CalmStyle.secondary) }
                                if turn.answer.isEmpty, turn.problem == nil {
                                    HStack(spacing: 8) { ProgressView(); Text("Thinking\u{2026}").font(.callout).foregroundStyle(CalmStyle.secondary) }
                                }
                                if let q = turn.query {
                                    Text("FROM YOUR MAIL").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                                        .padding(.top, 4)
                                    GmailSearchResults(query: q)
                                }
                                if !turn.engine.isEmpty {
                                    Text(turn.engine).font(.caption2).foregroundStyle(CalmStyle.secondary)
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                            .id(turn.id)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: turns.count) { _, _ in if let last = turns.last { withAnimation { reader.scrollTo(last.id, anchor: .bottom) } } }
            }
            HStack(spacing: 8) {
                TextField(turns.isEmpty ? "Ask anything" : "Ask a follow-up", text: $text, axis: .vertical)
                    .lineLimit(1...4).focused($typing).submitLabel(.send).onSubmit { send(text) }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous))
                    .accessibilityIdentifier("ask.field")
                Button { send(text) } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.semibold)).foregroundStyle(CalmStyle.onBlue)
                        .frame(width: 44, height: 44).background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous))
                }
                .disabled(working || text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle(topic.map { "Ask about \($0.title)" } ?? "Ask Lovely").navigationBarTitleDisplayMode(.inline)
        .task {
            if turns.isEmpty, !firstQuestion.trimmingCharacters(in: .whitespaces).isEmpty { send(firstQuestion, counted: true) }
            else if turns.isEmpty { typing = true }
        }
    }

    /// Before the first question: a line on what it can do, and the page's suggestions.
    private var starter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(topic == nil ? "Ask about your mail, or anything else. Answers from your mail show the emails underneath."
                              : "Ask about what's on your \(topic!.title) page, or anything around it.")
                .font(.callout).foregroundStyle(CalmStyle.secondary)
            WrapLayout(spacing: 8) {
                ForEach(topic?.suggestions ?? ["What did school send this week?", "Who's waiting on me?", "Which bills are due?"], id: \.self) { q in
                    Button { send(q) } label: {
                        Text(q).font(.subheadline).foregroundStyle(CalmStyle.blue)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func send(_ q: String, counted: Bool = false) {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !working else { return }
        if !counted { AskLovelyUsage().recordAsk() }
        text = ""
        let history = turns.filter { !$0.answer.isEmpty }.map { AskChatReader.Turn(question: $0.question, answer: $0.answer) }
        turns.append(Turn(question: question))
        let index = turns.count - 1
        working = true
        let facts = topic.map { store.pageFacts($0) } ?? []
        let owner = store.me.name == "You" ? "" : store.me.firstName
        let topicTitle = topic?.title
        Task {
            do {
                let a = try await Self.answer(question, history: history, topic: topicTitle, facts: facts, owner: owner, store: store)
                turns[index].answer = a.text; turns[index].query = a.query; turns[index].engine = a.engine
            } catch EngineError.unavailable {
                turns[index].problem = "Add a Claude key in Settings, AI, or turn on Apple Intelligence, to get answers here."
            } catch {
                turns[index].problem = "Lovely couldn't answer that just now. Check your connection and try again."
            }
            working = false
        }
    }

    /// Claude when there is a key (it can search his mail); otherwise Apple on the phone, which answers from the
    /// page facts and general knowledge, plus a mail search for questions about his mail.
    @MainActor static func answer(_ question: String, history: [AskChatReader.Turn], topic: String?, facts: [String],
                                  owner: String, store: FeedStore) async throws -> (text: String, query: String?, engine: String) {
        let today = Date().formatted(date: .complete, time: .omitted)
        if let key = EngineSettings.key(.claude) {
            let model = EngineSettings().claudeModel
            let system = AskChatReader.system(ownerName: owner, engineName: "Claude (\(model)) through Anthropic's API",
                                              today: today, topic: topic, facts: facts.map { Redactor.redact($0) })
            let gmail = store.gmail
            let a = try await AskChatReader.answer(question, history: history, system: system, model: model, key: key,
                                                   search: { query in await Self.searchLines(query, gmail: gmail) })
            return (a.text, a.query, "Claude")
        }
        guard ModelStatus.current.isAvailable else { throw EngineError.unavailable }
        let system = AskChatReader.system(ownerName: owner, engineName: "Apple Intelligence on this iPhone", today: today,
                                          topic: topic, facts: facts)
            + "\nYou cannot search his mail yourself here; Lovely shows matching emails under your answer when the question is about his mail."
        let session = LanguageModelSession(instructions: system)
        let prompt = (history.suffix(3).map { "Earlier he asked: \($0.question)\nYou said: \($0.answer)" } + [question]).joined(separator: "\n\n")
        let text = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
        var query: String?
        if topic == nil, let found = try? await search(for: question) { query = found.0 }
        return (text, query, "Apple Intelligence")
    }

    /// One line per message for the AI: sender, subject, date. Health mail is left out.
    nonisolated static func searchLines(_ query: String, gmail: any GmailInboxClient) async -> [String] {
        guard let list = try? await gmail.listMessageIDs(query: query, limit: 10) else { return [] }
        var out: [String] = []
        for id in list.ids {
            guard let m = try? await gmail.getMetadata(id: id),
                  !HealthMail.isHealth(address: m.fromAddress, name: m.fromName, subject: m.subject) else { continue }
            out.append("From \(m.fromName.isEmpty ? m.fromAddress : m.fromName), \(m.date.formatted(date: .abbreviated, time: .shortened)): \(m.subject)")
        }
        return out
    }

    static func search(for question: String) async throws -> (String, String) {
        let today = Date().formatted(.iso8601.year().month().day())
        if let key = EngineSettings.key(.claude) {
            return try await MailQuestionReader.query(question, today: today, model: EngineSettings().claudeModel, key: key)
        }
        guard ModelStatus.current.isAvailable else { throw EngineError.unavailable }
        let session = LanguageModelSession(instructions: MailQuestionReader.prompt(today: today))
        let answer = try await session.respond(to: question, generating: AppleMailQuestion.self, options: GenerationOptions(temperature: 0)).content
        let q = answer.query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { throw EngineError.badAnswer }
        return (q, answer.say)
    }
}
