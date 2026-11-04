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
        }.buttonStyle(.plain)
    }

    private var line: String {
        if let a = summary.alarms.first { return "Payment problem: \(a.payee)" }
        let open = summary.households.reduce(0) { $0 + $1.open.count }
        return open == 0 ? "No bills waiting" : "\(open) bill\(open == 1 ? "" : "s") waiting"
    }
}

/// Bills by household, accounts, renewals. Amounts are shown only for bills; account mail shows sender and subject.
struct MoneyView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let summary = MoneyInsights.summary(store.insights.store, households: InsightSettings().load().households)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(summary.alarms) { b in
                    Text("\(b.payee) reports a payment problem. Check it today.")
                        .font(.subheadline.weight(.semibold)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
                        .onTapGesture { router.open(.email(b.id)) }
                }
                ForEach(summary.households, id: \.household.id) { section in
                    header(section.household.name + (section.ended ? " · Ended" : ""))
                    if section.open.isEmpty && section.recentPayments.isEmpty {
                        Text("No bills found in the last 12 months.").font(.subheadline).foregroundStyle(CalmStyle.secondary)
                    }
                    ForEach(section.open) { billRow($0, tag: dueText($0)) }
                    ForEach(section.recentPayments) { billRow($0, tag: "Paid " + $0.postedOn.formatted(date: .abbreviated, time: .omitted)) }
                }
                if !summary.renewals.isEmpty {
                    header("Renewals")
                    ForEach(summary.renewals) { r in
                        row(r.payee, sub: r.what, trailing: r.chargesOn.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                if !summary.accounts.isEmpty {
                    header("Accounts")
                    ForEach(summary.accounts) { n in
                        row(n.institution, sub: n.subject, trailing: n.kind.label)
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

    private func row(_ title: String, sub: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).lineLimit(1)
                Text(sub).font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(trailing).font(.subheadline).foregroundStyle(CalmStyle.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 48)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
