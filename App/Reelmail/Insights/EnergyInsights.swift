import Foundation

/// What the Energy page says, worked out from the facts. Pure. One suggestion a month, rule-based, no model.
struct EnergySummary: Equatable {
    var latest: EnergyMonth?
    /// Up to 12 months, oldest first.
    var months: [EnergyMonth]
    var headline: String
    var suggestion: String?
    var costToDate: UsageAlert?
    var offer: ProgramOffer?
    var water: [Bill]
}

enum EnergyInsights {
    static func summary(_ store: InsightStore, household: Household?, today: Date = Date()) -> EnergySummary {
        let months = Array(store.energy.sorted { $0.month < $1.month }.suffix(12))
        let latest = months.last
        let alert = store.alerts.max { $0.asOf < $1.asOf }
        let offer = store.offers.max { $0.seenOn < $1.seenOn }
        let water = store.bills.filter { $0.kind == .statement && $0.involvesWater }.sorted { $0.postedOn > $1.postedOn }
        return EnergySummary(latest: latest, months: months, headline: headline(latest), suggestion: suggestion(months: months, offer: offer),
                             costToDate: alert, offer: offer, water: Array(water.prefix(6)))
    }

    static func headline(_ m: EnergyMonth?) -> String {
        guard let m else { return "No energy report found yet" }
        let cost = String(format: "$%.2f", m.dollarsPerDay)
        guard let change = m.changePerDay, abs(change) >= 0.01 else { return "\(cost) a day last month" }
        let word = change < 0 ? "down" : "up"
        return "\(cost) a day last month, \(word) \(String(format: "$%.2f", abs(change))) from the month before"
    }

    /// One plain suggestion, chosen by the first rule that applies.
    static func suggestion(months: [EnergyMonth], offer: ProgramOffer?) -> String? {
        if let offer, offer.credit > 0 {
            let devices = offer.devices.isEmpty ? "your devices" : offer.devices.joined(separator: " and ")
            return "\(offer.program) offers up to \(money(offer.credit)) in bill credits for enrolling \(devices)."
        }
        guard let latest = months.last else { return nil }
        if let top = latest.devices.max(by: { $0.dollars < $1.dollars }), top.dollars >= 10 {
            return "\(top.name) cost the most last month at \(money(top.dollars)). It is the first place to look for savings."
        }
        if months.count >= 3 {
            let prior = months.dropLast().suffix(3).map(\.dollarsPerDay)
            let average = prior.reduce(0, +) / Double(prior.count)
            if latest.dollarsPerDay > average * 1.15 {
                return "Last month ran about \(Int(((latest.dollarsPerDay / average) - 1) * 100)) percent above your recent average."
            }
        }
        return nil
    }

    private static func money(_ v: Double) -> String { v == v.rounded() ? "$\(Int(v))" : String(format: "$%.2f", v) }

    /// Sense mail leaves Home once an Energy snapshot exists. Local rule only; nothing is changed in Gmail.
    static func shouldHideFromHome(domain: String, fromName: String, store: InsightStore) -> Bool {
        guard !store.energy.isEmpty else { return false }
        return domain.contains("sense.com") || fromName.lowercased() == "sense"
    }
}
