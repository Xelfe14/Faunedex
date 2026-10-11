import Foundation

/// Attribute keys that carry a card's formatting inside an attributed string.
///
/// They record meaning ("bold", "heading paragraph"), not appearance. The app
/// derives fonts and colours from them for display, but only these keys are
/// read back when a card is saved. That split is what makes the round trip
/// exact: the look can be restyled freely without ever leaking into the data.
///
/// Computed rather than stored so they carry no global state, which Swift 6's
/// concurrency checking would otherwise have to vet.
public extension NSAttributedString.Key {
    static var flBold: NSAttributedString.Key { .init("fl.bold") }
    static var flItalic: NSAttributedString.Key { .init("fl.italic") }
    static var flUnderline: NSAttributedString.Key { .init("fl.underline") }
    static var flStrikethrough: NSAttributedString.Key { .init("fl.strikethrough") }
    static var flColor: NSAttributedString.Key { .init("fl.color") }
    /// The paragraph's style name, on every character of the paragraph
    /// including its closing line break.
    static var flParagraph: NSAttributedString.Key { .init("fl.paragraph") }
    /// On a picture's placeholder character: "identifier|width|height".
    static var flImage: NSAttributedString.Key { .init("fl.image") }
    /// On a list bullet's own characters, which are decoration and never text.
    static var flMarker: NSAttributedString.Key { .init("fl.marker") }
    /// A link. This is the very key UIKit and AppKit call `.link` (raw value
    /// "NSLink", verified), declared here because plain Foundation does not
    /// name it and this package imports neither UI framework. Text views treat
    /// it as the standard link attribute.
    static var flLink: NSAttributedString.Key { .init("NSLink") }
}

/// Converts between `RichDocument` and an attributed string carrying the
/// semantic keys above.
///
/// The attributed string is the form a text view edits; the document is the
/// form stored. The contract, tested on hundreds of random documents, is that
/// `document(from: attributedString(from: d)) == d.normalized()`.
///
/// Layout of the attributed string, for a document of three blocks
/// (a bullet "Lire", a picture, a heading "Fin"):
///
///     "•\t" "Lire" "\n" "\u{FFFC}" "\n" "Fin"
///      marker text  sep  picture   sep  text
///
/// Every block is one paragraph, separated by "\n". A bullet paragraph starts
/// with its marker characters. A picture is the object-replacement character.
public enum RichTextCodec {

    /// What a bullet paragraph starts with. Marked with `.flMarker`, so it is
    /// shown but never saved as text.
    public static let bulletMarker = "•\t"

    /// The character a text view stores where a picture sits.
    public static let objectReplacement = "\u{FFFC}"

    // MARK: Document to attributed string

    public static func attributedString(from document: RichDocument) -> NSAttributedString {
        let doc = document.normalized()
        let out = NSMutableAttributedString()

        for (index, block) in doc.blocks.enumerated() {
            let style: RichParagraphStyle
            switch block {
            case .paragraph(let paragraph):
                style = paragraph.style
                if paragraph.style == .bullet {
                    var markerAttributes = paragraphAttributes(.bullet)
                    markerAttributes[.flMarker] = true
                    out.append(NSAttributedString(string: bulletMarker, attributes: markerAttributes))
                }
                for run in paragraph.runs {
                    var attributes = semanticAttributes(for: run.format)
                    attributes[.flParagraph] = paragraph.style.rawValue
                    out.append(NSAttributedString(string: run.text, attributes: attributes))
                }
            case .image(let image):
                style = .body
                var attributes = paragraphAttributes(.body)
                attributes[.flImage] = imagePayload(image)
                out.append(NSAttributedString(string: objectReplacement, attributes: attributes))
            }
            if index < doc.blocks.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: paragraphAttributes(style)))
            }
        }
        return out
    }

    /// The semantic keys for a text format.
    public static func semanticAttributes(for format: RichFormat) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if format.bold { attributes[.flBold] = true }
        if format.italic { attributes[.flItalic] = true }
        if format.underline { attributes[.flUnderline] = true }
        if format.strikethrough { attributes[.flStrikethrough] = true }
        if let color = format.color { attributes[.flColor] = color.rawValue }
        if let link = format.link, let url = URL(string: link) { attributes[.flLink] = url }
        return attributes
    }

    public static func paragraphAttributes(_ style: RichParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.flParagraph: style.rawValue]
    }

    // MARK: Attributed string to document

    /// Read a document back out of an attributed string.
    ///
    /// Total by design: any attributed string gives a document, whatever was
    /// pasted or typed. Anything without the semantic keys (foreign fonts,
    /// colours, sizes) is plain text; a picture placeholder without a payload
    /// is dropped; a picture in the middle of a line becomes its own block,
    /// splitting the line around it.
    public static func document(from attributed: NSAttributedString) -> RichDocument {
        let string = attributed.string as NSString
        var blocks: [RichBlock] = []

        for paragraph in paragraphRanges(in: string) {
            let style = paragraphStyle(in: attributed, content: paragraph.content, separator: paragraph.separator)
            var runs: [RichRun] = []
            var emitted = false

            if paragraph.content.length > 0 {
                attributed.enumerateAttributes(in: paragraph.content, options: []) { attributes, range, _ in
                    if (attributes[.flMarker] as? Bool) == true { return }
                    let text = string.substring(with: range)

                    if let payload = attributes[.flImage] as? String, let image = parseImagePayload(payload) {
                        var pending = ""
                        for character in text {
                            if String(character) == objectReplacement {
                                if !pending.isEmpty {
                                    runs.append(RichRun(text: pending, format: format(from: attributes)))
                                    pending = ""
                                }
                                if !runs.isEmpty {
                                    blocks.append(.paragraph(RichParagraph(style: style, runs: runs)))
                                    runs = []
                                }
                                blocks.append(.image(image))
                                emitted = true
                            } else {
                                pending.append(character)
                            }
                        }
                        if !pending.isEmpty { runs.append(RichRun(text: pending, format: format(from: attributes))) }
                        return
                    }

                    let clean = text.replacingOccurrences(of: objectReplacement, with: "")
                    if !clean.isEmpty { runs.append(RichRun(text: clean, format: format(from: attributes))) }
                }
            }

            if !runs.isEmpty || !emitted {
                blocks.append(.paragraph(RichParagraph(style: style, runs: runs)))
            }
        }
        return RichDocument(blocks: blocks).normalized()
    }

    /// The text format recorded by the semantic keys, ignoring everything else.
    public static func format(from attributes: [NSAttributedString.Key: Any]) -> RichFormat {
        RichFormat(
            bold: (attributes[.flBold] as? Bool) ?? false,
            italic: (attributes[.flItalic] as? Bool) ?? false,
            underline: (attributes[.flUnderline] as? Bool) ?? false,
            strikethrough: (attributes[.flStrikethrough] as? Bool) ?? false,
            color: (attributes[.flColor] as? String).flatMap(RichColor.init(rawValue:)),
            link: linkString(attributes[.flLink])
        )
    }

    static func linkString(_ value: Any?) -> String? {
        if let url = value as? URL { return RichLink.normalized(url.absoluteString) }
        if let text = value as? String { return RichLink.normalized(text) }
        return nil
    }

    /// The inline keys, the ones a format controls. Paragraph style, picture
    /// and bullet keys are structure and never belong to a format.
    public static var inlineKeys: [NSAttributedString.Key] {
        [.flBold, .flItalic, .flUnderline, .flStrikethrough, .flColor, .flLink]
    }

    /// Give `range` exactly `format`, replacing whatever inline format it had.
    ///
    /// Used when the text system replaces a stretch of text (autocorrection
    /// re-inserting the word under the cursor, a text-replacement shortcut,
    /// Writing Tools rewriting a sentence): those paths insert plain text and
    /// ignore the typing format, so the replaced text's format is recorded
    /// beforehand and put back with this. Word processors behave the same way:
    /// text that replaces other text takes that text's formatting.
    public static func setFormat(_ format: RichFormat, in text: NSMutableAttributedString, range: NSRange) {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clamped.length > 0 else { return }
        for key in inlineKeys { text.removeAttribute(key, range: clamped) }
        text.addAttributes(semanticAttributes(for: format), range: clamped)
    }

    // MARK: Pictures

    public static func imagePayload(_ image: RichImage) -> String {
        "\(image.id.uuidString)|\(Int(image.width.rounded()))|\(Int(image.height.rounded()))"
    }

    public static func parseImagePayload(_ payload: String) -> RichImage? {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let id = UUID(uuidString: String(parts[0])),
              let width = Double(parts[1]),
              let height = Double(parts[2]) else { return nil }
        return RichImage(id: id, width: width, height: height)
    }

    // MARK: Paragraph scanning

    struct ParagraphRange {
        let content: NSRange
        /// The line break that ends the paragraph; nil for the last one.
        let separator: NSRange?
    }

    /// Split on every paragraph separator, counting "\r\n" as one, in UTF-16
    /// offsets because that is how attributed-string ranges are measured.
    static func paragraphRanges(in string: NSString) -> [ParagraphRange] {
        var ranges: [ParagraphRange] = []
        var start = 0
        var index = 0
        let length = string.length
        while index < length {
            let unit = string.character(at: index)
            if unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029 {
                var separatorLength = 1
                if unit == 0x0D, index + 1 < length, string.character(at: index + 1) == 0x0A {
                    separatorLength = 2
                }
                ranges.append(ParagraphRange(
                    content: NSRange(location: start, length: index - start),
                    separator: NSRange(location: index, length: separatorLength)
                ))
                index += separatorLength
                start = index
            } else {
                index += 1
            }
        }
        ranges.append(ParagraphRange(content: NSRange(location: start, length: length - start), separator: nil))
        return ranges
    }

    /// A paragraph's style is read from its first character, or, for an empty
    /// paragraph, from the line break that ends it. An empty last paragraph has
    /// neither and is body, which the document's normal form also enforces.
    static func paragraphStyle(in attributed: NSAttributedString, content: NSRange, separator: NSRange?) -> RichParagraphStyle {
        let location: Int?
        if content.length > 0 {
            location = content.location
        } else {
            location = separator?.location
        }
        guard let location, location < attributed.length,
              let raw = attributed.attribute(.flParagraph, at: location, effectiveRange: nil) as? String else {
            return .body
        }
        return RichParagraphStyle(rawValue: raw) ?? .body
    }
}
