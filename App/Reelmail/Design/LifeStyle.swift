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
