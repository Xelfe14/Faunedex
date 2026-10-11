import SwiftUI
import UIKit
import FlaunedexCore

/// One side of a card, read-only, as shown in a revision session.
///
/// A tap anywhere turns the card over, except on a link, which opens. That is
/// why the view handles taps itself instead of letting UITextView do it: a
/// selectable text view would swallow the tap meant for the card.
struct RichTextDisplay: UIViewRepresentable {
    let document: RichDocument
    var style: RichTextStyle
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> CardFaceTextView {
        CardFaceTextView()
    }

    func updateUIView(_ view: CardFaceTextView, context: Context) {
        view.onTap = onTap
        view.linkTextAttributes = [
            .foregroundColor: style.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        if view.shownDocument != document || view.shownCentered != style.centered {
            view.shownDocument = document
            view.shownCentered = style.centered
            view.attributedText = style.attributedString(for: document)
            view.setNeedsLayout()
        }
    }
}

/// A non-editable text view that centres short content vertically, like the
/// word in the middle of a flash card, and scrolls long content normally.
final class CardFaceTextView: UITextView {
    var shownDocument: RichDocument?
    var shownCentered = false
    var onTap: (() -> Void)?

    private let edge: CGFloat = 18

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = false
        isScrollEnabled = true
        backgroundColor = .clear
        showsVerticalScrollIndicator = true
        textContainerInset = UIEdgeInsets(top: edge, left: 14, bottom: edge, right: 14)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        centreVertically()
    }

    /// Push the text down so it sits in the middle when it is shorter than the
    /// card. Only changes the inset when the value really moves, so setting it
    /// (which triggers another layout) cannot loop.
    private func centreVertically() {
        guard bounds.width > 0 else { return }
        let fitting = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height
        let content = fitting - textContainerInset.top - textContainerInset.bottom
        let top = max(edge, ((bounds.height - content) / 2).rounded())
        if abs(textContainerInset.top - top) > 0.5 {
            textContainerInset.top = top
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let url = link(at: point) {
            UIApplication.shared.open(url)
        } else {
            onTap?()
        }
    }

    /// The link under the finger, if the finger really is on it: the nearest
    /// character is checked against its drawn rectangle, so a tap in the empty
    /// space beside a link turns the card instead of opening the link.
    private func link(at point: CGPoint) -> URL? {
        guard let position = closestPosition(to: point) else { return nil }
        let offset = self.offset(from: beginningOfDocument, to: position)
        for index in [offset, offset - 1] where index >= 0 && index < textStorage.length {
            guard let value = textStorage.attribute(.flLink, at: index, effectiveRange: nil),
                  let start = self.position(from: beginningOfDocument, offset: index),
                  let end = self.position(from: start, offset: 1),
                  let range = textRange(from: start, to: end) else { continue }
            if firstRect(for: range).insetBy(dx: -8, dy: -8).contains(point) {
                return (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            }
        }
        return nil
    }
}
