import SwiftUI

/// "Did mail arrive?" answered from Gmail itself: the engine writes the search, Lovely runs it read-only on the phone
/// and shows the newest matches. The results are never sent to an engine, and health mail shows as a count only.
struct GmailSearchResults: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let query: String
    @State private var state: Phase = .searching

    enum Phase: Equatable {
        case searching
        case found(total: Int, more: Bool, shown: [MessageStub], hidden: Int)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(query, systemImage: "magnifyingglass").font(.caption.monospaced()).foregroundStyle(CalmStyle.secondary).lineLimit(2)
            switch state {
            case .searching:
                ProgressView("Searching your Gmail").font(.lovely(.subheadline))
            case .failed(let why):
                Text(why).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
            case .found(let total, let more, let shown, let hidden):
                Text(GmailSearchResults.headline(total: total, more: more, newest: shown.first?.date))
                    .font(.lovely(.headline))
                ForEach(shown, id: \.id) { m in
                    Button { router.open(.email(m.id)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.subject.isEmpty ? "(no subject)" : m.subject).font(.lovely(.subheadline)).lineLimit(1).foregroundStyle(CalmStyle.ink)
                            Text((m.fromName.isEmpty ? m.fromAddress : m.fromName) + " · " + m.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(CalmStyle.bubble, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if hidden > 0 { Text("\(hidden) more look like health mail and are not shown here.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary) }
            }
        }
        .task(id: query) { await run() }
        .accessibilityIdentifier("session.search.results")
    }

    static func headline(total: Int, more: Bool, newest: Date?) -> String {
        guard total > 0 else { return "Nothing in your Gmail matches." }
        let count = more ? "\(total)+" : "\(total)"
        let latest = newest.map { " The newest arrived " + $0.formatted(date: .abbreviated, time: .shortened) + "." } ?? ""
        return "Found \(count) email\(total == 1 && !more ? "" : "s")." + latest
    }

    private func run() async {
        guard store.mode == .gmail else { state = .failed("Connect Gmail to search it."); return }
        do {
            let list = try await store.gmail.listMessageIDs(query: query, limit: 20)
            var shown: [MessageStub] = [], hidden = 0
            for id in list.ids.prefix(8) where shown.count < 5 {
                let m = try await store.gmail.getMetadata(id: id)
                if HealthMail.isHealth(address: m.fromAddress, name: m.fromName, subject: m.subject) { hidden += 1 } else { shown.append(m) }
            }
            state = .found(total: list.ids.count, more: list.truncated, shown: shown, hidden: hidden)
        } catch {
            state = .failed("Gmail could not be searched right now. \(error.localizedDescription)")
        }
    }
}
