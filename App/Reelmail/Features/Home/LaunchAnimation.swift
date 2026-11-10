import SwiftUI

/// The opening animation (cold start only): the l writes itself in one stroke, the pen lifts and the dot hops off
/// the end, lands with a rubbery squash and settles, then "lovely" and the line fade in. About 1.8 seconds, tap to skip.
/// Picks up exactly where the iPhone's still launch screen (LaunchMark) leaves off. Off with Reduce Motion, and in
/// Settings > Appearance > Opening animation. Everything is in this file, so it is easy to remove.
struct LaunchAnimation: View {
    static let settingKey = "lovely.launchAnimation"
    static var isOn: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    let finished: () -> Void
    @State private var trim: CGFloat = 0
    @State private var dotVisible = false
    @State private var dotAt: CGPoint = Mark.strokeEnd
    @State private var squash = CGSize(width: 1, height: 1)
    @State private var words = false
    @State private var done = false

    private let size: CGFloat = 160

    var body: some View {
        ZStack {
            CalmStyle.background.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack(alignment: .topLeading) {
                    Mark.lPath(in: size).trim(from: 0, to: trim)
                        .stroke(CalmStyle.blue, style: StrokeStyle(lineWidth: Mark.strokeWidth(in: size), lineCap: .round, lineJoin: .round))
                    let r = Mark.dotRadius(in: size)
                    Circle().fill(CalmStyle.rose)
                        .frame(width: r * 2, height: r * 2)
                        .scaleEffect(squash, anchor: .bottom)
                        .position(Mark.point(dotAt, in: size))
                        .opacity(dotVisible ? 1 : 0)
                }
                .frame(width: size, height: size)
                VStack(spacing: 8) {
                    Wordmark(size: 40)
                    Text("Get through your email.").font(.callout).foregroundStyle(CalmStyle.secondary)
                }
                .opacity(words ? 1 : 0).offset(y: words ? 0 : 8)
            }
        }
        .opacity(done ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lovely. Get through your email.")
        .task { await play() }
    }

    private func play() async {
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        withAnimation(.easeInOut(duration: 0.7)) { trim = 1 }
        await wait(0.66)
        // The pen lifts: the dot hops up off the end of the stroke...
        dotVisible = true
        withAnimation(.easeOut(duration: 0.24)) { dotAt = Mark.apex }
        await wait(0.24)
        // ...and falls to its place.
        withAnimation(.easeIn(duration: 0.2)) { dotAt = Mark.dotCenter }
        await wait(0.2)
        // Lands: squash, then a rubbery wobble that slows and settles.
        withAnimation(.linear(duration: 0.06)) { squash = CGSize(width: 1.5, height: 0.58) }
        await wait(0.06)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.28)) { squash = CGSize(width: 1, height: 1) }
        await wait(0.2)
        withAnimation(.easeOut(duration: 0.4)) { words = true }
        await wait(0.75)
        finish()
    }

    private func finish() {
        guard !done else { return }
        withAnimation(.easeOut(duration: 0.3)) { done = true }
        Task { try? await Task.sleep(for: .seconds(0.3)); finished() }
    }

    /// The icon's l and dot, from Design/Brand/icon-layer-l.svg and icon-layer-dot.svg (100-unit space, the icon's
    /// scale 1.1 about the center), cropped the same way as LaunchMark so the hand-off from the launch screen is seamless.
    enum Mark {
        static let cropOrigin: CGFloat = 150.0 / 10.24     // 14.65 units
        static let cropSize: CGFloat = 724.0 / 10.24       // 70.7 units
        static func icon(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (x - 50.5) * 1.1 + 50, y: (y - 49.5) * 1.1 + 50)
        }
        static func point(_ p: CGPoint, in size: CGFloat) -> CGPoint {
            CGPoint(x: (p.x - cropOrigin) / cropSize * size, y: (p.y - cropOrigin) / cropSize * size)
        }
        static func strokeWidth(in size: CGFloat) -> CGFloat { 7.5 * 1.1 / cropSize * size }
        static func dotRadius(in size: CGFloat) -> CGFloat { 4.8 * 1.1 / cropSize * size }

        static let strokeEnd = icon(66, 71)
        static let dotCenter = icon(74, 64)
        /// Up and between the end of the stroke and the dot's place.
        static let apex = CGPoint(x: (icon(66, 71).x + icon(74, 64).x) / 2, y: icon(74, 64).y - 22)

        /// M27 72 C38 70 56 55 59 38 C61 26 52 20 46 27 C39 35 41 58 46 68 C49 75 57 77 66 71
        static func lPath(in size: CGFloat) -> Path {
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { point(icon(x, y), in: size) }
            var path = Path()
            path.move(to: p(27, 72))
            path.addCurve(to: p(59, 38), control1: p(38, 70), control2: p(56, 55))
            path.addCurve(to: p(46, 27), control1: p(61, 26), control2: p(52, 20))
            path.addCurve(to: p(46, 68), control1: p(39, 35), control2: p(41, 58))
            path.addCurve(to: p(66, 71), control1: p(49, 75), control2: p(57, 77))
            return path
        }
    }
}
