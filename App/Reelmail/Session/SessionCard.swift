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

// MARK: Blue bar drop (owner, Nov 13, 2026)

/// What the email page says in words, with no box around it. Lovely's summary leads (it is capped at 25 words, so a
/// taller box would only show empty glass); the email's own words fill the rest of the page and fade out, and a tap opens
/// the whole thing. The fallback summary is the email's first words, so it is not repeated. Health mail and mail with
/// codes, account numbers, medical or legal details never show their own words here.
struct SessionCardText: Equatable {
    var lead: String?
    var leadIsAsk = false
    var excerpt: String?

    static let excerptLimit = 700

    static func make(_ m: SessionMessage, summary: EmailSummary) -> SessionCardText {
        let blurb = summary.blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = SessionCardText()
        if let ask = m.ask?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty {
            out.lead = ask; out.leadIsAsk = true
        } else if summary.engine == .appleIntelligence, !blurb.isEmpty {
            out.lead = blurb
        }
        if !m.isHealth, !summary.sensitive {
            let words = clean(m.text)
            if !words.isEmpty, words != out.lead { out.excerpt = words }
        }
        if out.lead == nil, out.excerpt == nil, !blurb.isEmpty { out.lead = blurb }
        return out
    }

    /// Spaces collapsed, at most one blank line in a row, cut at a word near the limit.
    static func clean(_ s: String) -> String {
        var lines: [String] = []
        for raw in s.components(separatedBy: .newlines) {
            let line = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            if line.isEmpty { if let last = lines.last, !last.isEmpty { lines.append("") } } else { lines.append(line) }
        }
        while lines.last == "" { lines.removeLast() }
        let text = lines.joined(separator: "\n")
        guard text.count > excerptLimit else { return text }
        let cut = text.prefix(excerptLimit)
        let end = cut.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? cut.endIndex
        return String(cut[..<end]) + "\u{2026}"
    }
}

/// The rose dot's flight after an email drops into the blue bar: one continuous motion with no joints. It is launched
/// up and to the right, a soft pull toward the middle swings it back left of center while gravity brings it down, it
/// bounces three times on the bar (each lower, with a squash), then drops through. About 1.7 seconds. Worked in a
/// 390 by 844 space; the view scales it to the screen.
struct DropFlight: Equatable {
    static let width: Double = 390
    static let height: Double = 844
    static let barHeight: Double = 20
    static let radius: Double = 24
    static var floor: Double { height - barHeight - radius }

    var x = 170.0
    var y = DropFlight.floor
    var vx = 1350.0
    var vy = -2170.0
    private(set) var bounces = 0
    private(set) var squash = 0.0
    private(set) var grow = 0.0
    private(set) var through = false
    private(set) var elapsed = 0.0

    /// Gone through the bar and faded out.
    var finished: Bool { through && y >= Self.floor + 70 }
    var opacity: Double { through ? max(0, 1 - (y - Self.floor) / 70) : 1 }
    /// Width and height scale: it grows in as it leaves the bar and squashes on each landing.
    var scale: (x: Double, y: Double) {
        let g = 0.6 + 0.4 * (1 - pow(1 - grow, 3))
        return (g * (1 + 0.32 * squash), g * (1 - 0.28 * squash))
    }

    /// Moves it on by `dt` seconds. Returns how hard it landed (0...1) when it lands on the bar in this step.
    mutating func step(_ dt: Double) -> Double? {
        let dt = min(1.0 / 30, max(0, dt))
        elapsed += dt
        var landed: Double?
        let n = 4, h = dt / Double(n)
        for _ in 0..<n {
            vx += (-40 * (x - 165) - 3 * vx) * h
            vy += 4200 * h
            x += vx * h; y += vy * h
            if !through, vy > 0, y >= Self.floor {
                let hit = vy
                y = Self.floor; bounces += 1
                vy = -vy * (bounces == 1 ? 0.38 : 0.34)
                squash = min(1, 0.5 + abs(vy) / 1200)
                landed = min(1, hit / 2200)
                if bounces >= 3 { through = true; vy = 260 }
            }
        }
        grow = min(1, grow + dt / 0.14)
        squash = max(0, squash - dt * 10)
        return landed
    }
}
