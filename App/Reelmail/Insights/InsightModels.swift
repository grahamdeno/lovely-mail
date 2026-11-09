import Foundation

// Facts Lovely reads out of mail, kept on this iPhone. Every record keeps the id of the email it came from,
// so no insight is shown without a source. Account numbers, codes and passwords are never stored.

struct EnergyDevice: Codable, Hashable, Sendable {
    var name: String
    var dollars: Double
}

/// One monthly energy report (a Sense snapshot).
struct EnergyMonth: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// First day of the month, UTC.
    var month: Date
    var kwhUsed: Double
    var kwhProduced: Double
    var dollarsPerDay: Double
    /// Change in dollars a day against the month before. Negative is lower.
    var changePerDay: Double?
    var devices: [EnergyDevice]
}

/// A utility's mid-cycle alert: cost so far in the billing cycle.
struct UsageAlert: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var costToDate: Double
    var asOf: Date
    var cycleStart: Date?
    var cycleEnd: Date?
}

/// A utility program that pays credits for enrolling a device.
struct ProgramOffer: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var program: String
    var credit: Double
    var devices: [String]
    var seenOn: Date
}

struct BillLine: Codable, Hashable, Sendable {
    var label: String
    var amount: Double
}

struct Bill: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case statement, payment }
    var id: String
    var kind: Kind
    /// The sender's display name.
    var payee: String
    /// The sender's company domain, for assigning a household.
    var domain: String
    var amount: Double?
    var dueOn: Date?
    var postedOn: Date
    /// The mail says a payment failed, was returned, is past due or service will stop.
    var problem: Bool
    var lines: [BillLine]

    /// Water or sewer is on the bill.
    var involvesWater: Bool {
        let name = payee.lowercased()
        return name.contains("water") || name.contains("utility") || lines.contains { $0.label.lowercased().contains("water") || $0.label.lowercased().contains("sewer") }
    }
}

enum AccountKind: String, Codable, Sendable, CaseIterable {
    case brokerage, retirement, bank, retireePay, childAccount, loan, other

    var label: String {
        switch self {
        case .brokerage: return "Brokerage"
        case .retirement: return "Retirement"
        case .bank: return "Bank"
        case .retireePay: return "Retiree pay"
        case .childAccount: return "Child account"
        case .loan: return "Loan"
        case .other: return "Account"
        }
    }
}

/// One email from a bank, broker or similar. Only the sender and subject are used.
struct AccountNotice: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var institution: String
    var domain: String
    var kind: AccountKind
    var subject: String
    var date: Date
    /// The subject asks you to act ("Take action", "Action needed").
    var asksAction: Bool
}

struct Renewal: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var payee: String
    var what: String
    var noticeDate: Date
    var chargesOn: Date
}

/// Health mail contributes appointment dates only.
struct Appointment: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var start: Date
    var hasTime: Bool
}

enum InsightFact: Equatable {
    case energyMonth(EnergyMonth)
    case usageAlert(UsageAlert)
    case offer(ProgramOffer)
    case bill(Bill)
    case account(AccountNotice)
    case renewal(Renewal)
    case appointment(Appointment)
}

/// Everything read from mail so far. Saved on this phone, deleted when Gmail is disconnected.
struct InsightStore: Codable, Equatable {
    var energy: [EnergyMonth] = []
    var alerts: [UsageAlert] = []
    var offers: [ProgramOffer] = []
    var bills: [Bill] = []
    var accounts: [AccountNotice] = []
    var renewals: [Renewal] = []
    var appointments: [Appointment] = []
    /// Message ids already read, so a refresh only looks at new mail.
    var processed: Set<String> = []
    /// The 12-month backfill reached the end of the mailbox.
    var historyDone = false
    /// Messages seen in the last backfill pass, for the progress line.
    var historySeen = 0

    mutating func add(_ fact: InsightFact) {
        switch fact {
        case .energyMonth(let x): energy.removeAll { $0.id == x.id }; energy.append(x)
        case .usageAlert(let x): alerts.removeAll { $0.id == x.id }; alerts.append(x)
        case .offer(let x): offers.removeAll { $0.id == x.id }; offers.append(x)
        case .bill(let x): bills.removeAll { $0.id == x.id }; bills.append(x)
        case .account(let x): accounts.removeAll { $0.id == x.id }; accounts.append(x)
        case .renewal(let x): renewals.removeAll { $0.id == x.id }; renewals.append(x)
        case .appointment(let x): appointments.removeAll { $0.id == x.id }; appointments.append(x)
        }
    }

    var isEmpty: Bool {
        energy.isEmpty && alerts.isEmpty && offers.isEmpty && bills.isEmpty && accounts.isEmpty && renewals.isEmpty && appointments.isEmpty
    }
}

/// Reads and writes the store on this phone. Complete file protection, excluded from backups.
struct InsightStorage {
    let directory: URL

    static var standard: InsightStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return InsightStorage(directory: base.appendingPathComponent("Reelmail/insights", isDirectory: true))
    }

    private var file: URL { directory.appendingPathComponent("insights.json") }

    func load() -> InsightStore {
        guard let data = try? Data(contentsOf: file), let store = try? JSONDecoder().decode(InsightStore.self, from: data) else { return InsightStore() }
        return store
    }

    func save(_ store: InsightStore) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(store)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var mutable = file; try? mutable.setResourceValues(values)
        } catch {
            // Insights are rebuilt from mail; a failed save only costs a re-read.
        }
    }

    func removeAll() { try? FileManager.default.removeItem(at: directory) }
}
