import Foundation

/// Home 2 (owner, Nov 10, 2026): mostly white space, and the first thing to do is talk about your mail. Above the
/// field, a greeting and one short sentence that says what matters (at most two things), with the important words
/// tappable; under it, three questions worth asking. Built from Today's steps. Pure, so it is tested.
struct HomeLine: Equatable {
    enum Link: String, Equatable { case answer, bill, session }

    struct Segment: Equatable {
        var text: String
        var link: Link? = nil
    }

    var greeting: String
    var sentence: [Segment]
    var suggestions: [String]

    static func greeting(firstName: String, hour: Int) -> String {
        let part = (5..<12).contains(hour) ? "Good morning" : ((12..<17).contains(hour) ? "Good afternoon" : "Good evening")
        let name = firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part + "." : "\(part), \(name)."
    }

    static func make(steps: [TodayStep], toGoThrough: Int, firstName: String, hour: Int) -> HomeLine {
        let open = steps.filter { !$0.done }
        var sentences: [[Segment]] = []
        var suggestions: [String] = []

        if let answer = open.first(where: { $0.kind == .answer }) {
            let who = answer.title.hasPrefix("Answer ") ? String(answer.title.dropFirst("Answer ".count)) : answer.title
            let many = who.hasSuffix(" people")
            sentences.append([Segment(text: who, link: .answer), Segment(text: many ? " are waiting on you." : " is waiting on you.")])
            suggestions.append(many ? "Who's waiting on me?" : "Answer \(who)")
        }
        suggestions.append("What needs me today?")
        if let bill = open.first(where: { $0.kind == .bill }) {
            let payee = bill.title.hasPrefix("Pay ") ? String(bill.title.dropFirst("Pay ".count)) : bill.title
            let when = bill.detail.prefix(1).lowercased() + bill.detail.dropFirst()
            sentences.append([Segment(text: payee, link: .bill), Segment(text: " is \(when).")])
            suggestions.append("When is \(payee) due?")
        }
        if toGoThrough > 0 {
            let count = toGoThrough == 1 ? "1 email" : "\(toGoThrough) emails"
            sentences.append([Segment(text: count, link: .session), Segment(text: " to go through.")])
        }
        for fallback in ["What did school send this week?", "Who's waiting on me?"] where suggestions.count < 3 && !suggestions.contains(fallback) {
            suggestions.append(fallback)
        }

        var sentence: [Segment] = []
        let shown = Array(sentences.prefix(2))
        for (i, s) in shown.enumerated() {
            if i > 0 { sentence.append(Segment(text: " ")) }
            sentence += s
        }
        if shown.isEmpty {
            sentence = [Segment(text: "You're all caught up.")]
        } else if shown.count == 1 {
            sentence.append(Segment(text: " Everything else can wait."))
        }
        return HomeLine(greeting: greeting(firstName: firstName, hour: hour), sentence: sentence, suggestions: Array(suggestions.prefix(3)))
    }

    /// The sentence as plain words, for VoiceOver and tests.
    var plainSentence: String { sentence.map(\.text).joined() }

    /// Questions Lovely answers on the phone without a round trip: today's steps as buttons.
    static func isNeedsMe(_ question: String) -> Bool {
        let q = question.lowercased()
        return ["needs me", "need me", "what's up today", "what should i do", "what's important"].contains { q.contains($0) }
    }
}
