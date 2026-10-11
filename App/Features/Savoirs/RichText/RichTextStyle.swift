import UIKit
import SwiftUI
import FlaunedexCore

/// Turns a card's semantic formatting ("bold", "red", "heading") into what a
/// text view draws (fonts, colours, indents, pictures).
///
/// Only the visual attributes are ever written here; the semantic ones from
/// `RichTextCodec` are left untouched. That is the whole trick of the editor:
/// the look can be recomputed at any time from the meaning, and the meaning is
/// what gets saved.
@MainActor
struct RichTextStyle {
    /// Body text size before Dynamic Type scaling.
    var baseSize: CGFloat = 17
    /// Centre every paragraph: used for short cards shown like flash cards.
    var centered = false
    var accent: UIColor = UIColor(Theme.knowledge)
    /// Width the text is laid out in, used to size pictures up front.
    var availableWidth: CGFloat = 320
    var maxImageHeight: CGFloat = 360
    var imageProvider: (UUID) -> UIImage? = { _ in nil }

    /// Base size scaled to the user's text-size setting.
    var scaledSize: CGFloat { UIFontMetrics(forTextStyle: .body).scaledValue(for: baseSize) }

    // MARK: Whole documents

    func attributedString(for document: RichDocument) -> NSMutableAttributedString {
        let text = NSMutableAttributedString(attributedString: RichTextCodec.attributedString(from: document))
        apply(to: text, range: NSRange(location: 0, length: text.length))
        return text
    }

    /// Recompute the visual attributes of `range` from its semantic ones.
    func apply(to text: NSMutableAttributedString, range: NSRange) {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clamped.length > 0 else { return }

        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        text.enumerateAttributes(in: clamped, options: []) { attributes, range, _ in
            runs.append((range, attributes))
        }
        for (range, attributes) in runs {
            let style = (attributes[.flParagraph] as? String).flatMap(RichParagraphStyle.init(rawValue:)) ?? .body
            let format = RichTextCodec.format(from: attributes)
            let isMarker = (attributes[.flMarker] as? Bool) == true

            text.removeAttribute(.underlineStyle, range: range)
            text.removeAttribute(.strikethroughStyle, range: range)
            text.addAttributes(visualAttributes(format: format, style: style, marker: isMarker), range: range)

            if let payload = attributes[.flImage] as? String, let image = RichTextCodec.parseImagePayload(payload) {
                if (attributes[.attachment] as? CardImageAttachment)?.imageID != image.id {
                    text.addAttribute(.attachment, value: attachment(for: image), range: range)
                }
                // A picture has its line to itself; centre it on that line.
                text.addAttribute(.paragraphStyle, value: centredPictureParagraph, range: range)
            } else if attributes[.attachment] != nil {
                text.removeAttribute(.attachment, range: range)
            }
        }
    }

    // MARK: Attributes

    func visualAttributes(format: RichFormat, style: RichParagraphStyle, marker: Bool) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(format: format, style: style),
            .foregroundColor: marker ? accent : color(format.color, style: style),
            .paragraphStyle: paragraphStyle(style),
        ]
        if format.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if format.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    /// What newly typed text carries: the meaning, for saving, and the look,
    /// for display. A link is never part of it, so typing after a link does
    /// not stretch the link over new words.
    func typingAttributes(format: RichFormat, style: RichParagraphStyle) -> [NSAttributedString.Key: Any] {
        var withoutLink = format
        withoutLink.link = nil
        var attributes = RichTextCodec.semanticAttributes(for: withoutLink)
        attributes[.flParagraph] = style.rawValue
        attributes.merge(visualAttributes(format: withoutLink, style: style, marker: false)) { _, visual in visual }
        return attributes
    }

    func font(format: RichFormat, style: RichParagraphStyle) -> UIFont {
        let size: CGFloat
        var traits: UIFontDescriptor.SymbolicTraits = []
        var rounded = false
        switch style {
        case .heading:
            size = scaledSize * 1.3
            traits.insert(.traitBold)
            rounded = true
        case .quote:
            size = scaledSize
            traits.insert(.traitItalic)
        case .body, .bullet:
            size = scaledSize
        }
        if format.bold { traits.insert(.traitBold) }
        if format.italic { traits.insert(.traitItalic) }

        var descriptor = UIFont.systemFont(ofSize: size).fontDescriptor
        if rounded, let roundedDescriptor = descriptor.withDesign(.rounded) { descriptor = roundedDescriptor }
        if !traits.isEmpty, let traited = descriptor.withSymbolicTraits(traits) { descriptor = traited }
        return UIFont(descriptor: descriptor, size: size)
    }

    func color(_ color: RichColor?, style: RichParagraphStyle) -> UIColor {
        guard let color else { return style == .quote ? .secondaryLabel : .label }
        return Self.uiColor(color)
    }

    static func uiColor(_ color: RichColor) -> UIColor {
        switch color {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }

    func paragraphStyle(_ style: RichParagraphStyle) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = centered ? .center : .natural
        paragraph.lineSpacing = 2
        switch style {
        case .body:
            paragraph.paragraphSpacing = 6
        case .heading:
            paragraph.paragraphSpacingBefore = 4
            paragraph.paragraphSpacing = 8
        case .bullet:
            // A hanging indent: the marker "•\t" sits in the margin and the
            // text, first line and wrapped lines alike, aligns on the tab stop.
            let indent = scaledSize * 1.4
            paragraph.alignment = .natural
            paragraph.tabStops = [NSTextTab(textAlignment: .natural, location: indent)]
            paragraph.defaultTabInterval = indent
            paragraph.headIndent = indent
            paragraph.paragraphSpacing = 4
        case .quote:
            paragraph.firstLineHeadIndent = 14
            paragraph.headIndent = 14
            paragraph.paragraphSpacing = 6
        }
        return paragraph
    }

    // MARK: Pictures

    var centredPictureParagraph: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        return paragraph
    }

    func attachment(for image: RichImage) -> CardImageAttachment {
        CardImageAttachment(
            imageID: image.id,
            image: imageProvider(image.id) ?? Self.placeholder,
            pixelSize: CGSize(width: image.width, height: image.height),
            availableWidth: availableWidth,
            maxHeight: maxImageHeight
        )
    }

    /// Shown while a picture's bytes are unavailable (on another device,
    /// still syncing), so its place on the card is visible rather than empty.
    static let placeholder: UIImage = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 44, weight: .light)
        return UIImage(systemName: "photo", withConfiguration: configuration)?
            .withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal) ?? UIImage()
    }()
}

/// A picture on a card, drawn at the width of the text and never beyond its
/// own resolution.
///
/// Its size is decided in two places because iOS has two text engines: TextKit
/// 2, which UITextView uses by default, asks the first method below, and
/// TextKit 1, still used in some configurations, asks the second. Both give the
/// same answer: as wide as the line allows, no wider than the picture's pixels
/// at 2x, no taller than `maxHeight`, aspect ratio kept.
final class CardImageAttachment: NSTextAttachment {
    let imageID: UUID
    private let pixelSize: CGSize
    private let maxHeight: CGFloat

    init(imageID: UUID, image: UIImage, pixelSize: CGSize, availableWidth: CGFloat, maxHeight: CGFloat) {
        self.imageID = imageID
        self.pixelSize = pixelSize
        self.maxHeight = maxHeight
        super.init(data: nil, ofType: nil)
        self.image = image
        self.bounds = fittedBounds(lineWidth: availableWidth)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        fittedBounds(lineWidth: proposedLineFragment.width)
    }

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        fittedBounds(lineWidth: lineFrag.width)
    }

    private func fittedBounds(lineWidth: CGFloat) -> CGRect {
        let aspect = pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 1
        let available = max(40, lineWidth - 12)
        var width = min(available, max(40, pixelSize.width / 2))
        var height = width / max(aspect, 0.01)
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        return CGRect(x: 0, y: 0, width: width.rounded(), height: height.rounded())
    }
}
