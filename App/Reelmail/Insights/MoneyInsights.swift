import Foundation

struct HouseholdBills: Equatable {
    var household: Household
    var ended: Bool
    var open: [Bill]
    var recentPayments: [Bill]
}

struct MoneySummary: Equatable {
    var households: [HouseholdBills]
    /// Latest mail from each bank, broker or similar, newest first.
    var accounts: [AccountNotice]
    var renewals: [Renewal]
    var alarms: [Bill]
    var actionNeeded: [AccountNotice]
}

/// Bills, accounts and renewals worked out from facts. Pure. Amounts come from bills only; account mail contributes sender and subject.
enum MoneyInsights {
    static let defaultHousehold = Household(id: "home", name: "Home")

    static func summary(_ store: InsightStore, households configured: [Household], today: Date = Date()) -> MoneySummary {
        let households = configured.isEmpty ? [defaultHousehold] : configured
        let statements = store.bills.filter { $0.kind == .statement }
        let payments = store.bills.filter { $0.kind == .payment }

        func isOpen(_ b: Bill) -> Bool {
            if payments.contains(where: { $0.domain == b.domain && $0.postedOn >= b.postedOn }) { return false }
            guard let due = b.dueOn else { return today.timeIntervalSince(b.postedOn) < 45 * 86_400 }
            return due >= today.addingTimeInterval(-30 * 86_400)
        }

        var sections: [HouseholdBills] = []
        for h in households {
            let mine: (Bill) -> Bool = { InsightSettings.household(for: $0, in: households)?.id == h.id }
            let open = statements.filter { mine($0) && isOpen($0) }.sorted { ($0.dueOn ?? $0.postedOn) < ($1.dueOn ?? $1.postedOn) }
            let paid = payments.filter(mine).sorted { $0.postedOn > $1.postedOn }
            sections.append(HouseholdBills(household: h, ended: h.isEnded(on: today), open: open, recentPayments: Array(paid.prefix(3))))
        }

        var latest: [String: AccountNotice] = [:]
        for n in store.accounts where (latest[n.domain]?.date ?? .distantPast) < n.date { latest[n.domain] = n }
        let accounts = latest.values.sorted { $0.date > $1.date }

        let renewals = store.renewals.filter { $0.chargesOn >= today }.sorted { $0.chargesOn < $1.chargesOn }
        let cutoff = today.addingTimeInterval(-30 * 86_400)
        let actions = accounts.filter { $0.asksAction && $0.date >= cutoff }
        return MoneySummary(households: sections, accounts: accounts, renewals: renewals, alarms: alarms(store, today: today), actionNeeded: actions)
    }

    /// A payment problem reported in the last 14 days with no later payment from the same sender.
    static func alarms(_ store: InsightStore, today: Date = Date()) -> [Bill] {
        let window = today.addingTimeInterval(-14 * 86_400)
        return store.bills.filter { b in
            b.problem && b.postedOn >= window
                && !store.bills.contains { $0.kind == .payment && $0.domain == b.domain && $0.postedOn > b.postedOn }
        }.sorted { $0.postedOn > $1.postedOn }
    }
}

/// The only insight allowed to notify outside the morning brief.
/// One notice per problem: a message is announced at most once, and a sender at most once every 14 days, so a run of reminders
/// about the same bill makes one notice. Names appear on the lock screen only when "Show names in the brief" is on.
enum PaymentAlarm {
    static let key = "lovely.alarm.notified"
    static let senderKey = "lovely.alarm.senders"
    static let quietDays: TimeInterval = 14 * 86_400

    static func notice(for bill: Bill, showNames: Bool) -> (title: String, body: String) {
        let who = showNames && !bill.payee.isEmpty ? bill.payee : "A bill"
        return ("Payment problem", "\(who) says a payment did not go through or is late. Open Lovely to check.")
    }

    static func unannounced(_ alarms: [Bill], defaults: UserDefaults = .standard, now: Date = Date()) -> [Bill] {
        let done = Set(defaults.stringArray(forKey: key) ?? [])
        let senders = defaults.dictionary(forKey: senderKey) as? [String: Double] ?? [:]
        var seen = Set<String>()
        return alarms.filter { bill in
            guard !done.contains(bill.id) else { return false }
            if let last = senders[bill.domain], now.timeIntervalSince1970 - last < quietDays { return false }
            return seen.insert(bill.domain).inserted
        }
    }

    static func markAnnounced(_ bills: [Bill], defaults: UserDefaults = .standard, now: Date = Date()) {
        var done = Set(defaults.stringArray(forKey: key) ?? [])
        var senders = defaults.dictionary(forKey: senderKey) as? [String: Double] ?? [:]
        bills.forEach { done.insert($0.id); senders[$0.domain] = now.timeIntervalSince1970 }
        defaults.set(Array(done), forKey: key)
        defaults.set(senders, forKey: senderKey)
    }

    /// Bills that would have been announced but fall in a sender's quiet period are still marked, so they never notify later.
    static func markSeen(_ alarms: [Bill], defaults: UserDefaults = .standard) {
        var done = Set(defaults.stringArray(forKey: key) ?? [])
        alarms.forEach { done.insert($0.id) }
        defaults.set(Array(done), forKey: key)
    }
}
