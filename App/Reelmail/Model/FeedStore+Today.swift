import Foundation

/// Home's Today steps, from the mail loaded now.
extension FeedStore {
    /// Today's steps, remembered for the day so finished ones stay checked.
    func todaySteps(now: Date = Date()) -> [TodayStep] {
        let d = digest
        let money = MoneyInsights.summary(insights.store, households: InsightSettings().load().households)
        let cal = Calendar.current
        var inputs = TodayPlan.Inputs()
        inputs.waiting = d.waiting.map { ($0.id, $0.email.from.firstName, $0.email.subject.isEmpty ? $0.summary.blurb : $0.email.subject) }
        inputs.toGoThrough = sessionCandidates.count
        inputs.bills = money.households.filter { !$0.ended }.flatMap(\.open).compactMap { b in b.dueOn.map { (b.payee, $0, Optional(b.id)) } }
        inputs.today = comingUp.filter { cal.isDate($0.date.start, inSameDayAs: now) }.map { e in
            (e.post.id, e.date.hasTime ? HomeGlance.dayLabel(e.date.start, hasTime: true, now: now).replacingOccurrences(of: "Today ", with: "") : "Today",
             e.post.email.subject.isEmpty ? e.post.email.from.name : e.post.email.subject)
        }
        let day = Self.dayKey(now)
        let store = TodayPlanStore(account: account ?? "demo")
        let saved = store.load(day: day)
        let steps = TodayPlan.merge(saved: saved, candidates: TodayPlan.candidates(inputs, now: now))
        // Only write when they changed. Home calls this while drawing; a write on every draw made SwiftUI redraw Home,
        // which wrote again, so build 1046 froze at launch and iOS closed it.
        if steps != saved { store.save(steps, day: day) }
        return steps
    }
}
