import Foundation

extension FeedStore {
    /// What the Money, Energy or Kids page knows, as lines for Ask Lovely. Health mail never appears.
    func pageFacts(_ topic: PageFacts.Topic, now: Date = Date()) -> [String] {
        switch topic {
        case .money:
            return PageFacts.money(MoneyInsights.summary(insights.store, households: InsightSettings().load().households), now: now)
        case .energy:
            return PageFacts.energy(EnergyInsights.summary(insights.store, household: nil), now: now)
        case .kids:
            let mail = InsightSettings().load().kids.flatMap { kid in
                kidMail(for: kid).compactMap { item -> (kid: String, subject: String, from: String, sent: Date, upcoming: String?)? in
                    let e = item.post.email
                    guard !HealthMail.isHealth(address: e.from.email, name: e.from.name, subject: e.subject) else { return nil }
                    let date = MailDates.extract(e, now: now).first.map { ComingUp.fullLabel($0) }
                    return (kid.name, e.subject, e.from.name.isEmpty ? e.from.email : e.from.name, e.date, date)
                }
            }
            return PageFacts.kids(mail.sorted { $0.sent > $1.sent }, now: now)
        }
    }
}
