import SwiftUI
import UIKit

/// Lets a list be pulled down (to refresh) but not pushed up past its end. When Home fits on the screen, an
/// upward swipe used to slide everything under the top bar and bounce back, which read as a bug (Nov 9).
/// Place it as the background of a row; it finds the list's scroll view and holds the bottom edge in place.
struct PullDownOnly: UIViewRepresentable {
    func makeUIView(context: Context) -> Finder { Finder() }
    func updateUIView(_ view: Finder, context: Context) {}

    final class Finder: UIView {
        private var watch: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, watch == nil else { return }
            var next = superview
            while let view = next, !(view is UIScrollView) { next = view.superview }
            guard let scroll = next as? UIScrollView else { return }
            isUserInteractionEnabled = false
            watch = scroll.observe(\.contentOffset, options: [.new]) { scroll, _ in
                MainActor.assumeIsolated { PullDownOnly.hold(scroll) }
            }
        }
    }

    /// The furthest the list may scroll down: the end of its content, or its resting place when it all fits.
    @MainActor static func hold(_ scroll: UIScrollView) {
        let inset = scroll.adjustedContentInset
        let maxY = max(-inset.top, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        if scroll.contentOffset.y > maxY + 0.5 { scroll.contentOffset.y = maxY }
    }
}
