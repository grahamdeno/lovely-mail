import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Home 2 (owner, Nov 10, 2026): white space first, and the first thing to do is talk about your mail.
/// A greeting and one sentence with what matters (tappable), the Ask field in the middle with three questions under it,
/// and Ball 1 at the bottom: tap it or pull it up to go through your mail. Asking turns the page into a thread; Lovely's
/// answers swipe down into the ball when handled. Nothing scrolls until there is a conversation.
/// Settings > Look and feel > "Chat Home" off brings back the classic Home. Mockup: Design/mockups/home-2.html.
struct LovelyHome: View {
    static let settingKey = "lovely.home.chat"

    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var shareText: ShareText?
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
    /// A photo or file added to the next question; its words are read on the phone.
    @State private var attachment: Attachment?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var picked: PhotosPickerItem?
    /// The field's height changed in this run loop: a tap arriving now is ignored (owner, Nov 11: no early sends).
    @State private var heightChanging = false
    /// How far the black Swipe to start sorting knob has been dragged.
    @State private var knob: CGFloat = 0

    struct Attachment: Equatable {
        var kind: String           // "photo" or "file"
        var name: String
        var image: UIImage?
        var text: String?
        var reading = true
    }
    static let gel = GelPhysics()
    private var gel: GelPhysics { Self.gel }

    struct Turn: Identifiable, Equatable {
        var id = UUID()
        var question: String
        var answer = ""
        var query: String?
        var problem: String?
        var engine = ""
        /// Answered on the phone: today's steps as buttons.
        var steps: [TodayStep]?
        /// The photo he attached, shown with his words.
        var image: UIImage?
        var fileName: String?
        /// Lovely's model can't do this (it needs the web): the task for Grok.
        var handoff: String?
        /// True only after Grok Bot's webhook answered 200.
        var sentToGrok = false
        /// The one line under Send to Grok after a try (accepted, or why the share sheet opened).
        var grokNote: String?
        var sending = false
        /// Grok's emailed report, shown under the question it answers.
        var report: String?
        var gone = false
    }

    var body: some View {
        let steps = store.todaySteps()
        let toGo = store.sessionCandidates.count
        let owner = store.me.name == "You" ? "" : store.me.firstName
        let line = HomeLine.make(steps: steps, toGoThrough: toGo, firstName: owner, hour: Calendar.current.component(.hour, from: Date()))
        let chatting = turns.contains { !$0.gone }
        // The LifeOS look (owner, Nov 12, 2026): greige ground, light cards, black squares. One way in to sorting: the
        // black bar above the field.
        ZStack(alignment: .bottom) {
            CalmStyle.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                topBar(chatting: chatting)
                if chatting {
                    thread(steps: steps)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            hero(line, steps: steps).padding(.top, 14)
                            suggestions(line, steps: steps).padding(.top, 18)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                if !typing { sortBar(toGo: toGo).padding(.horizontal, 20).padding(.bottom, 12) }
                composer.padding(.bottom, 8)
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
        .task {
            while !Task.isCancelled {
                await checkGrokReports()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                if let image { Task { await attach(image: image, kind: "photo", name: "Photo") } }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await attach(image: image, kind: "photo", name: "Photo")
                }
            }
        }
        .sheet(item: $shareText) { item in ActivityView(text: item.text).ignoresSafeArea().presentationDetents([.medium, .large]) }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText]) { result in
            if case .success(let url) = result { Task { await attach(file: url) } }
        }
    }

    // MARK: Pieces

    private func topBar(chatting: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(store.mode == .gmail ? Color(hex: 0x5FB84A) : CalmStyle.secondary).frame(width: 7, height: 7)
                Text(store.mode == .gmail ? "Inbox synced" : "Demo mail").font(.lovely(.footnote)).foregroundStyle(CalmStyle.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if chatting {
                Button { withAnimation { turns = []; text = "" } } label: {
                    Image(systemName: "plus").font(.lovely(.body, .semibold))
                }
                .buttonStyle(LifeSquareStyle(dark: false))
                .accessibilityLabel("New chat").accessibilityIdentifier("home2.new")
            }
            Button { router.tab = .people } label: { Image(systemName: "person.2").font(.lovely(.body, .semibold)) }
                .buttonStyle(LifeSquareStyle(dark: false))
                .accessibilityLabel("People").accessibilityIdentifier("home2.people")
            moreMenu
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            // Neon's glowing stripe under the top bar.
            if ThemeState.neon {
                Rectangle().fill(CalmStyle.gel).frame(height: 2)
                    .shadow(color: Color(hex: 0x9D4EDD).opacity(0.8), radius: 6)
                    .accessibilityHidden(true)
            }
        }
    }

    private func hero(_ line: HomeLine, steps: [TodayStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(line.greeting).font(.lovely(size: 32, weight: .semibold)).tracking(-0.8).lineLimit(2).minimumScaleFactor(0.7)
            Text(sentence(line))
                .font(.lovely(size: 18)).foregroundStyle(CalmStyle.ink).lineSpacing(3)
                .tint(CalmStyle.ink)
                .environment(\.openURL, OpenURLAction { url in
                    follow(HomeLine.Link(rawValue: url.host() ?? ""), steps: steps)
                    return .handled
                })
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(line.plainSentence)
        }
        .padding(.horizontal, 22)
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

    /// Grok's field, steady (owner, Nov 11, 2026): + and send sit on one fixed row and never move while he types; the
    /// words grow upward above it, photo or not. No layout switch, no animation that moves Send, and only the arrow sends.
    /// LifeOS look: three separate pieces, a light square, the field card, a black square.
    private var composer: some View {
        let canSend = HomeComposer.shouldSend(.arrowTap, text: text, hasAttachment: attachment != nil,
                                              busy: working || attachment?.reading == true, heightChanging: false)
        return VStack(alignment: .leading, spacing: 8) {
            if let a = attachment { attachmentChip(a).padding(10).lifeCard(corner: 18) }
            HStack(alignment: .bottom, spacing: 10) {
                addButton
                field
                    .padding(.horizontal, 12)
                    .frame(minHeight: 56)
                    .lifeCard(corner: 18)
                sendButton(canSend)
            }
        }
        .padding(.horizontal, 20)
        .transaction { $0.animation = nil }
    }

    /// Return makes a new line; it never sends.
    private var field: some View {
        TextField("Ask about your mail\u{2026}", text: $text, axis: .vertical)
            .font(.lovely(.body)).lineLimit(1...8).focused($typing)
            .padding(.vertical, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                heightChanging = true
                DispatchQueue.main.async { heightChanging = false }
            }
            .accessibilityIdentifier("home2.ask")
    }

    private var addButton: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
            }
            Button { showLibrary = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
            Button { showFiles = true } label: { Label("Choose File", systemImage: "folder") }
        } label: {
            Image(systemName: "paperclip").font(.lovely(.body, .semibold)).foregroundStyle(CalmStyle.ink)
                .frame(width: 56, height: 56)
                .lifeCard(corner: 18)
        }
        .accessibilityLabel("Add a photo or file").accessibilityIdentifier("home2.add")
    }

    private func sendButton(_ enabled: Bool) -> some View {
        Button {
            guard HomeComposer.shouldSend(.arrowTap, text: text, hasAttachment: attachment != nil,
                                          busy: working || attachment?.reading == true, heightChanging: heightChanging) else { return }
            send(text)
        } label: {
            Image(systemName: working ? "ellipsis" : "arrow.up").font(.lovely(.body, .bold))
                .frame(width: 56, height: 56).foregroundStyle(CalmStyle.onBlue)
                .lifeBlack(corner: 18)
        }
        .disabled(!enabled).opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("Ask Lovely").accessibilityIdentifier("home2.ask.go")
    }

    private func attachmentChip(_ a: Attachment) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = a.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.text").font(.lovely(.title3)).foregroundStyle(CalmStyle.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(CalmStyle.secondary.opacity(0.12))
                }
            }
            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.lovely(.subheadline, .semibold)).lineLimit(1)
                Text(a.reading ? "Reading on this iPhone\u{2026}" : HomeAttachment.summary(kind: a.kind, readText: a.text))
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            Spacer(minLength: 4)
            Button { attachment = nil } label: {
                Image(systemName: "xmark").font(.lovely(.caption, .bold)).foregroundStyle(CalmStyle.secondary)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .accessibilityLabel("Remove attachment")
        }
        .padding(.horizontal, 4).padding(.top, 2)
    }

    // MARK: Attachments: read on the phone

    private func attach(image: UIImage, kind: String, name: String) async {
        attachment = Attachment(kind: kind, name: name, image: image)
        let upright = PhotoEventsView.upright(image)
        var words = ""
        if let cg = upright.cgImage { words = await PhotoEventsView.recognize(cg).map(\.text).joined(separator: "\n") }
        if attachment?.image === image { attachment?.text = words; attachment?.reading = false }
        typing = true
    }

    private func attach(file url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.lastPathComponent
        if let image = UIImage(data: data) { await attach(image: image, kind: "photo", name: name); return }
        attachment = Attachment(kind: "file", name: name, image: nil)
        var words = ""
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(data: data) { words = pdf.string ?? "" }
        else { words = String(data: data, encoding: .utf8) ?? "" }
        if attachment?.name == name { attachment?.text = words; attachment?.reading = false }
        typing = true
    }

    private func suggestions(_ line: HomeLine, steps: [TodayStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(line.suggestions, id: \.self) { q in
                Button { send(q, steps: steps) } label: {
                    LifeRow(icon: "bubble.left", title: q, trailing: "chevron.right")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .accessibilityIdentifier("home2.suggestions")
    }

    /// The one way in to sorting (owner, Nov 12, 2026): a black bar; slide the knob right, or tap it.
    private func sortBar(toGo: Int) -> some View {
        let title = toGo > 0 ? "Swipe to sort \(toGo)" : (store.backlogCandidates.count > 0 ? "Swipe to go through older mail" : "All caught up")
        return GeometryReader { geo in
            let travel = max(0, geo.size.width - 68)
            ZStack(alignment: .leading) {
                Text(title).font(.lovely(size: 17, weight: .medium)).foregroundStyle(CalmStyle.onBlue)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 76)
                    .opacity(1 - Double(min(1, knob / max(1, travel))) * 0.8)
                Image(systemName: "arrow.right").font(.lovely(.body, .bold)).foregroundStyle(CalmStyle.onBlue)
                    .frame(width: 56, height: 52)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .offset(x: 6 + knob)
                    .gesture(DragGesture(minimumDistance: 4)
                        .onChanged { v in knob = min(travel, max(0, v.translation.width)) }
                        .onEnded { _ in
                            if knob > travel * 0.7 {
                                withAnimation(.easeOut(duration: 0.15)) { knob = travel }
                                startSession(toGo: toGo)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { knob = 0 }
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { knob = 0 }
                            }
                        })
            }
            .frame(width: geo.size.width, height: 64)
            .lifeBlack(corner: 20)
            .contentShape(Rectangle())
            .onTapGesture { startSession(toGo: toGo) }
        }
        .frame(height: 64)
        .accessibilityElement()
        .accessibilityLabel(toGo > 0 ? "Sort your inbox, \(toGo) email\(toGo == 1 ? "" : "s")" : "Inbox, all caught up")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { startSession(toGo: toGo) }
        .accessibilityIdentifier("home2.ball")
    }

    // MARK: The thread

    private func thread(steps: [TodayStep]) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(turns.filter { !$0.gone }) { turn in
                        VStack(alignment: .trailing, spacing: 6) {
                            if let image = turn.image {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else if let name = turn.fileName {
                                Label(name, systemImage: "doc.text").font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.secondary)
                            }
                            Text(turn.question).font(.lovely(.body)).foregroundStyle(CalmStyle.ink)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .lifeCard(corner: 22)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 56)
                        answerCard(turn)
                            .offset(y: swiping == turn.id ? swipeOffset : 0)
                            .scaleEffect(swiping == turn.id ? 1 - min(max(swipeY, 0) / 900, 0.12) : 1)
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 16)
                Color.clear.frame(height: 1).id("home2.end")
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // The newest message always sits just above the field (and the keyboard): on a new question, an answer
            // arriving, or the keyboard coming up.
            .onChange(of: threadShape) { _, _ in toEnd(reader) }
            .onChange(of: typing) { _, now in if now { toEnd(reader, after: 0.3) } }
        }
    }

    /// Changes when a turn is added or an answer or report arrives; never on a keystroke.
    private var threadShape: [String] {
        turns.filter { !$0.gone }.map { "\($0.id)|\($0.answer.count)|\($0.problem != nil)|\($0.report != nil)|\($0.sentToGrok)|\($0.steps?.count ?? -1)" }
    }

    private func toEnd(_ reader: ScrollViewProxy, after delay: Double = 0.05) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.25)) { reader.scrollTo("home2.end", anchor: .bottom) }
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
            if let steps = turn.steps {
                if steps.isEmpty {
                    Text("Nothing needs you right now. You're all caught up.").font(.lovely(.body))
                } else {
                    ForEach(steps) { step in
                        Button { act(step) } label: {
                            LifeRow(icon: "tray", title: step.title, detail: step.detail.isEmpty ? nil : step.detail, trailing: "chevron.right")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                if let task = turn.handoff { handoffBox(turn, task: task) }
                if let report = turn.report {
                    Text("GROK'S REPORT").font(.lovely(.caption2, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary).padding(.top, 2)
                    SelectableText(text: EmailPresentation.linked(report))
                }
                if !turn.answer.isEmpty { SelectableText(text: EmailPresentation.linked(turn.answer)) }
                if let p = turn.problem { Text(p).font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary) }
                if turn.answer.isEmpty, turn.problem == nil, turn.handoff == nil {
                    HStack(spacing: 8) { ProgressView(); Text("Looking through your mail\u{2026}").font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary) }
                }
                if let q = turn.query {
                    Text("FROM YOUR MAIL").font(.lovely(.caption2, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary).padding(.top, 4)
                    GmailSearchResults(query: q)
                }
            }
        }
        .font(.lovely(.body))
        .padding(.horizontal, 6).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.lovely(.subheadline, .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(CalmStyle.page, in: Capsule())
                    .shadow(color: Color(hex: 0x25222A).opacity(0.15), radius: 10, y: 4)
                    .padding(.bottom, 170)
                    .allowsHitTesting(false)
            }
            HStack {
                Button("People") { router.tab = .people }
                    .font(.lovely(.body, .semibold)).frame(minWidth: 44, minHeight: 44)
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
            Button { router.open(.grokReports) } label: { Label("Grok reports", systemImage: "sparkles") }
            Divider()
            Button { router.open(.settings) } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis").font(.lovely(.body, .bold)).foregroundStyle(CalmStyle.onBlue)
                .frame(width: 52, height: 52).lifeBlack(corner: 16)
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
        let typed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = attachment
        guard !working, !typed.isEmpty || file != nil, file?.reading != true else { return }
        let question = typed.isEmpty ? HomeAttachment.defaultQuestion : typed
        let prompt = file.map { HomeAttachment.prompt(question: typed, kind: $0.kind, readText: $0.text) } ?? question
        let today = steps ?? store.todaySteps()
        text = ""
        attachment = nil
        // "Answer Sarah": straight to her email.
        if file == nil, question.hasPrefix("Answer "), let step = today.first(where: { $0.kind == .answer && !$0.done }), let id = step.postID {
            typing = false; router.open(.email(id)); return
        }
        AskLovelyUsage().recordAsk()
        if file == nil, HomeLine.isNeedsMe(question) {
            withAnimation { turns.append(Turn(question: question, steps: today.filter { !$0.done })) }
            return
        }
        // "Ask Grok to …": straight to Grok, no engine.
        if file == nil, let task = GrokHandoff.explicitTask(question) {
            withAnimation { turns.append(Turn(question: question, handoff: task)) }
            return
        }
        let history = turns.filter { !$0.answer.isEmpty }.map { AskPrompt.Turn(question: $0.question, answer: $0.answer) }
        withAnimation { turns.append(Turn(question: question, image: file?.image, fileName: file?.image == nil ? file?.name : nil)) }
        let id = turns.last!.id
        working = true
        let owner = store.me.name == "You" ? "" : store.me.firstName
        Task {
            do {
                let a = try await AskLovelyView.answer(prompt, rule: GrokHandoff.engineRule, history: history, topic: nil, facts: [],
                                                       owner: owner, store: store)
                let parsed = GrokHandoff.parse(a.text)
                if let i = turns.firstIndex(where: { $0.id == id }) {
                    turns[i].answer = parsed.rest; turns[i].handoff = parsed.task; turns[i].query = a.query; turns[i].engine = a.engine
                }
            } catch {
                // Apple can't do it on the phone: say so, and offer Hand to Grok with his own words (owner, Nov 11, 2026).
                if let i = turns.firstIndex(where: { $0.id == id }) {
                    turns[i].problem = (error as? EngineError) == .unavailable ? AskLovelyView.unavailableLine : AskLovelyView.failedLine
                    if file == nil { turns[i].handoff = question }
                }
            }
            working = false
        }
    }

    // MARK: Hand to Grok

    /// Three states, in order (owner, Nov 11, 2026): Send to Grok; Grok Bot has it (only after a 200); the report.
    /// The first Send also sets up the Gmail filter that files Grok's reports; its line is shown above the button.
    @ViewBuilder private func handoffBox(_ turn: Turn, task: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task).font(.lovely(.body, .semibold))
            if turn.report != nil {
                EmptyView()
            } else if turn.sentToGrok {
                Text(GrokSendResult.accepted.note).font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
            } else {
                if let note = turn.grokNote { Text(note).font(.lovely(.callout)).foregroundStyle(CalmStyle.roseInk) }
                if let me = store.grokReportAddress, store.actions != nil, !store.grokReportsFiled {
                    let preview = GrokHandoff.filterPreview(owner: me)
                    Text(preview.lines.first ?? "").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                    SessionConfirmButton(title: turn.sending ? "Sending\u{2026}" : "Send to Grok", previews: [preview], enabled: !turn.sending,
                                         identifier: "home2.grok") { approvals in
                        store.setUpGrokReports(confirmed: approvals[0])
                        deliver(turn, task: task)
                    }
                } else {
                    Button(turn.sending ? "Sending\u{2026}" : "Send to Grok") { deliver(turn, task: task) }
                        .buttonStyle(SessionButtonStyle()).disabled(turn.sending).accessibilityIdentifier("home2.grok")
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// One tap: POST to the Grok Bot routine's webhook. Only a 200 counts as sent. Otherwise the share sheet opens
    /// (and only then is the prompt copied), and the card says why.
    private func deliver(_ turn: Turn, task: String) {
        guard let i = turns.firstIndex(where: { $0.id == turn.id }), !turns[i].sending else { return }
        turns[i].sending = true
        // A question asked on Home isn't one email, so Lovely adds no mail facts; health mail never goes either way.
        let prompt = GrokHandoff.prompt(task: task, facts: [], reportTo: store.grokReportAddress ?? "my email address")
        let id = turn.id, question = turn.question
        Task {
            let result = await GrokWebhook.send(task: task, prompt: prompt)
            guard let j = turns.firstIndex(where: { $0.id == id }) else { return }
            turns[j].sending = false
            if result.accepted {
                turns[j].sentToGrok = true
                turns[j].grokNote = nil
                GrokHandoffLog().add(.init(id: id, question: question, task: task, title: GrokHandoff.shortTitle(task), sentAt: Date(), report: nil))
            } else {
                turns[j].grokNote = result.note
                UIPasteboard.general.string = prompt
                shareText = ShareText(text: prompt)
            }
        }
    }

    /// Looks for Grok's emailed reports and puts each under the question it answers. Runs when Home opens and every
    /// minute while it stays open and something is waiting.
    private func checkGrokReports() async {
        let log = GrokHandoffLog()
        let waiting = log.waiting
        // Reports that came back for questions no longer on screen come back with their question.
        for item in log.items where item.report != nil && !turns.contains(where: { $0.id == item.id }) && item.sentAt > Date().addingTimeInterval(-86_400) {
            turns.append(Turn(id: item.id, question: item.question, handoff: item.task, sentToGrok: true, report: item.report))
        }
        guard !waiting.isEmpty, store.mode == .gmail else { return }
        guard let list = try? await store.gmail.listMessageIDs(query: GrokHandoff.searchQuery + " newer_than:14d", limit: 20) else { return }
        for id in list.ids.prefix(20) {
            guard let meta = try? await store.gmail.getMetadata(id: id),
                  let item = waiting.first(where: { GrokHandoff.isReport(subject: meta.subject, title: $0.title) }),
                  let mail = try? await store.gmail.getMessage(id: id, account: store.account) else { continue }
            let body = mail.body.trimmingCharacters(in: .whitespacesAndNewlines)
            log.setReport(item.id, body)
            if let k = turns.firstIndex(where: { $0.id == item.id }) {
                turns[k].report = body
            } else {
                turns.append(Turn(id: item.id, question: item.question, handoff: item.task, sentToGrok: true, report: body))
            }
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
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("settings.chatHome")
    }
}

struct ShareText: Identifiable {
    let id = UUID()
    let text: String
}

/// The share sheet, for handing a task to Grok Bot (pick Grok Bot, then a chat).
struct ActivityView: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Grok's reports, filed under Lovely/Grok reports by the filter Hand to Grok set up.
struct GrokReportsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What Grok did for you. Each report is emailed by Grok, labeled and kept out of your inbox.")
                    .font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
                GmailSearchResults(query: GrokHandoff.searchQuery)
            }
            .padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Grok reports").navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings > AI: Grok Bot's webhook, copied once from the bot's routine. Both values live in the Keychain.
struct GrokHandoffSetting: View {
    @State private var url = ""
    @State private var auth = ""
    @State private var saved = GrokWebhook.isSaved
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Send to Grok").font(.lovely(.headline))
            Text("When Lovely can't do something (anything on the web), one tap sends the task to your Grok Bot routine. Its report comes back by email, filed under Grok reports and shown under your question. No xAI key.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            SecureField(saved ? "Webhook URL (saved)" : "Webhook URL", text: $url)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(CalmStyle.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("settings.grokWebhook")
            SecureField(saved ? "Authorization header (saved)" : "Authorization header", text: $auth)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(CalmStyle.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("settings.grokAuth")
            HStack {
                Button("Save") { GrokWebhook.save(url: url, authorization: auth); url = ""; auth = ""; saved = GrokWebhook.isSaved }
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if saved { Button("Remove", role: .destructive) { GrokWebhook.save(url: "", authorization: ""); saved = false } }
            }
            .font(.lovely(.subheadline, .semibold))
            Text(saved ? "Saved on this iPhone. Send to Grok posts to it; only a 200 from Grok Bot counts as sent."
                       : "Copy both from your Grok Bot routine's webhook trigger. Until then, Send to Grok opens the share sheet instead.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
