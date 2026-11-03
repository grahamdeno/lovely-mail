import Foundation

/// A date (and maybe a time) found in an email, resolved to a real moment.
struct MailDate: Equatable, Identifiable {
    let start: Date
    let hasTime: Bool
    /// The words as written: "Nov 7", "this Sunday", "tomorrow".
    let phrase: String
    /// The sentence the date sits in.
    let sentence: String
    var id: String { "\(Int(start.timeIntervalSince1970))-\(hasTime)" }
}

/// Finds dates in mail and turns them into real moments, relative to when the mail was sent
/// ("Sunday" in a Saturday email is the next day). Pure, so it is tested with a fixed calendar and clock.
/// See docs/sprint4-design.md.
enum MailDates {
    /// Dates further out than this are ignored.
    static let horizon: TimeInterval = 120 * 86_400

    /// The dates in one email: subject plus the author's own words (no quoted replies), from the start of today
    /// to 120 days ahead, earliest first. Receipts name past days, so they yield nothing.
    static func extract(_ email: Email, now: Date, calendar: Calendar = .current) -> [MailDate] {
        let text = email.subject + "\n" + ReplySignals.authoredBody(email.body)
        guard !MailKind.isReceipt(text) else { return [] }
        return extract(text: text, sent: email.date, now: now, calendar: calendar)
    }

    static func extract(text: String, sent: Date, now: Date, calendar: Calendar = .current) -> [MailDate] {
        let earliest = calendar.startOfDay(for: now)
        let latest = now.addingTimeInterval(horizon)
        var found: [MailDate] = []
        for sentence in sentences(in: text) {
            let time = timeOfDay(in: sentence)
            for (phrase, day) in days(in: sentence, sent: sent, calendar: calendar) {
                var start = day
                if let time, let withTime = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) { start = withTime }
                guard start >= earliest, start <= latest else { continue }
                found.append(MailDate(start: start, hasTime: time != nil, phrase: phrase, sentence: sentence))
            }
        }
        var seen = Set<String>()
        return found.sorted { $0.start < $1.start }.filter { seen.insert($0.id).inserted }
    }

    // MARK: Sentences

    /// Lines, then sentences: a split happens after . ! or ? followed by a space and a capital letter, so
    /// "Nov. 7" and "9 p.m." stay whole.
    static func sentences(in text: String) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let chars = Array(line)
            var current = ""
            var i = 0
            while i < chars.count {
                current.append(chars[i])
                if ".!?".contains(chars[i]), i + 2 < chars.count, chars[i + 1] == " ", chars[i + 2].isUppercase {
                    out.append(current.trimmingCharacters(in: .whitespaces)); current = ""
                }
                i += 1
            }
            let last = current.trimmingCharacters(in: .whitespaces)
            if !last.isEmpty { out.append(last) }
        }
        return out.filter { !$0.isEmpty }
    }

    // MARK: Days

    private static let monthNames = ["Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
                                     "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12]
    private static let monthDay = try! NSRegularExpression(
        pattern: #"\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sept?(?:ember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#)
    private static let numeric = try! NSRegularExpression(pattern: #"(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?(?![\d/])"#)
    private static let weekday = try! NSRegularExpression(
        pattern: #"\b(?:(this|next)\s+)?(sun|mon|tues|wednes|thurs|fri|satur)day\b"#, options: .caseInsensitive)
    private static let relative = try! NSRegularExpression(pattern: #"\b(today|tonight|tomorrow)\b"#, options: .caseInsensitive)
    private static let weekdayNumbers = ["sun": 1, "mon": 2, "tues": 3, "wednes": 4, "thurs": 5, "fri": 6, "satur": 7]

    private static func days(in sentence: String, sent: Date, calendar: Calendar) -> [(phrase: String, day: Date)] {
        let ns = sentence as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let sentDay = calendar.startOfDay(for: sent)
        var out: [(phrase: String, day: Date)] = []

        for m in monthDay.matches(in: sentence, range: whole) {
            let month = monthNames[String(ns.substring(with: m.range(at: 1)).prefix(3))] ?? 0
            let day = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let year = m.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 3)))
            if let date = resolve(month: month, day: day, year: year, sentDay: sentDay, calendar: calendar) {
                out.append((phrase: ns.substring(with: m.range), day: date))
            }
        }
        for m in numeric.matches(in: sentence, range: whole) {
            let month = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let day = Int(ns.substring(with: m.range(at: 2))) ?? 0
            var year: Int?
            if m.range(at: 3).location != NSNotFound, let y = Int(ns.substring(with: m.range(at: 3))) { year = y < 100 ? 2000 + y : y }
            if let date = resolve(month: month, day: day, year: year, sentDay: sentDay, calendar: calendar) {
                out.append((phrase: ns.substring(with: m.range), day: date))
            }
        }
        for m in weekday.matches(in: sentence, range: whole) {
            let qualifier = m.range(at: 1).location == NSNotFound ? "" : ns.substring(with: m.range(at: 1)).lowercased()
            guard let target = weekdayNumbers[ns.substring(with: m.range(at: 2)).lowercased()] else { continue }
            let sentWeekday = calendar.component(.weekday, from: sentDay)
            var delta = (target - sentWeekday + 7) % 7
            if delta == 0 { delta = 7 }
            guard var date = calendar.date(byAdding: .day, value: delta, to: sentDay) else { continue }
            // "next Tuesday" written on a Monday means the Tuesday after this one.
            if qualifier == "next", calendar.isDate(date, equalTo: sentDay, toGranularity: .weekOfYear),
               let later = calendar.date(byAdding: .day, value: 7, to: date) { date = later }
            out.append((phrase: ns.substring(with: m.range), day: date))
        }
        for m in relative.matches(in: sentence, range: whole) {
            let word = ns.substring(with: m.range(at: 1)).lowercased()
            let offset = word == "tomorrow" ? 1 : 0
            if let date = calendar.date(byAdding: .day, value: offset, to: sentDay) { out.append((phrase: ns.substring(with: m.range), day: date)) }
        }
        return out
    }

    /// A real calendar day, or nil for 2/31. Without a year: the next one on or after the day it was sent.
    private static func resolve(month: Int, day: Int, year: Int?, sentDay: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        func make(_ y: Int) -> Date? {
            guard let date = calendar.date(from: DateComponents(year: y, month: month, day: day)) else { return nil }
            let back = calendar.dateComponents([.month, .day], from: date)
            return back.month == month && back.day == day ? date : nil
        }
        if let year { return make(year) }
        let sentYear = calendar.component(.year, from: sentDay)
        if let this = make(sentYear), this >= sentDay { return this }
        return make(sentYear + 1)
    }

    // MARK: Times

    private static let range = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*[-–]\s*(\d{1,2})(?::(\d{2}))?\s*([AaPp])\.?[Mm](?![A-Za-z])"#)
    private static let single = try! NSRegularExpression(pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*([AaPp])\.?[Mm](?![A-Za-z])"#)
    private static let noon = try! NSRegularExpression(pattern: #"\bnoon\b"#, options: .caseInsensitive)
    private static let twentyFour = try! NSRegularExpression(pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#)

    /// The first time of day in a sentence: "9:00 PM", "9pm", "6-8 PM" (start), "noon", "14:30".
    static func timeOfDay(in sentence: String) -> (hour: Int, minute: Int)? {
        let ns = sentence as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func int(_ m: NSTextCheckingResult, _ i: Int) -> Int? {
            m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i)))
        }
        func hour24(_ h: Int, pm: Bool) -> Int? { (1...12).contains(h) ? (h % 12) + (pm ? 12 : 0) : nil }

        if let m = range.firstMatch(in: sentence, range: whole), let h = int(m, 1) {
            let pm = ns.substring(with: m.range(at: 5)).lowercased() == "p"
            if let hour = hour24(h, pm: pm) { return (hour, int(m, 2) ?? 0) }
        }
        if let m = single.firstMatch(in: sentence, range: whole), let h = int(m, 1) {
            let pm = ns.substring(with: m.range(at: 3)).lowercased() == "p"
            if let hour = hour24(h, pm: pm) { return (hour, int(m, 2) ?? 0) }
        }
        if noon.firstMatch(in: sentence, range: whole) != nil { return (12, 0) }
        if let m = twentyFour.firstMatch(in: sentence, range: whole), let h = int(m, 1), let min = int(m, 2) { return (h, min) }
        return nil
    }
}
