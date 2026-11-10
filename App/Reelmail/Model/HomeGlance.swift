import Foundation

/// Day labels for Home ("Today 6 PM", "Tomorrow"). The At a glance cards were removed Nov 9 (owner: they repeated Home).
enum HomeGlance {
    /// "Today 6 PM", "Tomorrow", "Thu 6 PM", "Nov 20".
    static func dayLabel(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        var day: String
        if calendar.isDate(date, inSameDayAs: now) { day = "Today" }
        else if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: t) { day = "Tomorrow" }
        else if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { day = "Yesterday" }
        // A weekday name only for the days ahead; a past date reads as a date ("Oct 11"), never "Sun".
        else if date > now, date.timeIntervalSince(now) < 6 * 86_400 { f.dateFormat = "EEE"; day = f.string(from: date) }
        else { f.dateFormat = "MMM d"; day = f.string(from: date) }
        guard hasTime else { return day }
        f.dateFormat = calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        return day + " " + f.string(from: date)
    }
}
