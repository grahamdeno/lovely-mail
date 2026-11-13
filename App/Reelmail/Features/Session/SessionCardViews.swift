import SwiftUI

// Sprint 8 (owner, Nov 10, 2026): the pieces of the session's card page. The gel ball (the logo's rose dot) now lives
// only on Home's Swipe to sort; on the card page the blue bar and the flying dot replaced it (Nov 13, SessionDropBar).
// The glass pane is kept for the drawer box. Brand exception: the dot is the logo's, so it is rose; rose otherwise still
// means only "waiting on you".

/// The ball's physics: a springy scale, a lean toward the thumb, and a few wobble modes that die away.
/// Settles into a still, perfect sphere. Plain class: stepped from the Canvas, never observed.
final class GelPhysics {
    struct Mode { let k: Int; var a = 0.0; var v = 0.0; var ph = 0.0 }

    var scale = 1.0, scaleV = 0.0, scaleTarget = 1.0
    var reach = 0.0, reachTarget = 0.0
    var angle = -Double.pi / 2, angleTarget = -Double.pi / 2
    var modes: [Mode] = [2, 3, 4, 5, 6, 7].map { Mode(k: $0) }
    private var last: Date?

    /// A bump. `toward` lines the splat up with where the hit came from (radians; up is -pi/2).
    func kick(_ strength: Double, toward: Double? = nil) {
        scaleV += strength * 2.4
        for i in modes.indices {
            let k = Double(modes[i].k)
            modes[i].v += (Double.random(in: 0.7...1.3)) * strength * (2 / k) * 1.9
            modes[i].ph = toward.map { -$0 * k } ?? Double.random(in: 0...(2 * .pi))
        }
    }

    func step(to date: Date) {
        let dt = min(1.0 / 30, max(0, date.timeIntervalSince(last ?? date)))
        last = date
        guard dt > 0 else { return }
        let w = 9.5, z = 0.32
        scaleV += (-w * w * (scale - scaleTarget) - 2 * z * w * scaleV) * dt
        scale += scaleV * dt
        for i in modes.indices {
            let wk = 7 + Double(modes[i].k) * 1.8, zk = 0.2
            modes[i].v += (-wk * wk * modes[i].a - 2 * zk * wk * modes[i].v) * dt
            modes[i].a += modes[i].v * dt
        }
        reach += (reachTarget - reach) * min(1, dt * 10)
        var da = angleTarget - angle
        while da > .pi { da -= 2 * .pi }
        while da < -.pi { da += 2 * .pi }
        angle += da * min(1, dt * 8)
    }

    /// Resting and round: the Canvas can stop redrawing.
    var isSettled: Bool {
        abs(scale - scaleTarget) < 0.002 && abs(scaleV) < 0.01 && abs(reach - reachTarget) < 0.002
            && modes.allSatisfy { abs($0.a) < 0.001 && abs($0.v) < 0.01 }
    }

    func path(center c: CGPoint, radius r0: Double) -> Path {
        var p = Path()
        let n = 140
        for i in 0...n {
            let th = Double(i) / Double(n) * 2 * .pi
            var r = 1.0
            for m in modes { r += m.a * cos(Double(m.k) * th + m.ph) }
            let toward = max(0, cos(th - angle))
            r += reach * 0.26 * toward * toward * toward
            r -= reach * 0.06 * max(0, -cos(th - angle))
            let rr = r0 * scale * r
            let pt = CGPoint(x: c.x + cos(th) * rr, y: c.y + sin(th) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Ball 1: the logo's rose dot as a gel ball, half off the bottom of the screen.
struct GelBall: View {
    let physics: GelPhysics
    /// Redraws only while it is moving.
    let awake: Bool
    static let radius: Double = 74
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !awake)) { timeline in
            Canvas { ctx, size in
                physics.step(to: timeline.date)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = Self.radius * physics.scale
                let shape = physics.path(center: c, radius: Self.radius)
                let dark = scheme == .dark
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 10))
                    layer.translateBy(x: 0, y: 8)
                    layer.fill(shape, with: .color(Color(hex: 0xA3384F).opacity(0.28)))
                }
                let stops = dark
                    ? [Gradient.Stop(color: Color(hex: 0xF7B3C2), location: 0), .init(color: Color(hex: 0xE77A91), location: 0.55), .init(color: Color(hex: 0xB4506A), location: 1)]
                    : [Gradient.Stop(color: Color(hex: 0xF29AAE), location: 0), .init(color: Color(hex: 0xD2546E), location: 0.55), .init(color: Color(hex: 0xA3384F), location: 1)]
                ctx.fill(shape, with: .radialGradient(Gradient(stops: stops), center: CGPoint(x: c.x - r * 0.24, y: c.y - r * 0.4),
                                                      startRadius: 0, endRadius: r * 1.5))
                let m2 = physics.modes[0].a
                let shine = CGRect(x: c.x - r * 0.34 + cos(physics.angle) * physics.reach * 10 - 22 * physics.scale * (1 + m2),
                                   y: c.y - r * 0.42 + m2 * 30 - 12 * physics.scale * (1 - m2),
                                   width: 44 * physics.scale * (1 + m2), height: 24 * physics.scale * (1 - m2))
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.55)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Pane 2: a thick lens of glass. Liquid Glass underneath, a light rim that is brightest where the thumb is,
/// a faint cool and warm fringe at the sides, and a soft lift off the page.
struct GlassPane: ViewModifier {
    /// 0...1 across the screen: where the light catches the rim.
    var light: CGFloat = 0.3
    var corner: CGFloat = 32
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let dark = scheme == .dark
        content
            .background(
                LinearGradient(colors: [Color.white.opacity(dark ? 0.12 : 0.55), Color.white.opacity(dark ? 0.03 : 0.22)],
                               startPoint: .top, endPoint: .bottom), in: shape)
            .glassEffect(.regular, in: shape)
            .overlay(
                shape.strokeBorder(
                    AngularGradient(stops: [.init(color: .white, location: 0), .init(color: .white.opacity(0.15), location: 0.22),
                                            .init(color: .white.opacity(0.55), location: 0.48), .init(color: .white.opacity(0.12), location: 0.74),
                                            .init(color: .white, location: 1)],
                                    center: UnitPoint(x: light, y: 0)),
                    lineWidth: 1.5)
                .opacity(dark ? 0.35 : 1)
            )
            .overlay(
                shape.inset(by: 0.75).stroke(
                    LinearGradient(colors: [Color(hex: 0x8CA5FF).opacity(0.28), .clear, .clear, Color(hex: 0xFF8CA5).opacity(0.28)],
                                   startPoint: .leading, endPoint: .trailing), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x25222A).opacity(dark ? 0.5 : 0.14), radius: 22, x: 0, y: 18)
            .shadow(color: Color(hex: 0x25222A).opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

extension View {
    func glassPane(light: CGFloat = 0.3, corner: CGFloat = 32) -> some View { modifier(GlassPane(light: light, corner: corner)) }
}

extension CalmStyle {
    /// What shows behind a session page while it moves.
    static let pageGround = Color(light: 0xF2E1E5, dark: 0x0B0A0D, neon: 0x0B0A0D)
    /// Card 1: the session page itself.
    static let page = Color(light: 0xFBF3F5, dark: 0x141317, neon: 0x121116)
}

/// The email's own words on the card page (owner, Nov 13, 2026): a thin rule at the left marks them as the sender's,
/// not Lovely's summary. They take whatever room is left on the page and fade out at the bottom; a tap on the page opens
/// the whole email in the quick look.
struct SessionExcerpt: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Capsule().fill(CalmStyle.divider).frame(width: 3) }
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("From the email: \(text)")
    }
}
