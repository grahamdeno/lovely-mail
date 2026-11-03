import Foundation

/// "Coming up": mail with a real date ahead. Pure rules and labels, so they are tested with a fixed calendar.
enum ComingUp {
    /// Mail counts toward the Home row when its date is within this many days.
    static let weekDays = 7

    struct Entry: Identifiable, Equatable {
        let post: Post
        /// The earliest date in the mail that is still ahead.
        let date: MailDate
        var id: String { post.id }
    }

    /// One entry per message, earliest date first. Sections that are not about you doing something on a day
    /// (Reading, Updates, Notes to self) are left out.
    static func entries(posts: [Post], section: (Post) -> FeedSection, now: Date, calendar: Calendar = .current) -> [Entry] {
        posts.compactMap { post -> Entry? in
            guard ![.reading, .updates, .notes].contains(section(post)) else { return nil }
            guard !ConversationPresentation.isSensitive(post.email, summary: post.summary) else { return nil }
            guard let first = MailDates.extract(post.email, now: now, calendar: calendar).first else { return nil }
            return Entry(post: post, date: first)
        }
        .sorted { $0.date.start < $1.date.start }
    }

    /// Entries within the next 7 days.
    static func thisWeek(_ entries: [Entry], now: Date, calendar: Calendar = .current) -> [Entry] {
        let end = calendar.date(byAdding: .day, value: weekDays, to: calendar.startOfDay(for: now)) ?? now
        return entries.filter { $0.date.start < end }
    }

    enum Bucket: String, CaseIterable { case today = "Today", tomorrow = "Tomorrow", thisWeek = "This week", later = "Later" }

    static func bucket(_ date: Date, now: Date, calendar: Calendar = .current) -> Bucket {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return .today
        case 1: return .tomorrow
        case 2..<weekDays: return .thisWeek
        default: return .later
        }
    }

    static func grouped(_ entries: [Entry], now: Date, calendar: Calendar = .current) -> [(bucket: Bucket, entries: [Entry])] {
        Bucket.allCases.compactMap { bucket in
            let items = entries.filter { Self.bucket($0.date.start, now: now, calendar: calendar) == bucket }
            return items.isEmpty ? nil : (bucket, items)
        }
    }

    // MARK: Labels

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    /// "9 PM" or "9:30 AM".
    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a", calendar: calendar).string(from: date)
    }

    /// Short, for chips and rows: "Today 9 PM", "Tomorrow", "Sun 9 PM", "Nov 20".
    static func label(_ d: MailDate, now: Date, calendar: Calendar = .current) -> String {
        let time = d.hasTime ? " " + timeText(d.start, calendar: calendar) : ""
        switch bucket(d.start, now: now, calendar: calendar) {
        case .today: return "Today" + time
        case .tomorrow: return "Tomorrow" + time
        case .thisWeek: return formatter("EEE", calendar: calendar).string(from: d.start) + time
        case .later: return formatter("MMM d", calendar: calendar).string(from: d.start) + time
        }
    }

    /// Full, for the email screen: "Sun, Nov 8 · 9 PM".
    static func fullLabel(_ d: MailDate, calendar: Calendar = .current) -> String {
        let day = formatter("EEE, MMM d", calendar: calendar).string(from: d.start)
        return d.hasTime ? day + " \u{00B7} " + timeText(d.start, calendar: calendar) : day
    }

    /// The chip label for an organization: the soonest date within a week among its mail, or nil.
    static func chipLabel(for posts: [Post], in entries: [Entry], now: Date, calendar: Calendar = .current) -> String? {
        let ids = Set(posts.map(\.id))
        guard let soonest = thisWeek(entries, now: now, calendar: calendar).first(where: { ids.contains($0.post.id) }) else { return nil }
        return label(soonest.date, now: now, calendar: calendar)
    }
}

/// What goes into Apple's Add Event sheet. The sheet is Apple's; Lovely never reads the calendar.
struct CalendarDraft: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var notes: String

    static func make(email: Email, date: MailDate) -> CalendarDraft {
        var title = FallbackSummarizer.cleanSubject(email.subject, fallbackBody: email.body)
        if title.count > 60 { title = String(title.prefix(57)) + "…" }
        if title.isEmpty { title = "Event" }
        let end = date.hasTime ? date.start.addingTimeInterval(3600) : date.start
        return CalendarDraft(title: title, start: date.start, end: end, isAllDay: !date.hasTime,
                             location: firstAddress(in: ReplySignals.authoredBody(email.body)),
                             notes: "From \(email.from.name) in Lovely.")
    }

    /// The first street address the phone's data detector finds. Runs on the phone; nothing is fetched.
    static func firstAddress(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) else { return nil }
        let ns = text as NSString
        guard let match = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range)
    }
}
