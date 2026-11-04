import Foundation

/// When the brief arrives. Pure.
/// Default 9:30 on weekdays and 10:00 on weekends. After enough days of use it moves to
/// the median first-open or Done time minus 15 minutes, never before 7:00 or after 11:00.
/// A time the owner sets by hand always wins.
enum BriefTiming {
    static let weekdayDefault = 570
    static let weekendDefault = 600
    static let earliest = 420
    static let latest = 660
    static let leadMinutes = 15
    static let minimumSamples = 5

    static func defaultMinutes(on day: Date, calendar: Calendar = .current) -> Int {
        calendar.isDateInWeekend(day) ? weekendDefault : weekdayDefault
    }

    static func learned(from samples: [Int]) -> Int? {
        guard samples.count >= minimumSamples else { return nil }
        let sorted = samples.sorted()
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        return min(latest, max(earliest, median - leadMinutes))
    }

    /// Manual time, else learned (weekday and weekend kept apart), else the default.
    static func minutes(on day: Date, manual: Int?, weekdaySamples: [Int], weekendSamples: [Int], calendar: Calendar = .current) -> Int {
        if let manual { return manual }
        let weekend = calendar.isDateInWeekend(day)
        return learned(from: weekend ? weekendSamples : weekdaySamples) ?? defaultMinutes(on: day, calendar: calendar)
    }

    /// The next brief time after `now`, looking up to three days ahead because the time can differ by day.
    static func nextFire(after now: Date, calendar: Calendar = .current, minutesFor: (Date) -> Int) -> Date {
        let start = calendar.startOfDay(for: now)
        for offset in 0...3 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let fire = calendar.date(byAdding: .minute, value: minutesFor(day), to: day) else { continue }
            if fire > now { return fire }
        }
        return now.addingTimeInterval(86_400)
    }
}

/// The minutes after midnight of the first time Lovely was opened each day, and of each Done tap. Kept on this phone.
struct InteractionLog {
    static let weekdayKey = "lovely.interaction.weekday"
    static let weekendKey = "lovely.interaction.weekend"
    static let lastOpenDayKey = "lovely.interaction.lastOpenDay"
    static let keep = 60

    var defaults: UserDefaults = .standard
    var calendar: Calendar = .current

    var weekday: [Int] { defaults.array(forKey: Self.weekdayKey) as? [Int] ?? [] }
    var weekend: [Int] { defaults.array(forKey: Self.weekendKey) as? [Int] ?? [] }

    /// Records the first open of a day. Later opens the same day are ignored.
    func recordOpen(at now: Date = Date()) {
        let day = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        guard defaults.integer(forKey: Self.lastOpenDayKey) != day else { return }
        defaults.set(day, forKey: Self.lastOpenDayKey)
        record(now)
    }

    /// Records a Done tap.
    func recordDone(at now: Date = Date()) { record(now) }

    private func record(_ now: Date) {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        // Late-night and small-hours use says nothing about when a morning note is useful.
        guard minute >= 5 * 60, minute <= 14 * 60 else { return }
        let key = calendar.isDateInWeekend(now) ? Self.weekendKey : Self.weekdayKey
        var list = defaults.array(forKey: key) as? [Int] ?? []
        list.append(minute)
        defaults.set(Array(list.suffix(Self.keep)), forKey: key)
    }

    func clear() {
        [Self.weekdayKey, Self.weekendKey, Self.lastOpenDayKey].forEach { defaults.removeObject(forKey: $0) }
    }
}
