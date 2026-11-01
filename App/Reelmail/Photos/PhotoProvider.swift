import SwiftUI

/// Art for a post: a flat gradient and an SF Symbol. No glow.
struct PostArt: Hashable {
    let top: Color
    let bottom: Color
    let symbol: String
}

/// Where post photos come from.
protocol PhotoProvider {
    func art(for summary: EmailSummary, seed: String) -> PostArt
}

/// Local placeholder art per category, so nothing about an email leaves the phone.
///
/// TODO: Real photos from a stock image source, searched by `summary.imageQuery`
/// (generic 2-4 words, never names). The API key must come from the gitignored
/// Config/Local.xcconfig, never the repo, and sensitive posts should keep placeholders.
struct PlaceholderPhotoProvider: PhotoProvider {
    func art(for summary: EmailSummary, seed: String) -> PostArt {
        let (a, b) = Self.palette(summary.category)
        // Small, stable per-post variation so a run of same-category posts doesn't look identical.
        let shift = Double(abs(seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % 7) / 100
        return PostArt(top: Color(hue: a.h + shift, saturation: a.s, brightness: a.b),
                       bottom: Color(hue: b.h + shift, saturation: b.s, brightness: b.b),
                       symbol: summary.sensitive ? "lock.fill" : summary.category.symbol)
    }

    private typealias HSB = (h: Double, s: Double, b: Double)

    private static func palette(_ c: PostCategory) -> (HSB, HSB) {
        switch c {
        case .people: return ((0.03, 0.30, 0.78), (0.08, 0.18, 0.92))
        case .school: return ((0.58, 0.28, 0.70), (0.55, 0.14, 0.90))
        case .work: return ((0.60, 0.12, 0.55), (0.60, 0.06, 0.85))
        case .money: return ((0.36, 0.22, 0.62), (0.30, 0.10, 0.88))
        case .travel: return ((0.55, 0.35, 0.72), (0.12, 0.20, 0.95))
        case .events: return ((0.30, 0.30, 0.60), (0.20, 0.18, 0.90))
        case .newsletter: return ((0.08, 0.25, 0.75), (0.10, 0.10, 0.95))
        case .updates: return ((0.62, 0.08, 0.60), (0.62, 0.04, 0.88))
        }
    }
}
