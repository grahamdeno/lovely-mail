import SwiftUI

/// The one place a ConfirmedAction is made. Nothing is sent, forwarded, filtered or deleted until Confirm is tapped here.
struct ActionPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: ActionPreview
    var confirmTitle = "Confirm"
    /// Red confirm button for deletes, declines and Trash.
    var destructive = false
    let onConfirm: (ConfirmedAction) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(preview.title).font(.title3.weight(.semibold))
                    ForEach(preview.lines, id: \.self) { Text($0).font(.body) }
                    if !preview.recipients.isEmpty {
                        Text("TO").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary).padding(.top, 6)
                        ForEach(preview.recipients, id: \.self) { Text($0).font(.body.weight(.medium)) }
                    }
                    Text("Nothing happens until you tap \(confirmTitle).").font(.caption).foregroundStyle(CalmStyle.secondary).padding(.top, 6)
                    Button(confirmTitle, role: destructive ? .destructive : nil) {
                        onConfirm(ConfirmedAction(preview: preview))
                        dismiss()
                    }.buttonStyle(CalmActionStyle(prominent: true)).accessibilityIdentifier("preview.confirm")
                    Button("Cancel") { dismiss() }.buttonStyle(CalmActionStyle()).accessibilityIdentifier("preview.cancel")
                }.padding(20)
            }
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// A countdown banner for held sends and forwards, with Undo.
struct UndoBanner: View {
    @Environment(FeedStore.self) private var store
    /// In the inbox session only the newest one shows, so the bar never covers the session's buttons.
    var limit: Int? = nil
    var body: some View {
        let all = store.undo.pending
        let shown = limit.map { Array(all.suffix($0)) } ?? all
        let hiddenCount = all.count - shown.count
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(shown) { item in
                // Full bar for the first 3 seconds, then a small pill with a countdown ring: the 10-second window stays,
                // but it stops covering the screen.
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    let left = max(0, item.sendsAt.timeIntervalSince(context.date))
                    let total = max(store.undo.delay, 1)
                    if total - left < UndoBanner.fullFor {
                        fullBar(item, hiddenCount: item.id == shown.last?.id ? hiddenCount : 0)
                    } else {
                        pill(item, fraction: left / total)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.undo.pending)
    }

    /// How long the full bar shows before it shrinks to the pill.
    static let fullFor: TimeInterval = 3

    private func fullBar(_ item: UndoQueue.Pending, hiddenCount: Int) -> some View {
        // Solid blue with a shadow so it stands out from cards behind it (it floats over the session screen).
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill").font(.title3).accessibilityHidden(true)
            Text(item.title + (hiddenCount > 0 ? " (+\(hiddenCount) more)" : "")).font(.subheadline.weight(.medium)).lineLimit(2)
            Spacer(minLength: 8)
            Button { store.undo.cancel(item.id) } label: {
                Text("Undo").font(.subheadline.weight(.bold)).padding(.horizontal, 14).frame(minHeight: 36)
                    .foregroundStyle(CalmStyle.blue).background(CalmStyle.onBlue, in: Capsule())
            }
            .buttonStyle(.plain).frame(minHeight: 44).accessibilityIdentifier("undo.banner")
        }
        .foregroundStyle(CalmStyle.onBlue)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(CalmStyle.blue, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .transition(.opacity)
    }

    private func pill(_ item: UndoQueue.Pending, fraction: Double) -> some View {
        Button { store.undo.cancel(item.id) } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(CalmStyle.onBlue.opacity(0.3), lineWidth: 3)
                    Circle().trim(from: 0, to: fraction).stroke(CalmStyle.onBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
                Text("Undo").font(.subheadline.weight(.bold))
            }
            .foregroundStyle(CalmStyle.onBlue)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(CalmStyle.blue, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo: " + item.title)
        .accessibilityIdentifier("undo.banner")
        .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
    }
}
