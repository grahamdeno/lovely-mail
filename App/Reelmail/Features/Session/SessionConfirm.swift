import SwiftUI

/// The inbox session's action button. It is the preview: its label and the lines around it say exactly what will happen
/// (which messages, which drawer, who receives a reply), so one tap confirms it. Owner approved Nov 8, 2026 (Sprint 7).
/// This and ActionPreviewSheet are the only places a ConfirmedAction is made; scripts/privacy_guard.py checks it.
struct SessionConfirmButton: View {
    let title: String
    let previews: [ActionPreview]
    var prominent = true
    var enabled = true
    var identifier = "session.confirm"
    let onConfirm: ([ConfirmedAction]) -> Void

    var body: some View {
        Button {
            onConfirm(previews.map { ConfirmedAction(preview: $0) })
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(SessionButtonStyle(prominent: prominent))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(identifier)
    }
}

/// Big, thumb-sized buttons for the session: one primary per screen.
struct SessionButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(2).multilineTextAlignment(.center)
            .padding(.horizontal, 16).frame(minHeight: 54)
            .foregroundStyle(prominent ? CalmStyle.onBlue : CalmStyle.blue)
            .background(prominent ? CalmStyle.blue : CalmStyle.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// The way into a session, at the top of Home. One tap.
struct SessionStartCard: View {
    @Environment(Router.self) private var router
    let count: Int
    let waiting: Int

    var body: some View {
        Button { router.open(.session) } label: {
            HStack(spacing: 14) {
                Image(systemName: "tray.full").font(.title3.weight(.semibold)).foregroundStyle(CalmStyle.onBlue)
                    .frame(width: 44, height: 44).background(CalmStyle.blue, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go through your inbox").font(.headline).foregroundStyle(CalmStyle.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(CalmStyle.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.session")
        .accessibilityHint("Starts an inbox session")
    }

    private var subtitle: String {
        let base = count == 1 ? "1 to go through" : "\(count) to go through"
        return waiting > 0 ? base + " · \(waiting) waiting on you" : base
    }
}
