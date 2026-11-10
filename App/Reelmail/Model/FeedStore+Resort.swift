import Foundation

extension FeedStore {
    /// Reads the old Lovely category labels and works out where each email goes. Read-only.
    /// Money mail is opened to classify it, up to `perLabel` emails per label.
    func resortPlan(perLabel: Int = 150) async throws -> (groups: [CategoryResort.Group], truncated: Bool) {
        let settings = CategorySettings.current
        let kids = sessionKids
        var items: [CategoryResort.Item] = []
        var truncated = false
        for source in CategoryResort.sources {
            let found = try await gmail.listMessageIDs(query: CategoryResort.query(for: source.label), limit: perLabel)
            truncated = truncated || found.truncated
            if let fixed = source.to {
                let to = settings.isHidden(fixed) ? DrawerChoice(.finance) : DrawerChoice(fixed)
                items += found.ids.map { CategoryResort.Item(id: $0, from: source.label, to: to, subject: "") }
                continue
            }
            for id in found.ids {
                guard let e = try? await gmail.getMessage(id: id, account: account) else { continue }
                let health = HealthMail.isHealth(address: e.from.email, name: e.from.name, subject: e.subject) && !HealthOverrides.isNotHealth(e.from.email)
                let to = CategoryResort.target(fromAddress: e.from.email, fromName: e.from.name, subject: e.subject,
                                               text: ReplySignals.authoredText(e.body), isHealth: health, kids: kids, settings: settings)
                items.append(CategoryResort.Item(id: id, from: source.label, to: to, subject: e.subject))
            }
        }
        return (CategoryResort.groups(items), truncated)
    }

    /// Moves one group, after the 10-second Undo. Only Lovely labels change.
    func applyResort(_ group: CategoryResort.Group, confirmed: ConfirmedAction, done: @escaping @MainActor (Error?) -> Void) {
        guard let actions else { done(nil); return }
        _ = undo.enqueue(title: "Moving \(group.messageIDs.count) to \(group.to.drawer.title)", work: {
            let newID = try await actions.ensureLabel(group.to.labelName, confirmed: confirmed)
            let oldID = try await actions.existingLabelID(group.from)
            for id in group.messageIDs {
                try await actions.relabel(messageID: id, add: [newID], removeLovely: oldID.map { [$0] } ?? [], confirmed: confirmed)
            }
        }, finished: done)
    }
}
