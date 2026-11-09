import SwiftUI

/// Reelmail design tokens. Flat, no glow. Violet means one thing only: "needs your reply".
enum RM {
    enum Palette {
        /// Matte off-white header behind the avatar, pill, bell, search and stories.
        static let header = Color(hex: 0xF2F2F0)
        /// Cool graphite sheet the feed slides up on.
        static let sheet = Color(hex: 0x15171A)
        static let surface = Color(hex: 0x22252A)
        static let hairline = Color(hex: 0x33373D)
        static let secondary = Color(hex: 0x959BA3)
        static let ink = Color(hex: 0x15171A)
        static let white = Color.white
        /// Needs-reply only. On dark surfaces.
        static let violet = Color(hex: 0x8B7CFF)
        /// Needs-reply only. Text on light surfaces (passes 4.5:1 on white).
        static let violetOnLight = Color(hex: 0x7361E2)
    }

    /// Nested corners follow outer = inner + padding, so curves stay concentric.
    enum Radius {
        static func nested(inner: CGFloat, padding: CGFloat) -> CGFloat { inner + padding }

        static let button: CGFloat = 8
        static let cardPadding: CGFloat = 8
        /// 16 = button 8 + padding 8.
        static let card: CGFloat = nested(inner: button, padding: cardPadding)
        static let sheetPadding: CGFloat = 8
        /// 24 = card 16 + padding 8.
        static let sheet: CGFloat = nested(inner: card, padding: sheetPadding)
        static let activeTab: CGFloat = 12
        static let tabBarPadding: CGFloat = 6
        /// 18 = active tab 12 + padding 6.
        static let tabBar: CGFloat = nested(inner: activeTab, padding: tabBarPadding)
        /// Thumbnails inside list rows.
        static let thumb: CGFloat = 8

        /// Avatars are rounded squares with corners at 25% of their size.
        static func avatar(size: CGFloat) -> CGFloat { size * 0.25 }
        /// A ring drawn `gap` points outside an avatar keeps the curve concentric.
        static func avatarRing(size: CGFloat, gap: CGFloat) -> CGFloat {
            nested(inner: avatar(size: size), padding: gap)
        }
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// SF Pro (the system font) throughout.
    enum Typo {
        static func display(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .bold) }
        static let headline = Font.system(size: 22, weight: .bold)
        static let title = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
        static let callout = Font.system(size: 15, weight: .regular)
        static let caption = Font.system(size: 13, weight: .medium)
        static let micro = Font.system(size: 11, weight: .semibold)
    }
}

extension Color {
    /// A color that follows the iPhone's light or dark appearance, or the Neon or Playful theme when one is on.
    init(light: UInt32, dark: UInt32, neon: UInt32? = nil, playful: UInt32? = nil) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { traits in
            if ThemeState.neon { return ui(neon ?? dark) }
            if ThemeState.playful { return ui(playful ?? light) }
            return traits.userInterfaceStyle == .dark ? ui(dark) : ui(light)
        })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension View {
    /// A continuous rounded-rectangle clip.
    func rmCorner(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Which palette is live. Set by the app from the Appearance setting; the root view is rebuilt when it changes.
enum ThemeState {
    nonisolated(unsafe) static var neon = false
    /// Bright, rounded and bouncy: chunky buttons with a ledge under them, a rounded font, a fresh green.
    nonisolated(unsafe) static var playful = false
}
