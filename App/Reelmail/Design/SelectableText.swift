import SwiftUI
import UIKit

/// Email text you can select part of and whose links open on a tap. SwiftUI's `.textSelection(.enabled)` only
/// copies the whole Text, with no handles (Nov 9), so this wraps a read-only UITextView: drag the handles to pick
/// a few words, tap a link to open it, long-press a link for Copy Link.
struct SelectableText: UIViewRepresentable {
    let text: AttributedString
    var style: UIFont.TextStyle = .body
    var color: Color = CalmStyle.ink
    var linkColor: Color = CalmStyle.blue

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = []          // links come from EmailPresentation.linked, found on the phone
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "email.body"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let body = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let all = NSRange(location: 0, length: body.length)
        body.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: style), range: all)
        body.addAttribute(.foregroundColor, value: UIColor(color), range: all)
        if !view.attributedText.isEqual(to: body) { view.attributedText = body }
        view.linkTextAttributes = [.foregroundColor: UIColor(linkColor)]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }
}
