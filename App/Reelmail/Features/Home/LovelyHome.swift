import SwiftUI
import UIKit

/// Home 2 (owner, Nov 10, 2026): white space first, and the first thing to do is talk about your mail.
/// A greeting and one sentence with what matters (tappable), the Ask field in the middle with three questions under it,
/// and Ball 1 at the bottom: tap it or pull it up to go through your mail. Asking turns the page into a thread; Lovely's
/// answers swipe down into the ball when handled. Nothing scrolls until there is a conversation.
/// Settings > Look and feel > "Chat Home" off brings back the classic Home. Mockup: Design/mockups/home-2.html.
struct LovelyHome: View {
    static let settingKey = "lovely.home.chat"

    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var text = ""
    @FocusState private var typing: Bool
    @State private var turns: [Turn] = []
    @State private var working = false
    @State private var gelAwake = true
    @State private var gelSleep: Task<Void, Never>?
    @State private var ballPull: CGFloat = 0
    @State private var swiping: UUID?
    @State private var swipeY: CGFloat = 0
    @State private var ballCenter: CGPoint = .zero
    static let gel = GelPhysics()
    private var gel: GelPhysics { Self.gel }

    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var question: String
        var answer = ""
        var query: String?
        var problem: String?
        var engine = ""
        /// Answered on the phone: today's steps as buttons.
        var steps: [TodayStep]?
        var gone = false
    }

    var body: some View {
        let steps = store.todaySteps()
        let toGo = store.sessionCandidates.count
        let owner = store.me.name == "You" ? "" : store.me.firstName
        let line = HomeLine.make(steps: steps, toGoThrough: toGo, firstName: owner, hour: Calendar.current.component(.hour, from: Date()))
        let chatting = turns.contains { !$0.gone }
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                CalmStyle.page.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    topBar(chatting: chatting)
                    if chatting {
                        thread(steps: steps)
                        composer.padding(.bottom, typing ? 8 : 100)
                    } else {
                        Spacer(minLength: 8)
                        hero(line, steps: steps)
                        composer.padding(.top, 22)
                        if !typing { suggestions(line, steps: steps) }
                        Color.clear.frame(height: typing ? 10 : max(120, geo.size.height * 0.2))
                    }
                }
                if !typing { bottom(toGo: toGo) }
            }
        }
        .foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: chatting)
        .animation(.easeOut(duration: 0.2), value: typing)
        .onAppear {
            AskLovelyUsage().start()
            settleGel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { gel.kick(0.4, toward: -.pi / 2); settleGel() }
        }
        .onDisappear { gelSleep?.cancel() }
    }

    // MARK: Pieces

    private func topBar(chatting: Bool) -> some View {
        HStack {
            Text("lovely").font(.system(.title2, design: .serif).italic()).foregroundStyle(CalmStyle.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if chatting {
                Button("New") { withAnimation { turns = []; text = "" } }
                    .font(.subheadline.weight(.semibold)).accessibilityIdentifier("home2.new")
            }
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 6)
    }

    private func hero(_ line: HomeLine, steps: [TodayStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(line.greeting).font(.system(size: 34, weight: .heavy)).tracking(-0.6).lineLimit(2).minimumScaleFactor(0.7)
            Text(sentence(line))
                .font(.title3).foregroundStyle(CalmStyle.secondary)
                .tint(CalmStyle.ink)
                .environment(\.openURL, OpenURLAction { url in
                    follow(HomeLine.Link(rawValue: url.host() ?? ""), steps: steps)
                    return .handled
                })
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(line.plainSentence)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("home2.hero")
    }

    private func sentence(_ line: HomeLine) -> AttributedString {
        var out = AttributedString()
        for seg in line.sentence {
            var part = AttributedString(seg.text)
            if let link = seg.link, let url = URL(string: "lovely-home://\(link.rawValue)") {
                part.link = url
                part.foregroundColor = CalmStyle.ink
                part.underlineStyle = Text.LineStyle(pattern: .solid, color: link == .answer ? CalmStyle.rose : CalmStyle.blue)
            }
            out += part
        }
        return out
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask about your mail", text: $text)
                .font(.body).focused($typing).submitLabel(.send)
                .onSubmit { send(text) }
                .frame(minHeight: 46)
                .accessibilityIdentifier("home2.ask")
            Button { send(text) } label: {
                Image(systemName: working ? "ellipsis" : "arrow.up").font(.body.weight(.bold))
                    .frame(width: 40, height: 40).foregroundStyle(CalmStyle.onBlue)
                    .background(CalmStyle.blue, in: Circle())
            }
            .disabled(working || text.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Ask Lovely").accessibilityIdentifier("home2.ask.go")
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 5)
        .glassPane(corner: 26)
        .padding(.horizontal, 16)
    }

    private func suggestions(_ line: HomeLine, steps: [TodayStep]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(line.suggestions, id: \.self) { q in
                Button { send(q, steps: steps) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(CalmStyle.secondary.opacity(0.6))
                        Text(q).font(.body).foregroundStyle(CalmStyle.secondary)
                    }
                    .frame(minHeight: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32).padding(.top, 12)
        .accessibilityIdentifier("home2.suggestions")
    }

    // MARK: The thread

    private func thread(steps: [TodayStep]) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(turns.filter { !$0.gone }) { turn in
                        Text(turn.question).font(.body).foregroundStyle(CalmStyle.onBlue)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 56)
                        answerCard(turn)
                            .offset(y: swiping == turn.id ? swipeOffset : 0)
                            .scaleEffect(swiping == turn.id ? 1 - min(max(swipeY, 0) / 900, 0.12) : 1)
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.count) { _, _ in
                if let last = turns.last { withAnimation { reader.scrollTo(last.id, anchor: .top) } }
            }
        }
    }

    private var swipeOffset: CGFloat {
        let a = abs(swipeY), s: CGFloat = swipeY < 0 ? -1 : 1
        return s * (a <= 40 ? a : 40 + (a - 40) * 0.5)
    }

    private func answerCard(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // The card's top edge is its handle: pull it down into the ball when it's handled. (A drag anywhere would
            // fight the thread's scrolling.)
            HStack(spacing: 6) {
                Circle().fill(CalmStyle.rose).frame(width: 7, height: 7)
                Text("Lovely").font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
                Spacer()
                Text("Pull down when done").font(.caption2).foregroundStyle(CalmStyle.secondary.opacity(0.7))
                Capsule().fill(CalmStyle.divider).frame(width: 26, height: 4)
            }
            .frame(minHeight: 30).contentShape(Rectangle())
            .gesture(cardSwipe(turn))
            .accessibilityAction(named: "Done") { if let i = turns.firstIndex(where: { $0.id == turn.id }) { turns[i].gone = true } }
            if let steps = turn.steps {
                if steps.isEmpty {
                    Text("Nothing needs you right now. You're all caught up.").font(.body)
                } else {
                    ForEach(steps) { step in
                        Button { act(step) } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title).font(.body.weight(.semibold)).foregroundStyle(CalmStyle.ink)
                                    if !step.detail.isEmpty {
                                        Text(step.detail).font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
                            }
                            .padding(.vertical, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if step.id != steps.last?.id { Divider().overlay(CalmStyle.divider) }
                    }
                }
            } else {
                if !turn.answer.isEmpty { SelectableText(text: EmailPresentation.linked(turn.answer)) }
                if let p = turn.problem { Text(p).font(.callout).foregroundStyle(CalmStyle.secondary) }
                if turn.answer.isEmpty, turn.problem == nil {
                    HStack(spacing: 8) { ProgressView(); Text("Looking through your mail\u{2026}").font(.callout).foregroundStyle(CalmStyle.secondary) }
                }
                if let q = turn.query {
                    Text("FROM YOUR MAIL").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary).padding(.top, 4)
                    GmailSearchResults(query: q)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.page, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(CalmStyle.divider))
        .shadow(color: Color(hex: 0x25222A).opacity(0.08), radius: 14, y: 8)
    }

    /// Lovely's answers move like session pages: pulled down past the line, they drop into the ball.
    private func cardSwipe(_ turn: Turn) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { v in
                guard abs(v.translation.height) > abs(v.translation.width) else { return }
                swiping = turn.id
                swipeY = v.translation.height
                let p = Double(max(0, swipeY) / 150)
                gel.scaleTarget = 1 + min(p, 1.2) * 0.35
                gel.reachTarget = min(p, 1) * 0.8
                if ballCenter != .zero { gel.angleTarget = atan2(Double(v.location.y - ballCenter.y), Double(v.location.x - ballCenter.x)) }
                wakeGel()
            }
            .onEnded { _ in
                if swipeY >= 150 {
                    withAnimation(.easeIn(duration: 0.3)) { swipeY = 900 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        gel.scaleTarget = 1; gel.reachTarget = 0; gel.angleTarget = -.pi / 2
                        gel.kick(1, toward: -.pi / 2)
                        if let i = turns.firstIndex(where: { $0.id == turn.id }) { turns[i].gone = true }
                        swiping = nil; swipeY = 0
                        settleGel()
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { swipeY = 0 }
                    gel.scaleTarget = 1; gel.reachTarget = 0; gel.angleTarget = -.pi / 2
                    swiping = nil
                    settleGel()
                }
            }
    }

    // MARK: The bottom: People, the ball, ⋯

    private func bottom(toGo: Int) -> some View {
        ZStack(alignment: .bottom) {
            if ballPull > 8 {
                Text(ballPull > 90 ? (toGo > 0 ? "Let go to go through \(toGo)" : "Let go") : (toGo > 0 ? "Pull up to go through \(toGo)" : "Nothing to go through"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(CalmStyle.page, in: Capsule())
                    .shadow(color: Color(hex: 0x25222A).opacity(0.15), radius: 10, y: 4)
                    .padding(.bottom, 170)
                    .allowsHitTesting(false)
            }
            HStack {
                Button("People") { router.tab = .people }
                    .font(.body.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("home2.people")
                Spacer()
                moreMenu
            }
            .padding(.horizontal, 24).padding(.bottom, 18)
            .ignoresSafeArea(.container, edges: .bottom)

            GelBall(physics: gel, awake: gelAwake)
                .frame(width: 400, height: 400)
                .onGeometryChange(for: CGPoint.self) { CGPoint(x: $0.frame(in: .global).midX, y: $0.frame(in: .global).midY) } action: { ballCenter = $0 }
                .offset(y: 200 - 4)
                .allowsHitTesting(false)
                .ignoresSafeArea(.container, edges: .bottom)

            Color.clear.frame(width: 150, height: 84).contentShape(Rectangle())
                .gesture(ballGesture(toGo: toGo))
                .ignoresSafeArea(.container, edges: .bottom)
                .accessibilityElement()
                .accessibilityLabel(toGo > 0 ? "Go through your inbox, \(toGo) email\(toGo == 1 ? "" : "s")" : "Inbox, all caught up")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { startSession(toGo: toGo) }
                .accessibilityIdentifier("home2.ball")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button { router.open(.overview) } label: { Label("Everything", systemImage: "square.grid.2x2") }
            Button { router.open(.money) } label: { Label("Money", systemImage: "creditcard") }
            if !InsightSettings().load().kids.isEmpty {
                Button { router.open(.kids) } label: { Label("Kids", systemImage: "graduationcap") }
            }
            Button { router.open(.comingUp) } label: { Label("Coming up", systemImage: "calendar") }
            Button { router.open(.notes) } label: { Label("Notes to self", systemImage: "note.text") }
            Button { router.open(.later) } label: { Label("Later", systemImage: "clock") }
            Divider()
            Button { router.open(.settings) } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.bold)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("More").accessibilityIdentifier("home2.more")
    }

    /// Tap the ball or pull it up: the session rises out of it.
    private func ballGesture(toGo: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                ballPull = max(0, -v.translation.height)
                gel.scaleTarget = 1 + Double(min(ballPull / 200, 1)) * 0.35
                gel.reachTarget = Double(min(ballPull / 120, 1))
                gel.angleTarget = -.pi / 2
                wakeGel()
            }
            .onEnded { v in
                let pulled = -v.translation.height
                let tapped = abs(v.translation.height) < 8 && abs(v.translation.width) < 8
                withAnimation(.easeOut(duration: 0.15)) { ballPull = 0 }
                gel.reachTarget = 0
                if pulled > 90 || tapped { startSession(toGo: toGo) } else { gel.scaleTarget = 1; settleGel() }
            }
    }

    private func startSession(toGo: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        gel.scaleTarget = 1.4; gel.kick(0.9, toward: -.pi / 2); wakeGel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            gel.scaleTarget = 1; settleGel()
            if toGo > 0 { router.open(.session) }
            else if store.backlogCandidates.count > 0 { router.open(.backlog) }
        }
    }

    // MARK: Asking

    private func send(_ q: String, steps: [TodayStep]? = nil) {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !working else { return }
        let today = steps ?? store.todaySteps()
        text = ""
        typing = false
        // "Answer Sarah": straight to her email.
        if question.hasPrefix("Answer "), let step = today.first(where: { $0.kind == .answer && !$0.done }), let id = step.postID {
            router.open(.email(id)); return
        }
        AskLovelyUsage().recordAsk()
        if HomeLine.isNeedsMe(question) {
            withAnimation { turns.append(Turn(question: question, steps: today.filter { !$0.done })) }
            return
        }
        let history = turns.filter { !$0.answer.isEmpty }.map { AskChatReader.Turn(question: $0.question, answer: $0.answer) }
        withAnimation { turns.append(Turn(question: question)) }
        let id = turns.last!.id
        working = true
        let owner = store.me.name == "You" ? "" : store.me.firstName
        Task {
            do {
                let a = try await AskLovelyView.answer(question, history: history, topic: nil, facts: [], owner: owner, store: store)
                if let i = turns.firstIndex(where: { $0.id == id }) { turns[i].answer = a.text; turns[i].query = a.query; turns[i].engine = a.engine }
            } catch EngineError.unavailable {
                if let i = turns.firstIndex(where: { $0.id == id }) { turns[i].problem = "Add a Claude key in Settings, AI, or turn on Apple Intelligence, to get answers here." }
            } catch {
                if let i = turns.firstIndex(where: { $0.id == id }) { turns[i].problem = "Lovely couldn't answer that just now. Check your connection and try again." }
            }
            working = false
        }
    }

    /// A tapped word in the sentence.
    private func follow(_ link: HomeLine.Link?, steps: [TodayStep]) {
        switch link {
        case .answer:
            if let step = steps.first(where: { $0.kind == .answer && !$0.done }) { act(step) }
        case .bill:
            if let step = steps.first(where: { $0.kind == .bill && !$0.done }) { act(step) }
        case .session: startSession(toGo: store.sessionCandidates.count)
        case nil: break
        }
    }

    private func act(_ step: TodayStep) {
        switch step.kind {
        case .answer, .date:
            if let id = step.postID { router.open(.email(id)) } else { router.open(.session) }
        case .session: router.open(.session)
        case .bill:
            if let id = step.postID { router.open(.email(id)) } else { router.open(.money) }
        }
    }

    // MARK: The ball's life

    private func wakeGel() { gelAwake = true; gelSleep?.cancel(); gelSleep = nil }

    private func settleGel() {
        gelAwake = true
        gelSleep?.cancel()
        gelSleep = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                if swiping == nil, ballPull == 0, gel.isSettled { gelAwake = false; return }
            }
        }
    }
}

/// Settings > Look and feel: the chat Home, or the classic one.
struct ChatHomeToggle: View {
    @AppStorage(LovelyHome.settingKey) private var on = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Chat Home", isOn: $on).tint(CalmStyle.blue)
            Text(on ? "Home is a greeting, one line on what matters, and a place to ask about your mail. The ball takes you through it."
                    : "The classic Home with Today's steps and shortcuts.")
                .font(.caption).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("settings.chatHome")
    }
}
