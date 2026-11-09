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
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .background(CalmStyle.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(CalmStyle.divider))
                        .accessibilityIdentifier("home.ask")
                    Button { ask(text) } label: {
                        Image(systemName: "arrow.up").font(.body.weight(.semibold)).foregroundStyle(CalmStyle.onBlue)
                            .frame(width: 40, height: 40).background(CalmStyle.blue, in: Circle())
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
    let firstQuestion: String
    @State private var turns: [Turn] = []
    @State private var text = ""
    @State private var working = false

    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var question: String
        var query: String?
        var say: String = ""
        var problem: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(turns) { turn in
                            Text(turn.question).font(.body).foregroundStyle(CalmStyle.onBlue)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: 18))
                                .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 48)
                            VStack(alignment: .leading, spacing: 8) {
                                if !turn.say.isEmpty { Text(turn.say).font(.callout) }
                                if let q = turn.query { GmailSearchResults(query: q) }
                                if let p = turn.problem { Text(p).font(.callout).foregroundStyle(CalmStyle.secondary) }
                                if turn.query == nil, turn.problem == nil { ProgressView() }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                            .id(turn.id)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: turns.count) { _, _ in if let last = turns.last { withAnimation { reader.scrollTo(last.id, anchor: .bottom) } } }
            }
            HStack(spacing: 8) {
                TextField("Ask a follow-up", text: $text).submitLabel(.search).onSubmit { send(text) }
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(CalmStyle.card, in: Capsule())
                Button { send(text) } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.semibold)).foregroundStyle(CalmStyle.onBlue)
                        .frame(width: 40, height: 40).background(CalmStyle.blue, in: Circle())
                }
                .disabled(working || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Ask Lovely").navigationBarTitleDisplayMode(.inline)
        .task { if turns.isEmpty { send(firstQuestion, counted: true) } }
    }

    private func send(_ q: String, counted: Bool = false) {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !working else { return }
        if !counted { AskLovelyUsage().recordAsk() }
        text = ""
        // A follow-up carries the earlier question so "and last month?" makes sense.
        let context = turns.last.map { "Earlier question: \($0.question)\nNow: \(question)" } ?? question
        turns.append(Turn(question: question))
        let index = turns.count - 1
        working = true
        Task {
            do {
                let (query, say) = try await Self.search(for: context)
                turns[index].query = query; turns[index].say = say
            } catch {
                turns[index].problem = "Lovely could not work out a search for that. Try naming who or what, like \u{201C}mail from Gunner's school this week\u{201D}."
            }
            working = false
        }
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
