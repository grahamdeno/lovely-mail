import SwiftUI

/// Goes through today's mail one card at a time. Chat is available only when the owner switches it on in Testing tools.
struct WalkthroughView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var index = 0
    @State private var skipped: Set<String> = []
    @State private var sentence = ""
    @State private var preview: ChatPreview?
    @State private var message: String?

    struct ChatPreview { var intent: ChatIntent; var senders: [String]; var note: String }

    private var cards: [Post] {
        let d = store.digest
        var seen = Set<String>()
        return (d.waiting + d.todo).filter { $0.email.isUnread && seen.insert($0.id).inserted }
    }

    var body: some View {
        let list = cards.filter { !skipped.contains($0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let post = list.first {
                    Text("\(list.count) left").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                    card(post)
                } else {
                    Text("That is everything for now.").font(.lovely(.title3, .semibold))
                    Text("Nothing else needs you today.").font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
                }
                if LearnedRuleStore().chatEnabled { chat }
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Walk through").navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(post.email.from.name).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
            Text(post.summary.headline).font(.lovely(.title3, .semibold))
            Text(post.summary.blurb).font(.lovely(.body))
            HStack(spacing: 8) {
                Button { Task { await store.markDone(post) } } label: { Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle(prominent: true))
                Button { store.putOff(post, until: tomorrowMorning()) } label: { Label("Later", systemImage: "clock").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
            }
            HStack(spacing: 8) {
                Button { router.open(.email(post.id)) } label: { Label("Open", systemImage: "envelope.open").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
                Button { skipped.insert(post.id) } label: { Label("Skip", systemImage: "forward").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHAT (TESTING)").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            TextField("For example: stop showing mail from Acme", text: $sentence).textFieldStyle(.roundedBorder)
                .onSubmit { interpret() }
            Button("Preview") { interpret() }.disabled(sentence.isEmpty)
            if let p = preview {
                Text("\(p.intent.action == .filtered ? "Hide" : p.intent.action == .reading ? "Move to Reading" : "Keep in Home"): \(p.senders.joined(separator: ", "))")
                    .font(.lovely(.subheadline))
                Button("Apply this rule") { apply(p) }.buttonStyle(CalmActionStyle(prominent: true))
            }
            if let message { Text(message).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary) }
        }
        .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func interpret() {
        preview = nil; message = nil
        guard let intent = ChatInterpreter.intent(sentence) else {
            message = "I can hide a sender, move one to Reading, or keep one in Home. Try: stop showing mail from Acme."
            return
        }
        let senders = ChatInterpreter.senders(matching: intent.term, in: store.posts)
        guard !senders.isEmpty else { message = "No sender matching \"\(intent.term)\" in your loaded mail."; return }
        preview = ChatPreview(intent: intent, senders: senders, note: sentence)
    }

    private func apply(_ p: ChatPreview) {
        let rule = LearnedRule(id: UUID().uuidString, matches: p.senders, action: p.intent.action, source: .chat, created: Date(), note: p.note)
        message = store.applyLearned(rule) ? "Done. Settings, Testing tools can remove every rule made in chat." : "That could not be saved."
        preview = nil; sentence = ""
    }

    private func tomorrowMorning() -> Date {
        let cal = Calendar.current
        return cal.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86_400)
    }
}
