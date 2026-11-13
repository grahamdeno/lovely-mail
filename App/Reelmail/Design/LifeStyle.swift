import SwiftUI

/// Lovely's LifeOS look (owner, Nov 12, 2026: "steal like an artist"): a warm greige ground, light cards with a soft
/// light edge, black rounded squares for the main buttons, an orange dot, purple for done. Type is Space Grotesk
/// (SIL Open Font License, bundled in Design/Fonts). Colors live in CalmStyle; these are the shapes.
extension Font {
    /// Space Grotesk at a text style's size; scales with Dynamic Type. Falls back to the system font if missing.
    static func lovely(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(LifeFont.name(for: style == .headline && weight == .regular ? .semibold : weight),
                size: LifeFont.size(for: style), relativeTo: style)
    }

    static func lovely(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(LifeFont.name(for: weight), size: size, relativeTo: .body)
    }
}

enum LifeFont {
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .medium: return "SpaceGrotesk-Medium"
        case .semibold: return "SpaceGrotesk-SemiBold"
        case .bold, .heavy, .black: return "SpaceGrotesk-Bold"
        default: return "SpaceGrotesk-Regular"
        }
    }

    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }
}

enum LifeColor {
    /// The orange dot and the + button.
    static let orange = Color(hex: 0xE8552F)
    /// Done: the check circle, the filled drawer.
    static let purple = Color(hex: 0x3D2A73)
    /// Dashed connectors and drawer outlines.
    static let dash = Color(hex: 0x9B7FD6)
    static let black = Color(hex: 0x141414)
    static let blackEdge = Color(hex: 0x2E2E2E)
    /// The light edge around a card.
    static let cardEdge = Color(light: 0xFBF9F7, dark: 0x34313A)
}

extension View {
    /// A light card with its soft light edge.
    func lifeCard(corner: CGFloat = 18) -> some View {
        background(CalmStyle.card, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(LifeColor.cardEdge, lineWidth: 1.5))
    }

    /// A black rounded square or bar with its darker edge.
    func lifeBlack(corner: CGFloat = 16) -> some View {
        background(LifeColor.black, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(LifeColor.blackEdge, lineWidth: 2))
    }
}

/// The 52-point rounded square button: black (main action) or light.
struct LifeSquareStyle: ButtonStyle {
    var dark = true
    var size: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if dark {
                configuration.label.foregroundStyle(.white).frame(width: size, height: size).lifeBlack(corner: size * 0.31)
            } else {
                configuration.label.foregroundStyle(CalmStyle.ink).frame(width: size, height: size).lifeCard(corner: size * 0.31)
            }
        }
        .opacity(configuration.isPressed ? 0.75 : 1)
        .contentShape(Rectangle())
    }
}

/// The full-width black button ("Create automation" in LifeOS).
struct LifeBlackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.lovely(size: 17, weight: .medium)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60).lifeBlack(corner: 20)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A row card: icon, title (and detail), chevron or arrow. Used for answers, suggestions and attachments.
struct LifeRow: View {
    var icon: String
    var title: String
    var detail: String? = nil
    var trailing: String = "chevron.right"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.lovely(.body, .medium)).foregroundStyle(CalmStyle.ink).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.lovely(.callout)).foregroundStyle(CalmStyle.ink).lineLimit(2).multilineTextAlignment(.leading)
                if let detail {
                    Text(detail).font(.lovely(.footnote)).foregroundStyle(CalmStyle.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: trailing).font(.lovely(.footnote, .bold)).foregroundStyle(CalmStyle.ink)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .lifeCard(corner: 18)
        .contentShape(Rectangle())
    }
}

// MARK: Shell pieces (Nov 13, 2026: "get it closer to the LifeOS screenshots")

extension LifeColor {
    /// The gray panel inside a step card.
    static let panel = Color(light: 0xE6DFD8, dark: 0x2A2830)
    /// Dots on the sorting ground.
    static let dot = Color(light: 0xD8CDC2, dark: 0x2C2A31)
    /// LifeOS agent circles, used for people without a photo.
    static let avatars: [Color] = [Color(hex: 0x7A5BA8), Color(hex: 0xD9502E), Color(hex: 0x8D97D6), Color(hex: 0x2B2B2B), Color(hex: 0xB0703A)]
}

/// The dotted ground behind the sorting cards (the LifeOS automations canvas).
struct LifeDots: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 14
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(LifeColor.dot))
                    x += step
                }
                y += step
            }
        }
        .background(CalmStyle.pageGround)
        .accessibilityHidden(true)
    }
}

/// A sheet in the LifeOS manner: frosted greige glass, big round corners.
extension View {
    func lifeSheet() -> some View {
        presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                CalmStyle.background.opacity(0.82)
            }
        }
        .presentationCornerRadius(34)
    }
}

/// A section label above a group of rows ("Account", "App" in LifeOS settings).
struct LifeSectionLabel: View {
    let title: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.callout) }
            Text(title).font(.lovely(.callout))
        }
        .foregroundStyle(CalmStyle.secondary)
        .padding(.leading, 4).padding(.top, 10)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One grouped card of rows with hairlines between them.
struct LifeGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    row
                    if index < rows.count - 1 { Divider().overlay(CalmStyle.divider).padding(.leading, 52) }
                }
            }
        }
        .lifeCard(corner: 24)
    }
}

/// A row inside a LifeGroup: outline icon, title, value or badge, chevron.
struct LifeGroupRow: View {
    let icon: String
    let title: String
    var value: String = ""
    var badge: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.body).foregroundStyle(CalmStyle.ink).frame(width: 24)
                Text(title).font(.lovely(.body)).foregroundStyle(CalmStyle.ink)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge).font(.lovely(.footnote, .medium)).foregroundStyle(CalmStyle.ink)
                        .padding(.horizontal, 12).frame(minHeight: 30)
                        .background(CalmStyle.bubble, in: Capsule())
                } else if !value.isEmpty {
                    Text(value).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(CalmStyle.ink).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).frame(minHeight: 58).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.row." + title)
    }
}

/// The LifeOS bottom bar: a row of rounded squares, the middle one orange. Home, People, Ask, Search, Settings.
struct LifeTabBar: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 10) {
            square("house", label: "Home", on: router.tab == .home && router.path.isEmpty) { router.path = []; router.tab = .home }
            square("person.2", label: "People", on: router.tab == .people && router.path.isEmpty) { router.path = []; router.tab = .people }
            Button { router.path = []; router.tab = .home } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(LifeColor.orange, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Lovely").accessibilityIdentifier("tab.ask")
            square("magnifyingglass", label: "Search", on: router.tab == .search && router.path.isEmpty) { router.path = []; router.tab = .search }
            square("slider.horizontal.3", label: "Settings", on: router.path.last == .settings) { router.open(.settings) }
        }
    }

    private func square(_ symbol: String, label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3).foregroundStyle(CalmStyle.ink)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(on ? Color(light: 0xFFFFFF, dark: 0x3A3740) : CalmStyle.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LifeColor.cardEdge, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("tab." + label.lowercased())
    }
}

/// LifeOS headers on every pushed screen: greige bar, Space Grotesk titles, and a light rounded square for Back.
@MainActor
enum LifeNavigationLook {
    static func install() {
        let a = UINavigationBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = UIColor(CalmStyle.background)
        a.shadowColor = .clear
        let ink = UIColor(CalmStyle.ink)
        a.titleTextAttributes = [.foregroundColor: ink, .font: UIFont(name: "SpaceGrotesk-SemiBold", size: 18) ?? .systemFont(ofSize: 18, weight: .semibold)]
        a.largeTitleTextAttributes = [.foregroundColor: ink, .font: UIFont(name: "SpaceGrotesk-SemiBold", size: 34) ?? .systemFont(ofSize: 34, weight: .semibold)]
        let back = backSquare()
        a.setBackIndicatorImage(back, transitionMaskImage: back)
        let plain = UIBarButtonItemAppearance()
        plain.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        a.backButtonAppearance = plain
        let buttons = UIBarButtonItemAppearance()
        buttons.normal.titleTextAttributes = [.foregroundColor: ink, .font: UIFont(name: "SpaceGrotesk-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .medium)]
        a.buttonAppearance = buttons
        a.doneButtonAppearance = buttons
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = a
        bar.scrollEdgeAppearance = a
        bar.compactAppearance = a
        bar.tintColor = ink
    }

    /// A 44-point light rounded square with a chevron, drawn once (adapts to dark mode through the trait collection).
    static func backSquare() -> UIImage {
        let size = CGSize(width: 44, height: 44)
        let light = draw(size, fill: UIColor(red: 0.965, green: 0.949, blue: 0.933, alpha: 1), edge: UIColor(red: 0.984, green: 0.976, blue: 0.969, alpha: 1), ink: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1))
        let dark = draw(size, fill: UIColor(red: 0.16, green: 0.155, blue: 0.18, alpha: 1), edge: UIColor(red: 0.2, green: 0.19, blue: 0.23, alpha: 1), ink: .white)
        let asset = UIImageAsset()
        asset.register(light, with: UITraitCollection(userInterfaceStyle: .light))
        asset.register(dark, with: UITraitCollection(userInterfaceStyle: .dark))
        return asset.image(with: UITraitCollection.current).withRenderingMode(.alwaysOriginal)
            .withAlignmentRectInsets(UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0))
    }

    private static func draw(_ size: CGSize, fill: UIColor, edge: UIColor, ink: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 13)
            fill.setFill(); path.fill()
            edge.setStroke(); path.lineWidth = 1.5; path.stroke()
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            if let chevron = UIImage(systemName: "chevron.left", withConfiguration: config)?.withTintColor(ink, renderingMode: .alwaysOriginal) {
                chevron.draw(at: CGPoint(x: (size.width - chevron.size.width) / 2, y: (size.height - chevron.size.height) / 2))
            }
        }
    }
}

extension View {
    /// A List row as a LifeOS row card: its own light card with gaps between, no separator lines.
    func lifeListRow() -> some View {
        padding(.horizontal, 14).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lifeCard(corner: 20)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
    }
}
