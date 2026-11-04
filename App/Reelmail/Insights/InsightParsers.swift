import Foundation

/// Health mail is never read for amounts, bodies or insights. Only appointment dates come from the subject.
enum HealthMail {
    static let domains = ["mychart", "patient", "health", "clinic", "medical", "dental", "pharmacy", "tricare", "va.gov"]
    static let subjectWords = ["appointment", "prescription", "lab result", "test result", "patient portal", "refill", "claim", "explanation of benefits"]

    static func isHealth(domain: String, subject: String) -> Bool {
        let d = domain.lowercased()
        let s = subject.lowercased()
        return domains.contains { d.contains($0) } || subjectWords.contains { s.contains($0) }
    }
}

/// What the parsers are given. Body may be empty for metadata-only messages.
struct InsightInput {
    var id: String
    var fromName: String
    var fromAddress: String
    var subject: String
    var date: Date
    var body: String

    var domain: String { InsightText.registrable(InsightText.domain(of: fromAddress)) }
}

/// Known-format readers. Pure: text in, facts out. Each reader returns nothing when the mail is not its format.
enum InsightParsers {
    static func parse(_ m: InsightInput) -> [InsightFact] {
        if HealthMail.isHealth(domain: m.domain, subject: m.subject) {
            return appointment(m).map { [.appointment($0)] } ?? []
        }
        var facts: [InsightFact] = []
        let text = InsightText.flatten(m.body)
        if let e = sense(m, text) { facts.append(.energyMonth(e)) }
        if let a = usageAlert(m, text) { facts.append(.usageAlert(a)) }
        if let o = programOffer(m, text) { facts.append(.offer(o)) }
        if let b = bill(m, text) { facts.append(.bill(b)) }
        if let r = renewal(m, text) { facts.append(.renewal(r)) }
        if let n = accountNotice(m) { facts.append(.account(n)) }
        return facts
    }

    // MARK: Energy

    static func sense(_ m: InsightInput, _ text: String) -> EnergyMonth? {
        guard m.domain.contains("sense.com") || m.fromName.lowercased().contains("sense") else { return nil }
        guard let mo = Rx.groups(#"(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})"#, in: m.subject + " " + text),
              let month = InsightDates.month(mo[1], year: mo[2]) else { return nil }
        guard let used = Rx.groups(#"([\d,]+(?:\.\d+)?)\s*kWh\s*(?:used|consumed)"#, in: text).flatMap({ InsightText.money($0[1]) }) else { return nil }
        let produced = Rx.groups(#"([\d,]+(?:\.\d+)?)\s*kWh\s*(?:produced|generated)"#, in: text).flatMap { InsightText.money($0[1]) } ?? 0
        guard let perDay = Rx.groups(#"\$\s*([\d,]+(?:\.\d+)?)\s*(?:/|per|a)\s*day"#, in: text).flatMap({ InsightText.money($0[1]) }) else { return nil }
        var change: Double?
        if let c = Rx.groups(#"(up|down|higher|lower|more|less)\s*\$\s*([\d.]+)\s*(?:/|per|a)\s*day"#, in: text), let v = InsightText.money(c[2]) {
            change = ["down", "lower", "less"].contains(c[1].lowercased()) ? -v : v
        }
        var devices: [EnergyDevice] = []
        for g in Rx.all(#"([A-Z][A-Za-z0-9 \-']{2,24}?)\s*\$\s*([\d,]+(?:\.\d+)?)\s*(?:this month|for the month|/mo)"#, in: text, options: []) {
            if let v = InsightText.money(g[2]) { devices.append(EnergyDevice(name: g[1].trimmingCharacters(in: .whitespaces), dollars: v)) }
        }
        return EnergyMonth(id: m.id, month: month, kwhUsed: used, kwhProduced: produced, dollarsPerDay: perDay, changePerDay: change, devices: devices)
    }

    static func usageAlert(_ m: InsightInput, _ text: String) -> UsageAlert? {
        guard Rx.test("usage alert|energy usage|bill.*so far|projected", in: m.subject + " " + String(text.prefix(300))) else { return nil }
        guard let g = Rx.groups(#"usage as of\s+([A-Za-z]+ \d{1,2}, \d{4}|\d{1,2}/\d{1,2}/\d{4})[^$]{0,120}\$\s*([\d,]+(?:\.\d+)?)"#, in: text),
              let asOf = InsightDates.parse(g[1]), let cost = InsightText.money(g[2]) else { return nil }
        var start: Date?, end: Date?
        if let c = Rx.groups(#"\|\s*(\d{1,2}/\d{1,2}/\d{4})\s*\|\s*(\d{1,2}/\d{1,2}/\d{4})\s*\|"#, in: text) {
            start = InsightDates.parse(c[1]); end = InsightDates.parse(c[2])
        }
        return UsageAlert(id: m.id, costToDate: cost, asOf: asOf, cycleStart: start, cycleEnd: end)
    }

    static func programOffer(_ m: InsightInput, _ text: String) -> ProgramOffer? {
        guard let g = Rx.groups(#"up to \$\s*([\d,]+(?:\.\d+)?)\s*in bill credits.{0,80}?joining\s+(?:the\s+)?(.{3,60}?)\s+for enrolling your\s+(.{3,80}?)[.!]"#, in: text),
              let credit = InsightText.money(g[1]) else { return nil }
        let devices = g[3].replacingOccurrences(of: " and ", with: ", ").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return ProgramOffer(id: m.id, program: g[2], credit: credit, devices: devices, seenOn: m.date)
    }

    // MARK: Bills

    private static let problemPhrases = [
        "payment failed", "payment was returned", "payment returned", "unable to process your payment", "could not process your payment",
        "past due", "overdue", "final notice", "disconnection", "service will be disconnected", "service will be interrupted",
        "insufficient funds", "declined", "autopay failed", "autopay was unsuccessful"
    ]

    static func hasPaymentProblem(subject: String, text: String) -> Bool {
        let hay = (subject + " " + String(text.prefix(1200))).lowercased()
        if hay.contains("past due date") && !hay.contains("past due balance") { return false }
        return problemPhrases.contains { hay.contains($0) }
    }

    static func bill(_ m: InsightInput, _ text: String) -> Bill? {
        let subject = m.subject
        let looksLikeBill = Rx.test("bill|statement|amount due|payment|invoice|autopay", in: subject)
        guard looksLikeBill else { return nil }

        if let g = Rx.groups(#"Payment Amount:?\s*\$\s*([\d,]+(?:\.\d+)?)\s*Date Posted:?\s*([A-Za-z]+ \d{1,2}, \d{4}|\d{1,2}/\d{1,2}/\d{4})"#, in: text),
           let amount = InsightText.money(g[1]), let posted = InsightDates.parse(g[2]) {
            return Bill(id: m.id, kind: .payment, payee: m.fromName, domain: m.domain, amount: amount, dueOn: nil, postedOn: posted, problem: false, lines: [])
        }
        if Rx.test("payment (received|confirmation|posted|successful)|thank you for your payment|payment was (received|successful)", in: subject) {
            let amount = Rx.groups(#"\$\s*([\d,]+(?:\.\d+)?)"#, in: text).flatMap { InsightText.money($0[1]) }
            return Bill(id: m.id, kind: .payment, payee: m.fromName, domain: m.domain, amount: amount, dueOn: nil, postedOn: m.date, problem: false, lines: [])
        }

        let problem = hasPaymentProblem(subject: subject, text: text)
        let amount = Rx.groups(#"(?:Amount Due|Total Amount Due|Total Current Charges|Balance Due)\s*:?\s*\$\s*([\d,]+(?:\.\d+)?)"#, in: text).flatMap { InsightText.money($0[1]) }
        let due = Rx.groups(#"(?:Due Date|Due on|Payment Due|due by)\s*:?\s*([A-Za-z]+ \d{1,2}, \d{4}|\d{1,2}/\d{1,2}/\d{4})"#, in: text).flatMap { InsightDates.parse($0[1]) }
        guard amount != nil || due != nil || problem else { return nil }

        var lines: [BillLine] = []
        for g in Rx.all(#"\b(Water|Sewer|Trash|Electric|Gas|Internet|Stormwater|Service Fee|Base Charge)[A-Za-z ]{0,20}?\s+\$\s*([\d,]+(?:\.\d+)?)"#, in: text) {
            if let v = InsightText.money(g[2]) { lines.append(BillLine(label: g[1], amount: v)) }
        }
        return Bill(id: m.id, kind: .statement, payee: m.fromName, domain: m.domain, amount: amount, dueOn: due, postedOn: m.date, problem: problem, lines: lines)
    }

    // MARK: Renewals

    static func renewal(_ m: InsightInput, _ text: String) -> Renewal? {
        guard let g = Rx.groups(#"charged for your\s+(.{3,60}?)\s+in\s+(\d+)\s+days"#, in: m.subject + " " + text),
              let days = Int(g[2]) else { return nil }
        let charges = InsightDates.calendar.date(byAdding: .day, value: days, to: m.date) ?? m.date
        return Renewal(id: m.id, payee: m.fromName, what: g[1], noticeDate: m.date, chargesOn: charges)
    }

    // MARK: Accounts (sender and subject only)

    static let financialDomains: [String: AccountKind] = [
        "fidelity.com": .brokerage, "vanguard.com": .brokerage, "schwab.com": .brokerage, "robinhood.com": .brokerage,
        "dfas.mil": .retireePay, "mypay.dfas.mil": .retireePay,
        "usaa.com": .bank, "chase.com": .bank, "bankofamerica.com": .bank, "wellsfargo.com": .bank, "navyfederal.org": .bank,
        "capitalone.com": .bank, "ally.com": .bank, "discover.com": .bank,
        "trumpaccounts.gov": .childAccount, "trumpaccounts.com": .childAccount,
        "tsp.gov": .retirement, "empower.com": .retirement, "principal.com": .retirement
    ]

    static func accountNotice(_ m: InsightInput) -> AccountNotice? {
        let d = m.domain
        let kind = financialDomains[d] ?? financialDomains.first(where: { d.hasSuffix($0.key) })?.value
        guard let kind else { return nil }
        let asks = Rx.test("take action|action (needed|required)|verify|confirm your|update your|expires|deadline|respond by", in: m.subject)
        return AccountNotice(id: m.id, institution: m.fromName, domain: d, kind: kind, subject: m.subject, date: m.date, asksAction: asks)
    }

    // MARK: Appointments (subject only)

    static func appointment(_ m: InsightInput) -> Appointment? {
        guard let g = Rx.groups(#"scheduled for\s+([A-Za-z]+ \d{1,2}, \d{4}|\d{1,2}/\d{1,2}/\d{4})(?:\s+(?:at\s+)?(\d{1,2}:\d{2}\s*[AP]M))?"#, in: m.subject),
              let day = InsightDates.parse(g[1]) else { return nil }
        guard g.count > 2, !g[2].isEmpty else { return Appointment(id: m.id, start: day, hasTime: false) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = InsightDates.utc; f.dateFormat = "h:mm a"
        let clock = f.date(from: g[2].uppercased().replacingOccurrences(of: "  ", with: " "))
        guard let clock else { return Appointment(id: m.id, start: day, hasTime: false) }
        let secs = clock.timeIntervalSince(f.date(from: "12:00 AM") ?? clock)
        return Appointment(id: m.id, start: day.addingTimeInterval(secs), hasTime: true)
    }
}
