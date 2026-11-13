import Foundation

/// When an email arrived, as Mail shows it in a list: the time today, "Yesterday", the weekday this week, the month
/// and day this year, and the full date before that. Pure, so it is tested.
enum ReceivedDate {
    static func label(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            f.setLocalizedDateFormatFromTemplate("jmm")
            return f.string(from: date)
        }
        let startToday = calendar.startOfDay(for: now)
        let startThen = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startThen, to: startToday).day ?? 0
        if days == 1 { return "Yesterday" }
        if days > 1 && days < 7 {
            f.setLocalizedDateFormatFromTemplate("EEEE")
            return f.string(from: date)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return f.string(from: date)
        }
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f.string(from: date)
    }

    /// The full stamp for the preview sheet: "Thursday, Nov 12, 2026 at 8:02 AM".
    static func full(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEEEMMMdyjmm")
        return f.string(from: date)
    }
}
