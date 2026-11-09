import Foundation

/// "Add events from a photo": a picture of his work calendar becomes events on his Google Work calendar.
/// Everything here is pure (text in, events out) so it is tested; reading the photo and writing the calendar
/// happen on the phone in PhotoEventsView. Nothing is sent to a cloud engine: work calendars can hold sensitive detail.
struct PhotoEvent: Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    /// The reading looked doubtful (cut-off title, odd time): shown for a check.
    var unsure = false
}

/// One line of text read from the photo, with where it sat (0...1, top-left origin).
struct PhotoTextLine: Equatable, Sendable {
    var text: String
    var x: Double
    var y: Double
}

enum PhotoEvents {
    // MARK: Duplicates

    /// Same title (ignoring case, punctuation and filler words) and overlapping for at least half of the shorter one.
    static func isDuplicate(_ e: PhotoEvent, of existing: [(title: String, start: Date, end: Date)]) -> Bool {
        let key = normalized(e.title)
        guard !key.isEmpty else { return false }
        return existing.contains { other in
            let otherKey = normalized(other.title)
            guard !otherKey.isEmpty, otherKey == key || otherKey.contains(key) || key.contains(otherKey) else { return false }
            let overlap = min(e.end, other.end).timeIntervalSince(max(e.start, other.start))
            let shorter = max(60, min(e.end.timeIntervalSince(e.start), other.end.timeIntervalSince(other.start)))
            return overlap >= shorter / 2
        }
    }

    static let filler: Set<String> = ["meeting", "mtg", "sync", "call", "the", "a", "with", "and", "weekly", "daily"]

    static func normalized(_ title: String) -> String {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !filler.contains($0) }
            .joined(separator: " ")
    }

    // MARK: Reading text without a model

    /// Reads list-style calendars ("Monday, November 9" then "9:00 AM – 10:00 AM Sprint Review") and agenda screenshots.
    /// Used when Apple Intelligence is not available, and as a check on its answer.
    static func parse(_ lines: [PhotoTextLine], now: Date, calendar: Calendar = .current) -> [PhotoEvent] {
        var day: Date? = nil
        var out: [PhotoEvent] = []
        var pendingTitle: String? = nil
        let sorted = lines.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        for (i, line) in sorted.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            if let d = dayHeader(text, now: now, calendar: calendar) { day = d; pendingTitle = nil; continue }
            let base = day ?? calendar.startOfDay(for: now)
            if let (startMin, endMin, rest) = timeRange(text) {
                var title = rest
                if title.isEmpty { title = (i + 1 < sorted.count && timeRange(sorted[i + 1].text) == nil && dayHeader(sorted[i + 1].text, now: now, calendar: calendar) == nil) ? sorted[i + 1].text : (pendingTitle ?? "") }
                guard let start = calendar.date(byAdding: .minute, value: startMin, to: base),
                      let end = calendar.date(byAdding: .minute, value: max(endMin, startMin + 15), to: base) else { continue }
                let clean = title.trimmingCharacters(in: CharacterSet(charactersIn: " -–—·|"))
                out.append(PhotoEvent(title: clean.isEmpty ? "Untitled" : clean, start: start, end: end, unsure: clean.isEmpty || clean.count < 3))
                pendingTitle = nil
            } else if text.count > 2 {
                pendingTitle = text
            }
        }
        return out
    }

    /// "Monday, November 9", "Mon 11/9", "Tue Nov 10", "Wednesday".
    static func dayHeader(_ text: String, now: Date, calendar: Calendar = .current) -> Date? {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let short = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        guard let weekday = names.firstIndex(where: { t.hasPrefix($0) }) ?? short.firstIndex(where: { t.hasPrefix($0 + " ") || t.hasPrefix($0 + ",") || t == $0 }) else { return nil }
        guard t.count <= 30, timeRange(text) == nil else { return nil }
        // An explicit date wins; else the weekday in the current week.
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.isLenient = true
        let year = calendar.component(.year, from: now)
        let rest = text.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).dropFirst().joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        for format in ["MMMM d", "MMM d", "M/d"] {
            f.dateFormat = format + " yyyy"
            if !rest.isEmpty, let d = f.date(from: rest.replacingOccurrences(of: ",", with: "") + " \(year)") { return calendar.startOfDay(for: d) }
        }
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .first { calendar.component(.weekday, from: $0) == weekday + 1 }.map { calendar.startOfDay(for: $0) }
    }

    /// "9:00 AM – 10:30 AM Title", "9–10am Title", "13:00-14:00 Title". Minutes from midnight, and the rest of the line.
    static func timeRange(_ text: String) -> (Int, Int, String)? {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s*[-–—to]+\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]).lowercased() } }
        guard let h1 = group(1).flatMap(Int.init), let h2 = group(4).flatMap(Int.init), h1 <= 23, h2 <= 23 else { return nil }
        let m1 = group(2).flatMap(Int.init) ?? 0, m2 = group(5).flatMap(Int.init) ?? 0
        let p2 = group(6), p1 = group(3) ?? p2
        let borrowed = group(3) == nil && p2 != nil
        guard p1 != nil || group(2) != nil || group(5) != nil else { return nil }   // "3-4" alone is not a time
        func minutes(_ h: Int, _ m: Int, _ p: String?) -> Int {
            var hour = h
            if let p, p.hasPrefix("p"), hour < 12 { hour += 12 }
            if let p, p.hasPrefix("a"), hour == 12 { hour = 0 }
            return hour * 60 + m
        }
        var start = minutes(h1, m1, p1)
        var end = minutes(h2, m2, p2)
        if borrowed, start > end { start -= 12 * 60 }   // "11-1pm" is 11 AM to 1 PM
        if end <= start, p1 == nil, p2 == nil, h2 < 12 { end += 12 * 60 }
        if end <= start { end = start + 30 }
        let range = Range(m.range, in: text)!
        let rest = (String(text[..<range.lowerBound]) + " " + String(text[range.upperBound...])).trimmingCharacters(in: .whitespaces)
        return (start, end, rest)
    }

    /// "YYYY-MM-DD" and "HH:mm" from the model, in his time zone.
    static func date(_ day: String, _ time: String, calendar: Calendar = .current) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = time.isEmpty ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        return f.date(from: time.isEmpty ? day : day + " " + time)
    }
}
