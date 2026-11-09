import SwiftUI

/// One quiet row on Home that opens the Money page.
struct MoneyRow: View {
    @Environment(Router.self) private var router
    let summary: MoneySummary
    var body: some View {
        Button { router.open(.money) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Money").font(.subheadline.weight(.medium)).foregroundStyle(CalmStyle.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
                }
                Text(line).font(.caption).foregroundStyle(summary.alarms.isEmpty ? CalmStyle.secondary : CalmStyle.warningInk)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("home.row.money")
    }

    var line: String {
        if let a = summary.alarms.first { return "Payment problem: \(a.payee)" }
        let open = summary.households.reduce(0) { $0 + $1.open.count }
        return open == 0 ? "No bills waiting" : "\(open) bill\(open == 1 ? "" : "s") waiting"
    }
}

/// Money as answers (Nov 9 redesign): what is next, what may be unpaid, how spending moves, then history.
/// Amounts are shown only for bills; account mail shows sender and subject, and only when it asks for action.
struct MoneyView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    /// Bumped when he marks a bill paid, so the page redraws.
    @State private var marks = 0
    @State private var showHistory = false

    var body: some View {
        let _ = marks
        let summary = MoneyInsights.summary(store.insights.store, households: InsightSettings().load().households)
        let today = Date()
        let next = MoneyPlan.next(summary, today: today)
        let unpaid = MoneyPlan.maybeUnpaid(summary, today: today)
        let months = MoneyPlan.months(store.insights.store.bills, today: today)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(summary.alarms) { b in
                    Text("\(b.payee) reports a payment problem. Check it today.")
                        .font(.subheadline.weight(.semibold)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
                        .onTapGesture { router.open(.email(b.id)) }
                }
                // 1. The answer.
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                    if let next {
                        Text(next.payee + (next.amount.map { String(format: " · $%.2f", $0) } ?? ""))
                            .font(.title3.weight(.bold)).lineLimit(2)
                        Text(dueText(next)).font(.subheadline).foregroundStyle(CalmStyle.secondary)
                    } else {
                        Text("Nothing due right now").font(.title3.weight(.bold))
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .onTapGesture { if let next { router.open(.email(next.id)) } }
                .accessibilityIdentifier("money.next")

                // 2. Did you pay these?
                if !unpaid.isEmpty {
                    header("Did you pay these?")
                    Text("Their due dates passed and Lovely didn't see a payment email.").font(.caption).foregroundStyle(CalmStyle.secondary)
                    ForEach(unpaid) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { router.open(.email(b.id)) } label: {
                                row(b.payee, sub: dueText(b), trailing: b.amount.map { String(format: "$%.2f", $0) } ?? "", card: false)
                            }.buttonStyle(.plain)
                            HStack(spacing: 8) {
                                Button { MoneyPaidMarks().mark(b.id); marks += 1 } label: { Label("Paid", systemImage: "checkmark").frame(maxWidth: .infinity) }
                                    .buttonStyle(CalmActionStyle(prominent: true)).accessibilityIdentifier("money.paid")
                                Button { router.open(.email(b.id)) } label: { Text("Not yet").frame(maxWidth: .infinity) }
                                    .buttonStyle(CalmActionStyle())
                            }
                        }
                        .padding(12).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                // 3. Coming up after the next one.
                let upcoming = summary.households.filter { !$0.ended }.flatMap(\.open)
                    .filter { $0.id != next?.id && !unpaid.contains($0) }
                    .sorted { ($0.dueOn ?? .distantFuture) < ($1.dueOn ?? .distantFuture) }
                if !upcoming.isEmpty {
                    header("Also coming up")
                    ForEach(upcoming) { billRow($0, tag: dueText($0)) }
                }

                // 4. How it moves.
                if months.contains(where: { $0.total > 0 }) {
                    header("Bills by month")
                    MoneyMonthsChart(months: months)
                    if let trend = MoneyPlan.trend(months) { Text(trend).font(.caption).foregroundStyle(CalmStyle.secondary) }
                }

                if !summary.renewals.isEmpty {
                    header("Renewals")
                    ForEach(summary.renewals) { r in
                        row(r.payee, sub: r.what, trailing: r.chargesOn.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                // Accounts only when one asks you to act (promotions from a broker are not news).
                if !summary.actionNeeded.isEmpty {
                    header("Accounts asking for action")
                    ForEach(summary.actionNeeded) { n in
                        Button { router.open(.email(n.id)) } label: { row(n.institution, sub: n.subject, trailing: n.kind.label) }.buttonStyle(.plain)
                    }
                }

                // 5. History, one tap away.
                let paid = summary.households.flatMap(\.recentPayments).sorted { $0.postedOn > $1.postedOn }
                if !paid.isEmpty {
                    Button { withAnimation { showHistory.toggle() } } label: {
                        HStack {
                            Text("History · \(paid.count) paid").font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: showHistory ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                        }.foregroundStyle(CalmStyle.blue).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.top, 8)
                    if showHistory {
                        ForEach(paid) { billRow($0, tag: "Paid " + $0.postedOn.formatted(date: .abbreviated, time: .omitted)) }
                    }
                }
                if store.insights.store.isEmpty {
                    Text(store.insights.isRunning ? "Reading your last 12 months of mail." : "Nothing found yet.")
                        .font(.subheadline).foregroundStyle(CalmStyle.secondary)
                }
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Money").navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary).padding(.top, 8)
    }

    private func dueText(_ b: Bill) -> String {
        guard let due = b.dueOn else { return "Open" }
        return "Due " + due.formatted(date: .abbreviated, time: .omitted)
    }

    private func billRow(_ b: Bill, tag: String) -> some View {
        Button { router.open(.email(b.id)) } label: {
            row(b.payee, sub: tag, trailing: b.amount.map { String(format: "$%.2f", $0) } ?? "")
        }.buttonStyle(.plain)
    }

    private func row(_ title: String, sub: String, trailing: String, card: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).lineLimit(1)
                Text(sub).font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(trailing).font(.subheadline).foregroundStyle(CalmStyle.secondary)
        }
        .padding(.horizontal, card ? 14 : 0).padding(.vertical, card ? 8 : 0).frame(minHeight: card ? 48 : 0)
        .background(card ? CalmStyle.card : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

/// Six bars, one per month, so a jump stands out at a glance.
struct MoneyMonthsChart: View {
    let months: [MoneyPlan.Month]
    var body: some View {
        let top = max(months.map(\.total).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(months) { m in
                VStack(spacing: 4) {
                    Text(m.total > 0 ? String(format: "$%.0f", m.total) : "").font(.caption2).foregroundStyle(CalmStyle.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(m.id == months.last?.id ? CalmStyle.blue : CalmStyle.blue.opacity(0.35))
                        .frame(height: max(4, CGFloat(m.total / top) * 110))
                    Text(m.start.formatted(.dateTime.month(.abbreviated))).font(.caption2).foregroundStyle(CalmStyle.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 150, alignment: .bottom)
        .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(months.map { $0.start.formatted(.dateTime.month(.wide)) + String(format: " $%.0f", $0.total) }.joined(separator: ", "))
    }
}
