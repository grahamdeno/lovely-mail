import Foundation

/// Home's Today steps and glance cards, from the mail loaded now.
extension FeedStore {
    /// The glance cards, most urgent first (Home's "All cards" page).
    var glanceCards: [GlanceCard] {
        let d = digest
        let soon = ComingUp.thisWeek(comingUp, now: Date())
        let kidProfiles = InsightSettings().load().kids
        let kidMail = kidProfiles.flatMap { kid in kidMail(for: kid).map { (kid.name, $0.post) } }
        let latestKid = kidMail.max { $0.1.email.date < $1.1.email.date }
        let energy = EnergyInsights.summary(insights.store, household: nil)
        let money = MoneyInsights.summary(insights.store, households: InsightSettings().load().households)
        return HomeGlance.cards(
            next: soon.first.map { HomeGlance.Next(date: $0.date.start, hasTime: $0.date.hasTime,
                                                   title: $0.post.email.subject.isEmpty ? $0.post.email.from.name : $0.post.email.subject) },
            thisWeek: soon.count,
            openBills: money.households.filter { !$0.ended }.flatMap(\.open).map { HomeGlance.DueBill(payee: $0.payee, amount: $0.amount, dueOn: $0.dueOn) },
            paymentProblem: money.alarms.first?.payee,
            kidsCount: kidMail.count, latestKid: latestKid.map { ($0.0, $0.1.email.subject) },
            energyPerDay: energy.latest?.dollarsPerDay, energyChange: energy.latest?.changePerDay,
            earlier: d.earlier.count, organizations: d.organizations.map { ($0.name, $0.posts.count) }, now: Date())
    }

    /// Today's steps, remembered for the day so finished ones stay checked.
    func todaySteps(now: Date = Date()) -> [TodayStep] {
        let d = digest
        let money = MoneyInsights.summary(insights.store, households: InsightSettings().load().households)
        let cal = Calendar.current
        var inputs = TodayPlan.Inputs()
        inputs.waiting = d.waiting.map { ($0.id, $0.email.from.firstName, $0.email.subject.isEmpty ? $0.summary.blurb : $0.email.subject) }
        inputs.toGoThrough = sessionCandidates.count
        inputs.bills = money.households.filter { !$0.ended }.flatMap(\.open).compactMap { b in b.dueOn.map { (b.payee, $0) } }
        inputs.today = comingUp.filter { cal.isDate($0.date.start, inSameDayAs: now) }.map { e in
            (e.post.id, e.date.hasTime ? HomeGlance.dayLabel(e.date.start, hasTime: true, now: now).replacingOccurrences(of: "Today ", with: "") : "Today",
             e.post.email.subject.isEmpty ? e.post.email.from.name : e.post.email.subject)
        }
        let day = Self.dayKey(now)
        let store = TodayPlanStore(account: account ?? "demo")
        let steps = TodayPlan.merge(saved: store.load(day: day), candidates: TodayPlan.candidates(inputs, now: now))
        store.save(steps, day: day)
        return steps
    }
}
