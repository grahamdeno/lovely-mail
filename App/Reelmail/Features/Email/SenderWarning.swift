import SwiftUI

extension FeedStore {
    /// Who this sender really is, checked on the phone. Your own mail and people you write to are not checked for lookalikes.
    func senderVerdict(_ email: Email) -> SenderCheck.Verdict {
        let addr = email.from.email.lowercased()
        let mine = Set(([account ?? ""] + otherAddresses).map { $0.lowercased() })
        if email.isFromMe || mine.contains(addr) { return .ok }
        let known = sentByMe.contains { sent in sent.recipients.contains { $0.lowercased() == addr } }
        return SenderCheck.check(name: email.from.name, address: addr, replyTo: email.replyTo, authResults: email.authResults, known: known)
    }
}

/// The warning on an email whose sender may not be who they say. Shown on the email and in the inbox session.
struct SenderWarning: View {
    let verdict: SenderCheck.Verdict
    var compact = false

    var body: some View {
        if verdict.level != .ok {
            let strong = verdict.level == .warning
            VStack(alignment: .leading, spacing: 6) {
                Label(verdict.title, systemImage: strong ? "exclamationmark.shield.fill" : "questionmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array((compact ? Array(verdict.reasons.prefix(1)) : verdict.reasons).enumerated()), id: \.offset) { _, reason in
                    Text(reason).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                if !compact {
                    Text(strong ? "Don't tap links, open attachments or reply until you are sure. You can move it to Trash."
                                : "If you weren't expecting it, check before you tap any links.")
                        .font(.caption)
                }
            }
            .foregroundStyle(strong ? CalmStyle.roseInk : CalmStyle.warningInk)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(strong ? CalmStyle.roseInk.opacity(0.12) : CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sender.warning")
        }
    }
}
