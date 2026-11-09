import SwiftUI

/// Shown while Lovely opens, until it knows whether your Gmail or sample mail goes on screen, so the sample
/// "Connect Gmail" page never flashes for someone who is signed in. The icon's l and dot, the wordmark and the line.
struct LaunchSplash: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(CalmStyle.card)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                Image("BrandL").resizable().scaledToFit().foregroundStyle(CalmStyle.blue)
                Image("BrandDot").resizable().scaledToFit().foregroundStyle(CalmStyle.rose)
            }
            .frame(width: 128, height: 128)
            .accessibilityHidden(true)
            Wordmark(size: 40)
            Text("Mail from your people.").font(.callout).foregroundStyle(CalmStyle.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CalmStyle.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lovely. Mail from your people. Opening.")
    }
}
