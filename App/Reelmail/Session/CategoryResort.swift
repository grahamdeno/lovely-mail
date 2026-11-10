import Foundation

/// The one-time move from the first fixed categories (Lovely/Money, Kids, Orders, Personal) to the owner's new
/// ones (Nov 9). Kids, Orders and Personal map one to one; Money is split by what each email covers, so home
/// insurance goes to Home and a car loan to Auto. Pure, so it is tested; FeedStore runs it against Gmail.
enum CategoryResort {
    /// Old label, and where all of it goes (nil: decide per email).
    static let sources: [(label: String, to: Drawer?)] = [
        ("Lovely/Money", nil), ("Lovely/Kids", .family), ("Lovely/Orders", .shopping), ("Lovely/Personal", .community),
    ]

    struct Group: Identifiable, Equatable {
        var from: String
        var to: DrawerChoice
        var messageIDs: [String]
        /// A few subjects, so the owner can see what is moving.
        var examples: [String]
        var id: String { from + ">" + to.labelName }
        /// "Money › Home"
        var title: String { from.replacingOccurrences(of: Drawer.parent + "/", with: "") + " \u{203A} " + to.drawer.title }
    }

    struct Item: Equatable {
        var id: String
        var from: String
        var to: DrawerChoice
        var subject: String
    }

    /// Where one email from Lovely/Money goes: the rule guess, or Finance when the rules are unsure or pick a
    /// hidden category.
    static func target(fromAddress: String, fromName: String, subject: String, text: String, isHealth: Bool,
                       kids: [KidProfile], settings: CategorySettings) -> DrawerChoice {
        let input = DrawerGuesser.Input(fromAddress: fromAddress, fromName: fromName, subject: subject, text: text,
                                        category: .money, isPerson: false, isHealth: isHealth)
        if let g = DrawerGuesser.guess(input, kids: kids, settings: settings) { return DrawerChoice(g.choice.drawer) }
        return DrawerChoice(settings.isHidden(.finance) ? (settings.visible.first ?? .finance) : .finance)
    }

    /// Groups by old label and new category, biggest first. Mail whose new label is the same as its old one stays.
    static func groups(_ items: [Item]) -> [Group] {
        var out: [String: Group] = [:]
        for i in items where i.to.labelName != i.from {
            let key = i.from + ">" + i.to.labelName
            var g = out[key] ?? Group(from: i.from, to: i.to, messageIDs: [], examples: [])
            g.messageIDs.append(i.id)
            if g.examples.count < 3, !i.subject.isEmpty { g.examples.append(i.subject) }
            out[key] = g
        }
        return out.values.sorted { $0.messageIDs.count != $1.messageIDs.count ? $0.messageIDs.count > $1.messageIDs.count : $0.id < $1.id }
    }

    /// Gmail's search name for a label: "Lovely/Money" is label:lovely-money.
    static func query(for label: String) -> String {
        "label:" + label.lowercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
    }

    static func preview(_ g: Group) -> ActionPreview {
        var lines = ["Adds \(g.to.labelName) and removes \(g.from) on \(g.messageIDs.count) email\(g.messageIDs.count == 1 ? "" : "s")."]
        lines += g.examples.map { "\u{2022} " + $0 }
        lines.append("Only Lovely labels change. Nothing is deleted, and nothing leaves the inbox.")
        return ActionPreview(kind: .label, title: "Move to \(g.to.drawer.title)", lines: lines)
    }
}
