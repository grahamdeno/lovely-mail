import SwiftUI

/// Notes to self as a text thread: his notes and messages on the right in blue, Lovely on the left in gray.
/// Tap a note to talk about it or act on it. Lovely's suggestions are buttons; nothing happens until he taps.
struct NotesThreadView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var thread: [NoteChatMessage] = []
    @State private var focusedID: String?
    @State private var thinking = false
    @State private var problem: String?
    @State private var resetCount = 0
    @State private var handoffPost: Post?
    /// Swipe left, like Messages, to slide the bubbles over and show each one's time.
    @State private var reveal: CGFloat = 0
    private static let revealWidth: CGFloat = 76

    private var account: String { store.account ?? "demo" }
    private var notes: [Post] { store.digest.notes.sorted { $0.email.date < $1.email.date } }
    private var focused: Post? { notes.first { $0.id == focusedID } ?? notes.last }

    private enum Entry: Identifiable {
        case note(Post), message(NoteChatMessage)
        var id: String { switch self { case .note(let p): "n-" + p.id; case .message(let m): "m-" + m.id } }
        var date: Date { switch self { case .note(let p): p.email.date; case .message(let m): m.date } }
    }

    var body: some View {
        let entries = (notes.map(Entry.note) + thread.map(Entry.message)).sorted { $0.date < $1.date }
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if entries.isEmpty {
                            Text("Email yourself a note and it shows up here. Then talk it through with Lovely.")
                                .font(.callout).foregroundStyle(CalmStyle.secondary).padding(.top, 20)
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index == 0 || !Calendar.current.isDate(entries[index - 1].date, inSameDayAs: entry.date) {
                                Text(NotesThreadView.dayHeader(entry.date)).font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
                                    .frame(maxWidth: .infinity).padding(.top, 6)
                            }
                            ZStack(alignment: .trailing) {
                                Group {
                                    switch entry {
                                    case .note(let post): noteBubble(post)
                                    case .message(let m): messageBubble(m)
                                    }
                                }
                                .offset(x: reveal)
                                // Revealed by the swipe: the time, and what it was (a note from Gmail, typed here, or which engine answered).
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption2.weight(.semibold))
                                    Text(caption(entry)).font(.caption2).lineLimit(2).multilineTextAlignment(.trailing)
                                }
                                .foregroundStyle(CalmStyle.secondary)
                                .frame(width: NotesThreadView.revealWidth - 6, alignment: .trailing)
                                .offset(x: NotesThreadView.revealWidth + reveal)
                                .opacity(Double(-reveal / NotesThreadView.revealWidth))
                            }
                            .id(entry.id)
                        }
                        if thinking { ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).id("thinking") }
                        if let problem { Text(problem).font(.caption).foregroundStyle(CalmStyle.secondary).id("problem") }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .clipped()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            reveal = max(-NotesThreadView.revealWidth, min(0, v.translation.width))
                        }
                        .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { reveal = 0 } }
                )
                .onAppear { if let last = entries.last { reader.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: thread.count) { _, _ in
                    if let last = (notes.map(Entry.note) + thread.map(Entry.message)).sorted(by: { $0.date < $1.date }).last {
                        withAnimation { reader.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            VStack(spacing: 8) {
                if let note = focused { noteActions(note) }
                SessionAskField(hint: "Ask about \(focused.map { "\u{201C}\(shortTitle($0))\u{201D}" } ?? "your notes"). Lovely answers on this iPhone.",
                                thinking: thinking, onFocus: { _ in }, onAsk: { send($0) })
                    .id(resetCount)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
            .background(CalmStyle.background)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
        .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
        .onAppear { thread = NoteThreadStore(account: account).messages }
        .sheet(item: $handoffPost) { HandToGrokSheet(post: $0) }
    }

    // MARK: Bubbles

    static func dayHeader(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func caption(_ entry: Entry) -> String {
        switch entry {
        case .note(let p): return "Emailed from " + (p.email.from.email.split(separator: "@").last.map(String.init) ?? "Gmail")
        case .message(let m): return m.role == .me ? "Typed here" : (m.engine ?? "Lovely")
        }
    }

    private func noteBubble(_ post: Post) -> some View {
        let selected = post.id == focused?.id
        let body = post.summary.blurb.isEmpty ? String(post.email.body.prefix(280)) : post.summary.blurb
        return VStack(alignment: .trailing, spacing: 4) {
            Button { focusedID = post.id } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if !post.email.subject.isEmpty { Text(post.email.subject).font(.subheadline.weight(.semibold)) }
                    if !body.isEmpty, body != post.email.subject { Text(body).font(.subheadline) }
                }
                .foregroundStyle(CalmStyle.onBlue)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(CalmStyle.onBlue.opacity(selected ? 0.9 : 0), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .contextMenu { Button("Open the email") { router.open(.email(post.id)) } }
            Text("Note · " + post.email.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(CalmStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 48)
        .accessibilityIdentifier("notes.note")
    }

    private func messageBubble(_ m: NoteChatMessage) -> some View {
        let mine = m.role == .me
        return VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            Text(m.text).font(.subheadline)
                .foregroundStyle(mine ? CalmStyle.onBlue : CalmStyle.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(mine ? CalmStyle.blue.opacity(0.85) : CalmStyle.bubble, in: RoundedRectangle(cornerRadius: 18))
                .textSelection(.enabled)
            if !mine, let post = notes.first(where: { $0.id == m.noteID }) { suggestion(m, post) }
            if !mine, let engine = m.engine { Text(engine).font(.caption2).foregroundStyle(CalmStyle.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(mine ? .leading : .trailing, 48)
    }

    /// Lovely's suggestion, as a button under its bubble.
    @ViewBuilder private func suggestion(_ m: NoteChatMessage, _ post: Post) -> some View {
        switch m.action {
        case "later":
            let option = laterOption(m.later)
            if let option { chip("Bring back \(option.title.lowercased())") { store.putOff(post, until: option.date) } }
        case "put_away", "archive": doneButton(post, compact: true)
        case "trash": chip("Move to Trash", rose: true) { store.sessionTrash(post) }
        case "handoff": chip("Hand to Grok") { handoffPost = post }
        default: EmptyView()
        }
    }

    // MARK: Actions for the selected note

    private func noteActions(_ note: Post) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if NotesPlaybook.looksLikeTest(subject: note.email.subject, body: note.email.body) {
                    chip("Test note · Trash", rose: true) { store.sessionTrash(note) }
                }
                doneButton(note, compact: true)
                if let tomorrow = laterOption("tomorrow") { chip("Bring back tomorrow") { store.putOff(note, until: tomorrow.date) } }
                if !NotesPlaybook.looksLikeTest(subject: note.email.subject, body: note.email.body) {
                    chip("Trash", rose: true) { store.sessionTrash(note) }
                }
                chip("Open") { router.open(.email(note.id)) }
            }
        }
    }

    private func doneButton(_ post: Post, compact: Bool) -> some View {
        SessionConfirmButton(title: "Done", previews: [ActionPreview(kind: .label, title: "Note done",
                                                                     lines: ["Labels it Notes in Gmail, marks it read and takes it out of your inbox.", "Nothing is deleted. You have 10 seconds to undo."])],
                             prominent: false, identifier: "notes.done") { approvals in
            store.fileNotes([post], confirmed: approvals[0])
            if focusedID == post.id { focusedID = nil }
        }
        .frame(maxWidth: compact ? 120 : .infinity)
    }

    private func chip(_ title: String, rose: Bool = false, action: @escaping () -> Void) -> some View {
        let tint = rose ? CalmStyle.roseInk : CalmStyle.blue
        return Button(action: action) {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 12).frame(minHeight: 36)
                .foregroundStyle(tint).background(tint.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func laterOption(_ when: String?) -> LaterSchedule.Option? {
        let options = LaterSchedule.options(now: Date())
        return options.first { $0.title.lowercased() == (when ?? "tomorrow").lowercased() } ?? options.first
    }

    private func shortTitle(_ p: Post) -> String {
        let t = p.email.subject.isEmpty ? String(p.email.body.prefix(30)) : p.email.subject
        return t.count > 30 ? String(t.prefix(28)) + "\u{2026}" : t
    }

    // MARK: Talking to the engine

    private func send(_ text: String) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, !thinking else { return }
        let note = focused
        let mine = NoteChatMessage(role: .me, text: said, date: Date(), noteID: note?.id)
        NoteThreadStore(account: account).append(mine)
        thread.append(mine)
        resetCount += 1
        problem = nil

        let kind: EngineKind = .apple
        let me = store.me.firstName == "You" ? "" : store.me.firstName
        let request = EngineRequest(system: NotesPlaybook.system(ownerName: me), compact: NotesPlaybook.compact(ownerName: me),
                                    user: NotesPlaybook.userMessage(notes: notes.map { ($0.id, $0.email.date, $0.email.subject, $0.email.body) },
                                                                    focusedID: note?.id, thread: thread, said: said))
        thinking = true
        Task {
            do {
                let answer = try await EngineRouter.engine().interpret(request)
                let c = answer.command
                let text = (c.reply ?? "").isEmpty ? (c.say ?? "") : (c.reply ?? "")
                let action = ["later", "put_away", "archive", "trash", "handoff"].contains(c.action) ? c.action : nil
                let reply = NoteChatMessage(role: .lovely, text: text.isEmpty ? "I'm not sure. Can you say more?" : text, date: Date(),
                                            noteID: note?.id, action: action, later: c.later, engine: kind.name)
                NoteThreadStore(account: account).append(reply)
                thread.append(reply)
            } catch {
                problem = "\(kind.name): \(error.localizedDescription)"
            }
            thinking = false
        }
    }
}
