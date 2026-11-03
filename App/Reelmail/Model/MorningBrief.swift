import Foundation

/// The text of the morning notification. Pure, so it is tested without a phone.
/// Counts only by default; names appear only when the owner turns on "Show names in the brief".
/// See docs/sprint4-design.md.
struct MorningBrief: Equatable {
    var title: String
    var body: String

    static let maxParts = 3
    static let subjectLimit = 24

    /// Nil when there is nothing to say, so quiet mornings send nothing.
    /// - waiting: mail waiting on you. todo: To do (mail back from Later is already first in it).
    /// - promises: open "You said you would" items. today: Coming up entries dated today.
    static func make(waiting: [Post], todo: Int, promises: Int, today: [ComingUp.Entry], backFromLater: Int,
                     showNames: Bool, calendar: Calendar = .current) -> MorningBrief? {
        var parts: [String] = []
        if !waiting.isEmpty { parts.append(showNames ? waitingNames(waiting) : "\(waiting.count) waiting on you") }
        if promises > 0 { parts.append(promises == 1 ? "1 thing you said you would do" : "\(promises) things you said you would do") }
        if todo > 0 { parts.append("\(todo) to do") }
        if !today.isEmpty { parts.append(showNames ? todayNames(today, calendar: calendar) : "\(today.count) today") }
        if backFromLater > 0 { parts.append("\(backFromLater) back from Later") }
        guard !parts.isEmpty else { return nil }
        return MorningBrief(title: "Good morning", body: parts.prefix(maxParts).joined(separator: " \u{00B7} "))
    }

    /// "Dana is waiting on you", "Dana and Sam are waiting on you", "Dana, Sam and 2 others are waiting on you".
    static func waitingNames(_ waiting: [Post]) -> String {
        var seen = Set<String>()
        let names = waiting.map(\.email.from).filter { seen.insert($0.email).inserted }.map(\.firstName)
        return ReplyRecipients.nameList(names) + (names.count == 1 ? " is" : " are") + " waiting on you"
    }

    /// "Today: Game 9 PM", or "Today: Game 9 PM and 1 more".
    static func todayNames(_ today: [ComingUp.Entry], calendar: Calendar) -> String {
        guard let first = today.first else { return "" }
        var subject = FallbackSummarizer.cleanSubject(first.post.email.subject, fallbackBody: first.post.email.body)
        // The brief never carries a long dash or an exclamation mark, even when the subject does.
        subject = subject.replacingOccurrences(of: "\u{2014}", with: "-").replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "!", with: "")
        if subject.count > subjectLimit { subject = String(subject.prefix(subjectLimit - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}" }
        let time = first.date.hasTime ? " " + ComingUp.timeText(first.date.start, calendar: calendar) : ""
        let more = today.count > 1 ? " and \(today.count - 1) more" : ""
        return "Today: " + subject + time + more
    }

    /// The next time of day (minutes after midnight) on or after `now`: today if it is still ahead, else tomorrow.
    static func nextFire(minutes: Int, after now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        let today = calendar.date(byAdding: .minute, value: minutes, to: start) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }
}
