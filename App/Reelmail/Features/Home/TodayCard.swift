import SwiftUI

/// The top of Home: today's brief and the inbox session in one card. What's waiting, what's coming up,
/// and one button. Tap the heading for the full brief.
struct TodayCard: View {
    @Environment(Router.self) private var router
    let toGoThrough: Int
    let waiting: Int
    let thisWeek: Int
    /// No new mail, but older read mail is still in the inbox.
    let older: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { router.open(.brief) } label: {
                HStack {
                    Text("Today").font(.lovely(.title3, .bold)).foregroundStyle(CalmStyle.ink)
                    Spacer()
                    Text("Brief").font(.lovely(.subheadline, .medium)).foregroundStyle(CalmStyle.blue)
                    Image(systemName: "chevron.right").font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.blue)
                }
                .frame(minHeight: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("home.brief")
            Text(summary).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if toGoThrough > 0 || older > 0 {
                Button(toGoThrough > 0 ? "Go through your inbox" : "Clear older mail") {
                    router.open(toGoThrough > 0 ? .session : .backlog)
                }
                .buttonStyle(SessionButtonStyle())
                .accessibilityIdentifier("home.session")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    var summary: String { Self.summary(toGoThrough: toGoThrough, waiting: waiting, thisWeek: thisWeek, older: older) }

    static func summary(toGoThrough: Int, waiting: Int, thisWeek: Int, older: Int) -> String {
        var parts: [String] = []
        if toGoThrough > 0 { parts.append("\(toGoThrough) to go through") }
        if waiting > 0 { parts.append("\(waiting) waiting on you") }
        if thisWeek > 0 { parts.append(thisWeek == 1 ? "1 date this week" : "\(thisWeek) dates this week") }
        if parts.isEmpty { return older > 0 ? "All caught up. \(older) read email\(older == 1 ? "" : "s") still in your inbox." : "All caught up." }
        return parts.joined(separator: " · ")
    }
}

/// Kids, Energy and Money as three small tiles on one line.
struct InsightTiles: View {
    @Environment(Router.self) private var router
    let kids: String?
    let energy: String?
    let money: String?

    var body: some View {
        HStack(spacing: 8) {
            if let kids { tile("Kids", kids, .kids).accessibilityIdentifier("home.row.kids") }
            if let energy { tile("Energy", energy, .energy).accessibilityIdentifier("home.row.energy") }
            if let money { tile("Money", money, .money).accessibilityIdentifier("home.row.money") }
        }
    }

    private func tile(_ title: String, _ detail: String, _ route: Route) -> some View {
        Button { router.open(route) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.lovely(.subheadline, .semibold)).foregroundStyle(CalmStyle.ink)
                Text(detail).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(2).minimumScaleFactor(0.85)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
