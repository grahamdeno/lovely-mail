import SwiftUI

/// Home round 5: "Also", a short paragraph of what's worth knowing. Named words open their page.
struct HomeAlsoView: View {
    @Environment(Router.self) private var router
    let sentences: [[HomeAlso.Part]]

    var body: some View {
        if !sentences.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ALSO").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                Text(attributed)
                    .font(.body).lineSpacing(4).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == Self.scheme, let link = HomeAlso.Link(rawValue: url.host() ?? "") else { return .systemAction }
                        router.open(Self.route(link))
                        return .handled
                    })
                    .accessibilityIdentifier("home.also")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static let scheme = "lovely-home"

    private var attributed: AttributedString {
        var out = AttributedString()
        for (n, sentence) in sentences.enumerated() {
            if n > 0 { out += AttributedString(" ") }
            for part in sentence {
                var piece = AttributedString(part.text)
                if let link = part.link, let url = URL(string: "\(Self.scheme)://\(link.rawValue)") {
                    piece.link = url
                    piece.font = .body.weight(.medium)
                }
                out += piece
            }
        }
        return out
    }

    static func route(_ link: HomeAlso.Link) -> Route {
        switch link {
        case .kids: return .kids
        case .money: return .money
        case .energy: return .energy
        case .later: return .later
        case .todo: return .mailList("todo")
        case .notes: return .notes
        case .promises: return .promises
        case .waitingOnThem: return .waitingOnThem
        case .comingUp: return .comingUp
        }
    }
}

/// The shortcuts that used to be Home chips: shown above the ask field while it is empty and focused, or as a
/// quiet row at the bottom of Home when the split pill is off.
enum HomeShortcuts {
    struct Item: Identifiable { var title: String; var symbol: String; var route: Route; var id: String { title } }

    @MainActor static func items(hasKids: Bool) -> [Item] {
        var out = [Item(title: "Events from a photo", symbol: "camera", route: .photoEvents),
                   Item(title: "Money", symbol: "creditcard", route: .money)]
        if hasKids { out.append(Item(title: "Kids", symbol: "graduationcap", route: .kids)) }
        out += [Item(title: "Energy", symbol: "bolt", route: .energy),
                Item(title: "Coming up", symbol: "calendar", route: .comingUp),
                Item(title: "Later", symbol: "clock", route: .later)]
        return out
    }
}

struct ShortcutRow: View {
    @Environment(Router.self) private var router
    let items: [HomeShortcuts.Item]
    var picked: () -> Void = {}
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button { picked(); router.open(item.route) } label: {
                        Label(item.title, systemImage: item.symbol).font(.subheadline).foregroundStyle(CalmStyle.ink)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: SplitPillBar.corner, style: .continuous).strokeBorder(CalmStyle.divider))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityIdentifier("home.shortcuts")
    }
}
