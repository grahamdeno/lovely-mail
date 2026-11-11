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
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 54)
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
    /// No new mail, but older read mail is still in the inbox.
    var backlog = false

    var body: some View {
        Button { router.open(backlog ? .backlog : .session) } label: {
            HStack(spacing: 14) {
                Image(systemName: "tray.full").font(.title3.weight(.semibold)).foregroundStyle(CalmStyle.onBlue)
                    .frame(width: 44, height: 44).background(CalmStyle.blue, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(backlog ? "Clear older mail" : "Go through your inbox").font(.headline).foregroundStyle(CalmStyle.ink)
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
        if backlog { return count == 1 ? "1 read email still in your inbox" : "\(count) read emails still in your inbox" }
        let base = count == 1 ? "1 to go through" : "\(count) to go through"
        return waiting > 0 ? base + " · \(waiting) waiting on you" : base
    }
}

/// A session confirm with its own look: a drawer row in the drawer box, a word beside the ball. Like
/// SessionConfirmButton, the label and the lines around it are the preview, so one tap confirms it.
struct SessionConfirmTap<Content: View>: View {
    let previews: [ActionPreview]
    var identifier = "session.confirm"
    let onConfirm: ([ConfirmedAction]) -> Void
    @ViewBuilder let label: () -> Content

    var body: some View {
        Button { onConfirm(previews.map { ConfirmedAction(preview: $0) }) } label: { label() }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
    }
}

/// Pulling a session email down past the line into the ball files it, as if its main button were tapped.
/// Owner approved Nov 10, 2026 (docs/sprint8-swipe.md, CLAUDE.md): only after the destination ("Put away in Finance")
/// was shown on screen during the pull, only filing (put away, archive), with the 10-second Undo. Never Trash, send
/// or rules by gesture.
enum SessionPull {
    static func approvals(for previews: [ActionPreview]) -> [ConfirmedAction] {
        previews.map { ConfirmedAction(preview: $0) }
    }
}
