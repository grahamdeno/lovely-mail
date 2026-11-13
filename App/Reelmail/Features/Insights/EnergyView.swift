import SwiftUI

/// One quiet row on Home that opens the Energy page. Shown once an energy report has been read.
struct EnergyRow: View {
    @Environment(Router.self) private var router
    let summary: EnergySummary
    var body: some View {
        Button { router.open(.energy) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Energy").font(.lovely(.subheadline, .medium)).foregroundStyle(CalmStyle.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.secondary)
                }
                Text(summary.headline).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityIdentifier("home.row.energy")
    }
}

/// What your energy and water mail says, in one place. Everything here was read from mail on this phone.
struct EnergyView: View {
    @Environment(FeedStore.self) private var store

    var body: some View {
        let summary = EnergyInsights.summary(store.insights.store, household: nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary.headline).font(.lovely(.title3, .semibold))
                if let suggestion = summary.suggestion {
                    ProfileCard(title: "This month", value: "One thing to try", detail: suggestion)
                }
                if let alert = summary.costToDate {
                    ProfileCard(title: "This billing cycle so far", value: String(format: "$%.2f", alert.costToDate),
                                detail: "As of \(alert.asOf.formatted(date: .abbreviated, time: .omitted)).")
                }
                if summary.months.count > 1 { MonthBars(months: summary.months) }
                if let latest = summary.latest, !latest.devices.isEmpty {
                    Text("LAST MONTH BY DEVICE").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                    ForEach(latest.devices.sorted { $0.dollars > $1.dollars }, id: \.name) { d in
                        HStack { Text(d.name); Spacer(); Text(String(format: "$%.2f", d.dollars)).foregroundStyle(CalmStyle.secondary) }
                            .padding(.horizontal, 14).frame(minHeight: 44).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                if !summary.water.isEmpty {
                    Text("WATER AND SEWER").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                    ForEach(summary.water) { b in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(b.payee)
                                Text(b.postedOn.formatted(date: .abbreviated, time: .omitted)).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                            }
                            Spacer()
                            if let a = b.amount { Text(String(format: "$%.2f", a)).foregroundStyle(CalmStyle.secondary) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                if store.insights.store.energy.isEmpty {
                    Text(store.insights.isRunning ? "Reading your last 12 months of mail." : "No energy report has been found in your last 12 months of mail.")
                        .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
                }
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Energy").navigationBarTitleDisplayMode(.inline)
        .askBubble(.energy)
    }
}

/// Dollars a day, one bar a month.
private struct MonthBars: View {
    let months: [EnergyMonth]
    var body: some View {
        let top = max(months.map(\.dollarsPerDay).max() ?? 1, 0.01)
        VStack(alignment: .leading, spacing: 8) {
            Text("DOLLARS A DAY").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(months) { m in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(CalmStyle.blue).frame(height: max(4, 90 * m.dollarsPerDay / top))
                        Text(m.month.formatted(.dateTime.month(.narrow))).font(.lovely(.caption2)).foregroundStyle(CalmStyle.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 120, alignment: .bottom)
        }
        .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dollars a day by month, from \(String(format: "$%.2f", months.first?.dollarsPerDay ?? 0)) to \(String(format: "$%.2f", months.last?.dollarsPerDay ?? 0))")
    }
}
