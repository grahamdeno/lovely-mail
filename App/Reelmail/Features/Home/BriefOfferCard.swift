import SwiftUI

/// One-time card at the bottom of Home after the first Done. Either choice hides it for good.
struct BriefOfferCard: View {
    @Environment(FeedStore.self) private var store
    @AppStorage(BriefSettings.offerSeenKey) private var seen = false
    @AppStorage(BriefSettings.enabledKey) private var enabled = false
    @State private var declined = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Want a short morning brief? Counts only, at 7:30.").font(.lovely(.subheadline, .medium))
            if declined {
                Text("Notifications are off for Lovely. Turn them on in the Settings app.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            HStack(spacing: 8) {
                Button("Turn on") {
                    Task {
                        let granted = await MorningBriefScheduler.requestPermission()
                        enabled = granted
                        if granted { seen = true; await MorningBriefScheduler.reschedule(store: store) } else { declined = true }
                    }
                }
                .buttonStyle(CalmActionStyle(prominent: true))
                Button("No thanks") { seen = true }
                    .buttonStyle(CalmActionStyle())
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
