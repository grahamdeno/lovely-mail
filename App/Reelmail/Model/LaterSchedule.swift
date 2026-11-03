import Foundation

/// "Later": put a message off until a time you pick. Local to this phone; Gmail is not changed.
/// Pure, so the choices are tested with a fixed calendar and clock.
enum LaterSchedule {
    struct Option: Equatable, Identifiable {
        let title: String
        let date: Date
        var id: String { title }
    }

    /// Up to three quick choices, nearest first.
    static func options(now: Date, calendar: Calendar = .current) -> [Option] {
        var out: [Option] = []
        let hour = calendar.component(.hour, from: now)
        if hour < 17, let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) {
            out.append(Option(title: "This evening", date: evening))
        }
        let startOfToday = calendar.startOfDay(for: now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
           let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) {
            out.append(Option(title: "Tomorrow", date: morning))
        }
        let weekday = calendar.component(.weekday, from: now)   // Sunday = 1 ... Saturday = 7
        if (2...5).contains(weekday),
           let saturday = calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 7), matchingPolicy: .nextTime) {
            out.append(Option(title: "This weekend", date: saturday))
        }
        if let monday = calendar.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, weekday: 2), matchingPolicy: .nextTime) {
            // On a Sunday night "tomorrow" is already Monday morning; do not offer the same time twice.
            if !out.contains(where: { $0.date == monday }) { out.append(Option(title: "Next week", date: monday)) }
        }
        return Array(out.prefix(3))
    }

    /// "tomorrow 8 AM", "today 6 PM", "Sat 9 AM", "Nov 9, 8 AM".
    static func label(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = calendar.component(.minute, from: date) == 0 ? date.formatted(.dateTime.hour()) : date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "today " + time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow " + time }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time }
        return date.formatted(.dateTime.month(.abbreviated).day()) + ", " + time
    }

    /// Hidden from Home while the time is in the future.
    static func isPending(_ until: Date, now: Date) -> Bool { until > now }

    /// Entries for messages that are gone or no longer unread are dropped.
    static func pruned(_ later: [String: Date], keeping unreadIDs: Set<String>) -> [String: Date] {
        later.filter { unreadIDs.contains($0.key) }
    }

    /// The earliest allowed custom time: one hour from now.
    static func earliestCustom(now: Date) -> Date { now.addingTimeInterval(3600) }
}
