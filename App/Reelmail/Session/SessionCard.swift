import CoreGraphics
import Foundation

// Sprint 8 (owner, Nov 10, 2026): each session email is a full white page moved with the thumb. Flick up skips,
// pull down into the ball puts it away, swipe left shows Move to Trash. The rules for the moves, the page's big fact,
// what a pull does and the likely drawers live here, pure, so they are tested. See docs/sprint8-swipe.md.

/// The thumb's rules, copied from Shoebox's Today: follows 1:1 for 40 pt, then half speed; lines at 100 pt up and
/// 170 pt down; a drag counts as sideways only when it is half again wider than tall.
enum SessionCardMotion {
    static let upDistance: CGFloat = 100
    static let downDistance: CGFloat = 170
    static let trashWidth: CGFloat = 112

    enum Direction: Equatable { case sideways, vertical }
    enum Release: Equatable { case skip, putAway, springBack }

    static func resisted(_ v: CGFloat) -> CGFloat {
        let a = abs(v)
        let s: CGFloat = v < 0 ? -1 : 1
        return s * (a <= 40 ? a : 40 + (a - 40) * 0.5)
    }

    /// Settled once per drag. Leftward opens Trash; once open, either way moves it.
    static func direction(dx: CGFloat, dy: CGFloat, slideStart: CGFloat) -> Direction {
        abs(dx) > abs(dy) * 1.5 && (dx < 0 || slideStart < 0) ? .sideways : .vertical
    }

    /// Where the page sits while Trash is being pulled open: 1:1 up to the word's width, then a third as fast.
    static func slide(start: CGFloat, dx: CGFloat) -> CGFloat {
        let x = min(0, start + dx)
        return x >= -trashWidth ? x : -trashWidth + (x + trashWidth) * 0.35
    }

    /// A quick flick up counts even short of the line; putting away needs the full pull, so it is never an accident.
    static func release(dy: CGFloat, predictedDy: CGFloat) -> Release {
        if dy <= -upDistance || (predictedDy <= -upDistance && dy < -30) { return .skip }
        if dy >= downDistance { return .putAway }
        return .springBack
    }

    /// 0 at rest, 1 at the put-away line (more past it).
    static func pullProgress(_ dy: CGFloat) -> CGFloat { max(0, dy) / downDistance }
}

/// The one big fact on an email's page: an amount, a day, who is waiting. Health mail is never read for amounts.
struct SessionHero: Equatable {
    var label: String
    var value: String

    static func make(_ m: SessionMessage, dates: [MailDate], now: Date, calendar: Calendar = .current) -> SessionHero {
        let waiting = m.section == .waiting || m.ask != nil
        let first = dates.first
        if !m.isHealth, let amount = amount(in: m.subject + "\n" + m.text) {
            return SessionHero(label: first.map { "Due " + dayLabel($0, now: now, calendar: calendar, withTime: false) } ?? "Amount", value: amount)
        }
        if let first {
            return SessionHero(label: waiting ? "Waiting on you" : "Coming up", value: dayLabel(first, now: now, calendar: calendar, withTime: true))
        }
        if waiting { return SessionHero(label: "Waiting on you", value: firstName(m.fromName)) }
        if m.isFirstTimeSender { return SessionHero(label: "New sender", value: shortName(m.fromName)) }
        return SessionHero(label: "From", value: m.isPerson ? firstName(m.fromName) : shortName(m.fromName))
    }

    /// "$142.18" from a sentence about money owed or paid; never a price from an ad.
    static func amount(in text: String) -> String? {
        let money = #"\$\s?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{2})?"#
        let context = ["due", "balance", "total", "amount", "payment", "pay", "bill", "invoice", "statement", "charge",
                       "owe", "quote", "estimate", "fee", "cost", "receipt", "refund", "paid"]
        for sentence in MailDates.sentences(in: text) where !MailDates.isPromoSentence(sentence) {
            let lower = sentence.lowercased()
            guard context.contains(where: { DrawerGuesser.containsWord(lower, $0) }),
                  let r = sentence.range(of: money, options: .regularExpression) else { continue }
            return sentence[r].replacingOccurrences(of: " ", with: "")
        }
        return nil
    }

    /// "Today", "Tomorrow 9 AM", "Friday 7 PM", "Nov 20".
    static func dayLabel(_ d: MailDate, now: Date, calendar: Calendar, withTime: Bool) -> String {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        let day: String
        switch ComingUp.bucket(d.start, now: now, calendar: calendar) {
        case .today: day = "Today"
        case .tomorrow: day = "Tomorrow"
        case .thisWeek: f.dateFormat = "EEEE"; day = f.string(from: d.start)
        case .later: f.dateFormat = "MMM d"; day = f.string(from: d.start)
        }
        guard withTime, d.hasTime else { return day }
        return day + " " + ComingUp.timeText(d.start, calendar: calendar)
    }

    static func firstName(_ name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.split(separator: " ").first.map(String.init) ?? n
    }

    /// "Cape Fear Power" stays; "Acme Corporation, Inc." becomes "Acme Corporation".
    static func shortName(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        for suffix in [", Inc.", ", Inc", " Inc.", " Inc", ", LLC", " LLC", " Co."] where n.hasSuffix(suffix) {
            n = String(n.dropLast(suffix.count))
        }
        return n.isEmpty ? name : n
    }
}

/// What pulling the page down into the ball will do, named on screen during the pull. Only filing, never Trash.
enum SessionPullTarget: Equatable {
    case putAway(DrawerChoice, dateLabel: String?)
    case archive
    case chooseDrawer

    static func make(_ item: SessionItem, dateLabel: String?) -> SessionPullTarget {
        switch item.suggestion {
        case .putAway(let d): return .putAway(d, dateLabel: nil)
        case .addDatesThenPutAway(let d): return .putAway(d, dateLabel: dateLabel)
        case .archive: return .archive
        case .reply: return .putAway(item.drawer?.choice ?? DrawerChoice(.personal), dateLabel: nil)
        case .decide: return item.drawer.map { .putAway($0.choice, dateLabel: nil) } ?? .chooseDrawer
        }
    }

    var label: String {
        switch self {
        case .putAway(let d, let date): return date.map { "Add \($0), then put away in \(d.title)" } ?? "Put away in \(d.title)"
        case .archive: return "Archive"
        case .chooseDrawer: return "Choose a drawer"
        }
    }

    var releaseLabel: String {
        switch self {
        case .chooseDrawer: return "Let go to choose a drawer"
        default: return "Let go: " + label
        }
    }
}

/// The drawers worth offering first when Lovely has no answer: the rules' guess, then categories whose words appear
/// in the mail, then the owner's usual order. Each with a short reason.
enum DrawerLikely {
    struct Pick: Equatable {
        var choice: DrawerChoice
        var reason: String
    }

    static let extraWords: [String: [String]] = [
        "home": ["chimney", "roof", "gutter", "furnace", "fireplace", "lawn", "yard", "contractor", "repair", "plumber",
                 "electrician", "appliance", "inspection", "cleaning"],
        "finance": ["quote", "estimate", "price", "payment", "invoice"],
        "projects": ["schedule a visit", "proposal", "contract"],
    ]

    static func words(for d: Drawer) -> [String] {
        let base: [String]
        switch d.id {
        case "home": base = DrawerGuesser.houseWords + DrawerGuesser.mortgageWords + DrawerGuesser.homeCoverWords + DrawerGuesser.phoneWords
        case "auto": base = DrawerGuesser.autoWords
        case "family": base = DrawerGuesser.schoolWords
        case "finance": base = DrawerGuesser.moneyWords
        case "lifelegal": base = DrawerGuesser.lifeWords + DrawerGuesser.legalWords
        case "government": base = DrawerGuesser.governmentWords
        case "work": base = DrawerGuesser.workWords
        case "travel": base = DrawerGuesser.travelWords
        case "shopping": base = DrawerGuesser.orderWords
        case "projects": base = DrawerGuesser.projectWords
        case "pets": base = DrawerGuesser.petWords
        case "accounts": base = DrawerGuesser.accountWords
        default: base = []
        }
        return base + (extraWords[d.id] ?? [])
    }

    static func top(_ m: SessionMessage, guess: DrawerGuess?, visible: [Drawer] = Drawer.allCases, limit: Int = 3) -> [Pick] {
        let haystack = (m.subject + "\n" + String(m.text.prefix(2000))).lowercased()
        var picks: [Pick] = []
        if let guess, visible.contains(guess.choice.drawer) { picks.append(Pick(choice: guess.choice, reason: guess.reason)) }
        let scored = visible.enumerated().compactMap { i, d -> (Drawer, Int, Int, [String])? in
            if m.isHealth && d != .health { return nil }
            let hits = words(for: d).filter { DrawerGuesser.containsWord(haystack, $0) }
            var score = hits.count
            if m.isPerson, d == .community { score += 1 }
            if m.isHealth, d == .health { score += 10 }
            return (d, score, i, Array(hits.prefix(3)))
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
        for (d, _, _, hits) in scored where picks.count < limit && !picks.contains(where: { $0.choice.drawer == d }) {
            picks.append(Pick(choice: DrawerChoice(d), reason: hits.isEmpty ? usual(d) : hits.joined(separator: ", ")))
        }
        return picks
    }

    /// "mortgage or rent, home insurance" from "the house: mortgage or rent, home insurance, utilities, ...".
    static func usual(_ d: Drawer) -> String {
        let meaning = d.meaning
        let after = meaning.split(separator: ":", maxSplits: 1).last.map(String.init) ?? meaning
        return after.split(separator: ",").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
    }
}
