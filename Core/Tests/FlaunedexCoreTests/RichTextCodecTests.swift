import Testing
import Foundation
@testable import FlaunedexCore

/// The codec is the bridge between what the text view edits and what is
/// stored. If it loses a bold word or a picture on the way back, the card is
/// silently damaged at every save, so the contract is checked on hand-written
/// documents and on hundreds of random ones.
struct RichTextCodecTests {

    private func roundTrip(_ doc: RichDocument) -> RichDocument {
        RichTextCodec.document(from: RichTextCodec.attributedString(from: doc))
    }

    private func paragraph(_ style: RichParagraphStyle = .body, _ runs: RichRun...) -> RichBlock {
        .paragraph(RichParagraph(style: style, runs: runs))
    }

    // MARK: The contract

    @Test func everyFeatureSurvivesTheRoundTrip() {
        let doc = RichDocument(blocks: [
            paragraph(.heading, RichRun(text: "Je pense, donc je suis.", format: RichFormat(bold: true))),
            paragraph(.body, RichRun(text: "René Descartes", format: RichFormat(italic: true, color: .purple)),
                      RichRun(text: ", "),
                      RichRun(text: "Discours de la méthode", format: RichFormat(underline: true,
                                                                                    link: "https://fr.wikipedia.org/wiki/Discours_de_la_m%C3%A9thode"))),
            paragraph(.bullet, RichRun(text: "1637", format: RichFormat(strikethrough: true))),
            paragraph(.bullet),
            paragraph(.quote, RichRun(text: "Cogito ergo sum")),
            .image(RichImage(id: UUID(), width: 800, height: 600)),
            .image(RichImage(id: UUID(), width: 300, height: 900)),
            paragraph(.body, RichRun(text: "Fin 🎓")),
        ])
        #expect(roundTrip(doc) == doc.normalized())
    }

    @Test func fourHundredRandomDocumentsSurviveTheRoundTrip() {
        var generator = SeededGenerator(seed: 1637)
        for trial in 0..<400 {
            let doc = randomDocument(using: &generator)
            let back = roundTrip(doc)
            #expect(back == doc.normalized(), "trial \(trial)")
            if back != doc.normalized() { break }
        }
    }

    @Test func theEmptyDocumentIsAnEmptyString() {
        #expect(RichTextCodec.attributedString(from: .empty).length == 0)
        #expect(roundTrip(.empty) == .empty)
    }

    // MARK: Layout of the attributed string

    @Test func bulletsGetAMarkerThatIsNeverSavedAsText() {
        let doc = RichDocument(blocks: [paragraph(.bullet, RichRun(text: "Lire"))])
        let attributed = RichTextCodec.attributedString(from: doc)
        #expect(attributed.string == "•\tLire")
        #expect((attributed.attribute(.flMarker, at: 0, effectiveRange: nil) as? Bool) == true)
        #expect(roundTrip(doc).plainText == "Lire")
    }

    @Test func aBulletTypedByHandIsJustText() {
        // "•\t" without the marker key was typed or pasted: it is content.
        let typed = NSAttributedString(string: "•\tpas une puce")
        #expect(RichTextCodec.document(from: typed).plainText == "•\tpas une puce")
    }

    @Test func anEmptyParagraphKeepsItsStyleThroughItsLineBreak() {
        let doc = RichDocument(blocks: [
            paragraph(.body, RichRun(text: "avant")),
            paragraph(.quote),
            paragraph(.body, RichRun(text: "après")),
        ])
        #expect(roundTrip(doc) == doc)
    }

    @Test func picturesUseTheReplacementCharacterWithTheirPayload() throws {
        let id = UUID()
        let attributed = RichTextCodec.attributedString(from: RichDocument(blocks: [.image(RichImage(id: id, width: 640, height: 480))]))
        #expect(attributed.string == "\u{FFFC}")
        let payload = try #require(attributed.attribute(.flImage, at: 0, effectiveRange: nil) as? String)
        #expect(RichTextCodec.parseImagePayload(payload) == RichImage(id: id, width: 640, height: 480))
    }

    // MARK: Whatever the text view hands back

    @Test func aPictureInsideALineSplitsTheLine() {
        let id = UUID()
        let text = NSMutableAttributedString(string: "avant", attributes: [.flParagraph: "heading"])
        text.append(NSAttributedString(string: "\u{FFFC}", attributes: [
            .flParagraph: "heading", .flImage: RichTextCodec.imagePayload(RichImage(id: id, width: 4, height: 3)),
        ]))
        text.append(NSAttributedString(string: "après", attributes: [.flParagraph: "heading"]))
        #expect(RichTextCodec.document(from: text).blocks == [
            paragraph(.heading, RichRun(text: "avant")),
            .image(RichImage(id: id, width: 4, height: 3)),
            paragraph(.heading, RichRun(text: "après")),
        ])
    }

    @Test func aForeignAttachmentWithoutPayloadIsDropped() {
        let pasted = NSAttributedString(string: "a\u{FFFC}b")
        #expect(RichTextCodec.document(from: pasted).blocks == [paragraph(.body, RichRun(text: "ab"))])
    }

    @Test func foreignFormattingIsIgnoredOnlySemanticKeysCount() {
        let pasted = NSMutableAttributedString(string: "gras")
        pasted.addAttribute(NSAttributedString.Key("NSFont"), value: "Helvetica-Bold 30", range: NSRange(location: 0, length: 4))
        pasted.addAttribute(NSAttributedString.Key("NSColor"), value: "rgb(255,0,0)", range: NSRange(location: 0, length: 4))
        #expect(RichTextCodec.document(from: pasted).blocks == [paragraph(.body, RichRun(text: "gras"))])
    }

    @Test func plainTextBecomesBodyParagraphs() {
        let pasted = NSAttributedString(string: "Titre\r\nLigne\u{2029}Autre")
        let doc = RichTextCodec.document(from: pasted)
        #expect(doc.blocks == [
            paragraph(.body, RichRun(text: "Titre")),
            paragraph(.body, RichRun(text: "Ligne")),
            paragraph(.body, RichRun(text: "Autre")),
        ])
    }

    @Test func semanticValuesUseFoundationTypes() {
        let attributes = RichTextCodec.semanticAttributes(for: RichFormat(bold: true, color: .green, link: "https://example.com"))
        #expect((attributes[.flBold] as? Bool) == true)
        #expect((attributes[.flColor] as? String) == "green")
        #expect((attributes[.flLink] as? URL)?.absoluteString == "https://example.com")
        #expect(RichTextCodec.format(from: attributes) == RichFormat(bold: true, color: .green, link: "https://example.com"))
    }

    @Test func aLinkStoredAsTextIsReadToo() {
        let format = RichTextCodec.format(from: [.flLink: "www.larousse.fr"])
        #expect(format.link == "https://www.larousse.fr")
    }

    @Test func malformedPayloadsAreRejected() {
        #expect(RichTextCodec.parseImagePayload("") == nil)
        #expect(RichTextCodec.parseImagePayload("pas-un-uuid|1|1") == nil)
        #expect(RichTextCodec.parseImagePayload("\(UUID().uuidString)|large|1") == nil)
        #expect(RichTextCodec.parseImagePayload("\(UUID().uuidString)|1") == nil)
    }

    // MARK: Random documents

    private static let alphabet: [Character] = Array("abcdeèéàç ZÉ'«»,.!?-•\t😀🇫🇷\n")
    private static let links = [
        "https://fr.wikipedia.org/wiki/Horace",
        "mailto:taddeo@example.com",
        "https://www.larousse.fr/dictionnaires/francais/aubaine/6358",
    ]

    private func randomDocument(using generator: inout SeededGenerator) -> RichDocument {
        var blocks: [RichBlock] = []
        for _ in 0..<Int.random(in: 0...7, using: &generator) {
            if Int.random(in: 0..<5, using: &generator) == 0 {
                blocks.append(.image(RichImage(id: UUID(),
                                               width: Double(Int.random(in: 1...4000, using: &generator)),
                                               height: Double(Int.random(in: 1...4000, using: &generator)))))
                continue
            }
            let style = RichParagraphStyle.allCases.randomElement(using: &generator)!
            var runs: [RichRun] = []
            for _ in 0..<Int.random(in: 0...4, using: &generator) {
                let length = Int.random(in: 0...12, using: &generator)
                let text = String((0..<length).map { _ in Self.alphabet.randomElement(using: &generator)! })
                let format = RichFormat(
                    bold: Bool.random(using: &generator),
                    italic: Bool.random(using: &generator),
                    underline: Int.random(in: 0..<4, using: &generator) == 0,
                    strikethrough: Int.random(in: 0..<6, using: &generator) == 0,
                    color: Bool.random(using: &generator) ? RichColor.allCases.randomElement(using: &generator) : nil,
                    link: Int.random(in: 0..<5, using: &generator) == 0 ? Self.links.randomElement(using: &generator) : nil
                )
                runs.append(RichRun(text: text, format: format))
            }
            blocks.append(.paragraph(RichParagraph(style: style, runs: runs)))
        }
        return RichDocument(blocks: blocks)
    }
}

/// Replacing text must not strip formatting. Found in the simulator: tapping
/// into a card made autocorrection re-insert the word under the cursor as plain
/// text, and saving would have erased the bold. The editor now records the
/// replaced text's format and puts it back with `setFormat`.
struct ReplacementFormatTests {

    @Test func setFormatRestoresTheReplacedTextsFormat() {
        // What autocorrection leaves behind: "le " bold, "lendemain" plain.
        let text = NSMutableAttributedString(string: "le ", attributes: [.flBold: true, .flParagraph: "body"])
        text.append(NSAttributedString(string: "lendemain", attributes: [.flParagraph: "body"]))
        RichTextCodec.setFormat(RichFormat(bold: true), in: text, range: NSRange(location: 3, length: 9))
        #expect(RichTextCodec.document(from: text).blocks
                == [.paragraph(RichParagraph(style: .body, runs: [RichRun(text: "le lendemain", format: RichFormat(bold: true))]))])
    }

    @Test func setFormatReplacesRatherThanAdds() {
        let text = NSMutableAttributedString(string: "mot", attributes: [
            .flItalic: true, .flColor: "red", .flParagraph: "heading",
        ])
        RichTextCodec.setFormat(RichFormat(bold: true), in: text, range: NSRange(location: 0, length: 3))
        let attributes = text.attributes(at: 0, effectiveRange: nil)
        #expect(RichTextCodec.format(from: attributes) == RichFormat(bold: true), "italic and red are gone")
        #expect(attributes[.flParagraph] as? String == "heading", "paragraph structure is untouched")
    }

    @Test func setFormatLeavesTheRestOfTheTextAlone() {
        let text = NSMutableAttributedString(string: "abc", attributes: [.flItalic: true])
        RichTextCodec.setFormat(.plain, in: text, range: NSRange(location: 1, length: 1))
        #expect((text.attribute(.flItalic, at: 0, effectiveRange: nil) as? Bool) == true)
        #expect(text.attribute(.flItalic, at: 1, effectiveRange: nil) == nil)
        #expect((text.attribute(.flItalic, at: 2, effectiveRange: nil) as? Bool) == true)
    }

    @Test func aRangePastTheEndIsClampedNotACrash() {
        let text = NSMutableAttributedString(string: "ab")
        RichTextCodec.setFormat(RichFormat(bold: true), in: text, range: NSRange(location: 1, length: 50))
        #expect((text.attribute(.flBold, at: 1, effectiveRange: nil) as? Bool) == true)
        RichTextCodec.setFormat(RichFormat(bold: true), in: text, range: NSRange(location: 9, length: 3))
    }
}
