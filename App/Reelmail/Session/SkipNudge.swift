import Foundation

// Skipped three times (owner, Nov 16, 2026; design canvas screen 5c). When an email has been skipped in three
// sessions, the card says so in the big-fact slot, with one field to ask for help (typed or spoken), dates to hide it
// until, and Keep showing it. What it says depends on what kind of email it is. Hiding is Lovely-only (the Later list);
// Gmail is not changed. Nothing happens because of skips without his tap. Pure apart from save/load, so it is tested.

/// How many sessions each email was skipped in, and per sender, saved per account.
struct SkipMemory: Equatable, Codable, Sendable {
    struct Record: Equatable, Codable, Sendable {
        var count: Int
        var lastSession: String
        var last: Date
        /// The count when he last said Keep showing it (0 = never): Lovely asks again three skips later.
        var askedAt: Int
    }

    private(set) var messages: [String: Record] = [:]
    /// Skips per sender, kept from the start so later sorting can learn from them. Not acted on yet.
    private(set) var senders: [String: Int] = [:]

    static let threshold = 3

    static func key(account: String) -> String { "lovely.session.skips." + account.lowercased() }

    static func load(account: String, defaults: UserDefaults = .standard) -> SkipMemory {
        guard let data = defaults.data(forKey: key(account: account)),
              let memory = try? JSONDecoder().decode(SkipMemory.self, from: data) else { return SkipMemory() }
        return memory
    }

    func save(account: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(account: account)) }
    }

    func count(_ id: String) -> Int { messages[id]?.count ?? 0 }

    /// Ask at three skips, and three more after each Keep showing it.
    func shouldAsk(_ id: String) -> Bool {
        guard let r = messages[id] else { return false }
        return r.count >= r.askedAt + Self.threshold
    }

    /// Counts at most once per session, so going round the skipped ones at the end of a session counts once.
    mutating func recordSkip(_ id: String, sender: String, session: String, now: Date) {
        var r = messages[id] ?? Record(count: 0, lastSession: "", last: now, askedAt: 0)
        guard r.lastSession != session else { return }
        r.count += 1; r.lastSession = session; r.last = now
        messages[id] = r
        let s = TrashMemory.normalized(sender)
        if s.contains("@") { senders[s, default: 0] += 1 }
    }

    /// Undo of a skip made in this session.
    mutating func undoSkip(_ id: String, sender: String, session: String) {
        guard var r = messages[id], r.lastSession == session, r.count > 0 else { return }
        r.count -= 1; r.lastSession = ""
        if r.count == 0 { messages[id] = nil } else { messages[id] = r }
        let s = TrashMemory.normalized(sender)
        if let n = senders[s] { senders[s] = n > 1 ? n - 1 : nil }
    }

    mutating func keepShowing(_ id: String) {
        guard var r = messages[id] else { return }
        r.askedAt = r.count
        messages[id] = r
    }

    /// Hidden, put away or gone: its count no longer matters.
    mutating func forget(_ id: String) { messages[id] = nil }

    /// Drops emails no longer in the inbox (a new reply is a new email, so it starts again at zero).
    mutating func prune(keeping ids: Set<String>) {
        messages = messages.filter { ids.contains($0.key) }
    }
}

/// What the skipped-three-times card says and offers.
struct SkipNudge: Equatable {
    enum Kind: Equatable { case person, bill, dated, newsletter, health, plain }

    struct Option: Equatable, Identifiable {
        let title: String
        let date: Date
        /// From the email itself (shown in rose).
        var fromEmail = false
        var id: String { title }
    }

    var kind: Kind
    var title: String
    var line: String
    /// The field's placeholder; nil for health mail (no field: Lovely doesn't read health mail to help with it).
    var placeholder: String?
    var options: [Option]
    /// Newsletters: offer a rule for the sender (the More sheet, behind its preview).
    var offersRule: Bool { kind == .newsletter }

    static func make(_ m: SessionMessage, count: Int, newsletter: Bool, hero: SessionHero, dates: [MailDate],
                     now: Date, calendar: Calendar = .current) -> SkipNudge {
        let title = "Skipped \(count) times"
        let upcoming = dates.first { $0.start > now }
        let kind: Kind
        if m.isHealth { kind = .health }
        else if m.isPerson && (m.ask != nil || m.section == .waiting) { kind = .person }
        else if !m.isHealth && SessionHero.amount(in: m.subject + "\n" + m.text) != nil { kind = .bill }
        else if newsletter { kind = .newsletter }
        else if upcoming != nil { kind = .dated }
        else { kind = .plain }

        let line: String
        let placeholder: String?
        switch kind {
        case .person:
            line = "\(SessionHero.firstName(m.fromName)) is waiting. Want help replying, or should it wait?"
            placeholder = "Help me reply\u{2026}"
        case .bill:
            line = "Want help with it, or should it wait until closer to the due date?"
            placeholder = "Help me with it\u{2026}"
        case .dated:
            line = "Want help with it, or should it wait until closer to the day?"
            placeholder = "Help me with it\u{2026}"
        case .newsletter:
            line = "Want mail like this put away for you from now on?"
            placeholder = "Help me with it\u{2026}"
        case .health:
            line = "Should it wait for a better day?"
            placeholder = nil
        case .plain:
            line = "Want help with it, or should it wait for a better day?"
            placeholder = "Help me with it\u{2026}"
        }
        return SkipNudge(kind: kind, title: title, line: line, placeholder: placeholder,
                         options: options(now: now, deadline: m.isHealth ? nil : upcoming?.start, bill: kind == .bill, calendar: calendar))
    }

    /// Tomorrow, the weekend (or next week), and the day before a date in the email when that is further out.
    static func options(now: Date, deadline: Date?, bill: Bool, calendar: Calendar = .current) -> [Option] {
        var out: [Option] = []
        let today = calendar.startOfDay(for: now)
        if let t = calendar.date(byAdding: .day, value: 1, to: today), let tomorrow = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: t) {
            out.append(Option(title: "Tomorrow", date: tomorrow))
        }
        let weekday = calendar.component(.weekday, from: now)   // Sunday = 1 ... Saturday = 7
        if (2...5).contains(weekday),
           let saturday = calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 7), matchingPolicy: .nextTime) {
            out.append(Option(title: "Saturday", date: saturday))
        } else if let monday = calendar.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, weekday: 2), matchingPolicy: .nextTime),
                  !out.contains(where: { $0.date == monday }) {
            out.append(Option(title: "Monday", date: monday))
        }
        if let deadline,
           let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: deadline)),
           let at = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: dayBefore),
           at > (out.map(\.date).max() ?? now) {
            out.append(Option(title: shortDay(at, calendar: calendar) + (bill ? " \u{00B7} before it's due" : " \u{00B7} the day before"),
                              date: at, fromEmail: true))
        }
        return out
    }

    static func shortDay(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}

/// "After Thanksgiving", "next week", "Friday", "in two weeks", "December 3": when to bring an email back, from what he
/// said or typed. Morning of that day. Nil when it isn't a time (then it goes to Ask Lovely as words).
enum SkipDateParser {
    static func parse(_ said: String, now: Date, calendar: Calendar = .current) -> Date? {
        let s = " " + said.lowercased().replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression) + " "
        let today = calendar.startOfDay(for: now)
        func morning(_ day: Date, hour: Int = 8) -> Date? { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: day)) }
        func days(_ n: Int) -> Date? { calendar.date(byAdding: .day, value: n, to: today).flatMap { morning($0) } }
        func has(_ w: String) -> Bool { s.contains(" " + w + " ") }

        guard isWhen(s) else { return nil }

        // Holidays (US).
        if s.contains("thanksgiving") {
            guard let thursday = thanksgiving(after: now, calendar: calendar) else { return nil }
            let offset = s.contains("before thanksgiving") ? -2 : 4   // Tuesday before, or the Monday after
            return calendar.date(byAdding: .day, value: offset, to: thursday).flatMap { morning($0) }
        }
        if s.contains("christmas") {
            let year = calendar.component(.year, from: now)
            var c = DateComponents(year: year, month: 12, day: s.contains("before christmas") ? 22 : 26)
            if let d = calendar.date(from: c), d <= now { c.year = year + 1 }
            return calendar.date(from: c).flatMap { morning($0) }
        }
        if s.contains("new year") {
            let year = calendar.component(.year, from: now) + 1
            return calendar.date(from: DateComponents(year: year, month: 1, day: 2)).flatMap { morning($0) }
        }

        if has("tomorrow") { return days(1) }
        if has("tonight") || s.contains("this evening") {
            if let e = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now), e > now { return e }
        }
        if s.contains("weekend") {
            return calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 7), matchingPolicy: .nextTime)
        }
        if s.contains("next week") {
            return calendar.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, weekday: 2), matchingPolicy: .nextTime)
        }
        if s.contains("next month") {
            guard let m = calendar.date(byAdding: .month, value: 1, to: today) else { return nil }
            let c = calendar.dateComponents([.year, .month], from: m)
            return calendar.date(from: DateComponents(year: c.year, month: c.month, day: 1)).flatMap { morning($0) }
        }
        // "in 3 days", "in two weeks", "a week", "a couple of days"
        let numbers = ["a": 1, "one": 1, "two": 2, "couple": 2, "three": 3, "few": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "ten": 10]
        if let r = s.range(of: #"\b(\d+|a|one|two|three|four|five|six|seven|ten|couple|few)( of)? (days?|weeks?)\b"#, options: .regularExpression) {
            let parts = s[r].split(separator: " ").map(String.init)
            let n = Int(parts[0]) ?? numbers[parts[0]] ?? 1
            let unit = parts.last ?? "days"
            return days(unit.hasPrefix("week") ? n * 7 : n)
        }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (i, name) in names.enumerated() where has(name) {
            return calendar.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, weekday: i + 1), matchingPolicy: .nextTime)
        }
        // A written date: "December 3", "12/3".
        if let d = MailDates.extract(text: said, sent: now, now: now).first(where: { $0.start > now }) {
            return morning(d.start)
        }
        return nil
    }

    /// Only when what he said is about when: "tell her I'll do it Friday" is a reply, not a date to hide it until.
    static func isWhen(_ padded: String) -> Bool {
        let reply = "tell reply say ask text email write answer let send draft sign pay".split(separator: " ").map(String.init)
        let words = padded.split(separator: " ").map(String.init)
        if words.contains(where: reply.contains) { return false }
        let when = ["remind", "later", "until", "till", "after", "before", "next", "wait", "hide", "bring", "back", "snooze",
                    "tomorrow", "tonight", "weekend", "in"]
        return words.count <= 5 || words.contains(where: when.contains)
    }

    /// The fourth Thursday of November, this year or next if it has passed.
    static func thanksgiving(after now: Date, calendar: Calendar = .current) -> Date? {
        let year = calendar.component(.year, from: now)
        for y in [year, year + 1] {
            var c = DateComponents(year: y, month: 11, weekday: 5, weekdayOrdinal: 4)
            c.hour = 0
            if let d = calendar.date(from: c), calendar.startOfDay(for: d) >= calendar.startOfDay(for: now) { return d }
        }
        return nil
    }
}
