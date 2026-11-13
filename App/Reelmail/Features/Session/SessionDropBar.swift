import SwiftUI
import UIKit

// Blue bar drop (owner, Nov 13, 2026): in place of the gel ball, a thin Lovely-blue bar with no words sits on the very
// bottom of the card page. It rises as the email is pulled down, gulps the email when it is filed, and the logo's rose
// dot flies out, swings back, bounces three times on the bar and drops through it. Prototype: the design canvas,
// screen 4. The motion lives in DropFlight (Session/SessionCard.swift), pure, so it is tested.

/// Shared by the session (which draws the bar above every card) and the card page (which pulls and files).
/// Lives on the session, not the card, so the dot keeps flying while the next email comes up.
@Observable
final class SessionDropBar {
    /// 0 at rest, 1 at the put-away line (more past it), from the card's drag.
    var pull: CGFloat = 0
    /// Typing, the drawer box, Trash or the reply screen is showing.
    var hidden = false
    private(set) var gulping = false
    private(set) var flying = false

    @ObservationIgnored var flight = DropFlight()
    @ObservationIgnored var lastStep: Date?

    static let restHeight: CGFloat = DropFlight.barHeight
    static let risenHeight: CGFloat = 90

    var height: CGFloat {
        gulping ? 96 : Self.restHeight + (Self.risenHeight - Self.restHeight) * min(1, max(0, pull))
    }

    /// The email is in: the bar gulps and, unless Reduce Motion is on, the dot flies.
    func launch(reduceMotion: Bool) {
        pull = 0
        gulping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in self?.gulping = false }
        guard !reduceMotion else { return }
        flight = DropFlight()
        lastStep = nil
        flying = true
    }

    /// Called once per frame while the dot is in the air.
    func advance(to date: Date) {
        let dt = lastStep.map { date.timeIntervalSince($0) } ?? 0
        lastStep = date
        if let hit = flight.step(dt) {
            DispatchQueue.main.async { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.35 + 0.65 * hit) }
        }
        if flight.finished, flying {
            DispatchQueue.main.async { [weak self] in self?.flying = false }
        }
    }
}

/// The bar and the dot, drawn over the card page, edge to edge, never in the way of a tap.
struct SessionDropLayer: View {
    let bar: SessionDropBar
    let showBar: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                if bar.flying {
                    TimelineView(.animation) { timeline in
                        dot(at: timeline.date, in: geo.size)
                    }
                }
                // The dot is drawn behind the bar, so it lands on top of it and drops through it.
                UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous)
                    .fill(CalmStyle.blue)
                    .shadow(color: ThemeState.neon ? CalmStyle.blue.opacity(0.75) : .clear, radius: 12)
                    .shadow(color: ThemeState.neon ? CalmStyle.blue.opacity(0.35) : .clear, radius: 26)
                    .frame(height: bar.height)
                    .scaleEffect(x: bar.gulping ? 1.04 : 1, y: 1, anchor: .bottom)
                    .opacity(showBar && !bar.hidden ? 1 : 0)
                    .animation(.spring(response: 0.24, dampingFraction: 0.62), value: bar.height)
                    .animation(.easeOut(duration: 0.18), value: bar.hidden)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dot(at date: Date, in size: CGSize) -> some View {
        bar.advance(to: date)
        let f = bar.flight
        let k = size.height / DropFlight.height
        let x = size.width * f.x / DropFlight.width
        // Pinned so the floor is the top of the bar on any screen.
        let y = size.height - DropFlight.barHeight - DropFlight.radius - (DropFlight.floor - f.y) * k
        let d = DropFlight.radius * 2
        let s = f.scale
        return Circle()
            .fill(RadialGradient(colors: [Self.shine, CalmStyle.rose, Self.deep], center: UnitPoint(x: 0.35, y: 0.3),
                                 startRadius: 0, endRadius: d * 0.75))
            .frame(width: d, height: d)
            .shadow(color: Self.deep.opacity(ThemeState.neon ? 0.8 : 0.35), radius: ThemeState.neon ? 14 : 9, y: ThemeState.neon ? 0 : 6)
            .scaleEffect(x: s.x, y: s.y, anchor: .bottom)
            .opacity(f.opacity)
            .position(x: x, y: y)
    }

    private static let shine = Color(light: 0xF29AAE, dark: 0xF7B3C2, neon: 0xFF8AD0)
    private static let deep = Color(light: 0xA3384F, dark: 0xB4506A, neon: 0xB0207A)
}
