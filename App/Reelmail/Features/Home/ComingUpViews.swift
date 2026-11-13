import EventKit
import EventKitUI
import SwiftUI

/// "Coming up · 2 this week ›": one quiet row that opens the list.
struct ComingUpRow: View {
    @Environment(Router.self) private var router
    let count: Int
    var body: some View {
        Button { router.open(.comingUp) } label: {
            HStack(spacing: 10) {
                Text("Coming up · \(count) this week").font(.lovely(.subheadline, .medium)).foregroundStyle(CalmStyle.ink)
                Spacer()
                Text("Dates in your mail").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                Image(systemName: "chevron.right").font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.secondary)
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Mail with a date ahead, grouped Today, Tomorrow, This week, Later.
struct ComingUpListView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let now = Date()
        let groups = ComingUp.grouped(store.comingUp, now: now)
        List {
            if groups.isEmpty {
                Text("No dates ahead in your mail.").font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
                    .listRowBackground(CalmStyle.background).listRowSeparator(.hidden)
            }
            ForEach(groups, id: \.bucket) { group in
                Section {
                    ForEach(group.entries) { entry in
                        Button { router.open(.email(entry.post.id)) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(entry.post.email.from.name).font(.lovely(.headline)).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(ComingUp.label(entry.date, now: now)).font(.lovely(.subheadline, .medium)).foregroundStyle(CalmStyle.blue)
                                }
                                Text(FallbackSummarizer.cleanSubject(entry.post.email.subject, fallbackBody: entry.post.email.body))
                                    .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .lifeListRow()
                    }
                } header: {
                    Text(group.bucket.rawValue.uppercased()).font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.secondary)
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Coming up").navigationBarTitleDisplayMode(.inline)
    }
}

/// On the email screen: the first date, with Add to Calendar and a menu for more.
struct EmailDateRow: View {
    let post: Post
    @State private var draft: CalendarDraft?

    var body: some View {
        let dates = MailDates.extract(post.email, now: Date())
        if let first = dates.first {
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(CalmStyle.blue)
                Text(ComingUp.fullLabel(first)).font(.lovely(.subheadline, .medium)).lineLimit(1)
                Spacer(minLength: 8)
                if dates.count > 1 {
                    Menu("+\(dates.count - 1) more") {
                        ForEach(dates.dropFirst()) { d in
                            Button(ComingUp.fullLabel(d)) { draft = CalendarDraft.make(email: post.email, date: d) }
                        }
                    }
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                }
                Button { draft = CalendarDraft.make(email: post.email, date: first) } label: { Label("Add to Calendar", systemImage: "plus") }
                    .buttonStyle(CalmActionStyle()).lineLimit(1)
            }
            .sheet(item: Binding(get: { draft.map(DraftBox.init) }, set: { draft = $0?.draft })) { box in
                CalendarEventSheet(draft: box.draft).ignoresSafeArea()
            }
        }
    }

    private struct DraftBox: Identifiable {
        let draft: CalendarDraft
        var id: String { "\(draft.start.timeIntervalSince1970)-\(draft.title)" }
    }
}

/// Apple's Add Event sheet. It runs outside the app, so Lovely never asks for or gets calendar access.
struct CalendarEventSheet: UIViewControllerRepresentable {
    let draft: CalendarDraft
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { dismiss() }
    }
}
