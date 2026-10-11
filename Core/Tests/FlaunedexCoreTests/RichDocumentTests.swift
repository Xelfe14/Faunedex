import Testing
import Foundation
@testable import FlaunedexCore

struct RichDocumentTests {

    private func paragraph(_ style: RichParagraphStyle = .body, _ runs: RichRun...) -> RichBlock {
        .paragraph(RichParagraph(style: style, runs: runs))
    }

    private let bold = RichFormat(bold: true)
    private let italic = RichFormat(italic: true)

    // MARK: Normal form

    @Test func neighboursWithTheSameFormatMerge() {
        let doc = RichDocument(blocks: [paragraph(.body,
            RichRun(text: "Bon", format: bold),
            RichRun(text: "jour", format: bold),
            RichRun(text: "", format: italic),
            RichRun(text: " !"))])
        #expect(doc.normalized().blocks == [paragraph(.body, RichRun(text: "Bonjour", format: bold), RichRun(text: " !"))])
    }

    @Test func aLineBreakInsideARunSplitsTheParagraphKeepingItsStyle() {
        let doc = RichDocument(blocks: [paragraph(.heading, RichRun(text: "Titre\nSuite", format: bold))])
        #expect(doc.normalized().blocks == [
            paragraph(.heading, RichRun(text: "Titre", format: bold)),
            paragraph(.heading, RichRun(text: "Suite", format: bold)),
        ])
    }

    @Test func windowsAndUnicodeLineBreaksAreParagraphBreaksToo() {
        let doc = RichDocument(plainText: "un\r\ndeux\u{2028}trois\rquatre")
        #expect(doc.plainText == "un\ndeux\ntrois\nquatre")
        #expect(doc.blocks.count == 4)
    }

    @Test func pictureMarkersNeverSurviveInsideText() {
        let doc = RichDocument(blocks: [paragraph(.body, RichRun(text: "a\u{FFFC}b"))])
        #expect(doc.normalized().plainText == "ab")
    }

    @Test func oneEmptyParagraphIsTheEmptyDocument() {
        #expect(RichDocument(blocks: [paragraph()]).normalized() == .empty)
        #expect(RichDocument(plainText: "").blocks.isEmpty)
    }

    @Test func anEmptyLastHeadingBecomesBodyButAnEmptyBulletStays() {
        let heading = RichDocument(blocks: [paragraph(.body, RichRun(text: "a")), paragraph(.heading)]).normalized()
        #expect(heading.blocks.last == paragraph(.body))
        let bullet = RichDocument(blocks: [paragraph(.body, RichRun(text: "a")), paragraph(.bullet)]).normalized()
        #expect(bullet.blocks.last == paragraph(.bullet), "the bullet marker itself carries the style")
    }

    @Test func invalidLinksAreDroppedButTheirTextKept() {
        let doc = RichDocument(blocks: [paragraph(.body, RichRun(text: "clic", format: RichFormat(link: "javascript:alert(1)")))])
        #expect(doc.normalized().blocks == [paragraph(.body, RichRun(text: "clic"))])
    }

    @Test func pictureSizesBecomeWholePositivePixels() {
        let id = UUID()
        let doc = RichDocument(blocks: [.image(RichImage(id: id, width: 1234.6, height: 0))]).normalized()
        #expect(doc.blocks == [.image(RichImage(id: id, width: 1235, height: 1))])
    }

    @Test func trimmingRemovesBlankEndsButKeepsInnerSpacing() {
        let doc = RichDocument(blocks: [
            paragraph(), paragraph(.body, RichRun(text: "a")), paragraph(),
            paragraph(.body, RichRun(text: "b")), paragraph(.body, RichRun(text: "   ")),
        ])
        #expect(doc.trimmed().blocks == [
            paragraph(.body, RichRun(text: "a")), paragraph(), paragraph(.body, RichRun(text: "b")),
        ])
    }

    // MARK: Reading

    @Test func readingHelpers() {
        let picture = UUID()
        let doc = RichDocument(blocks: [
            paragraph(), .image(RichImage(id: picture, width: 10, height: 5)),
            paragraph(.heading, RichRun(text: "  Carpe diem ", format: bold)),
            paragraph(.body, RichRun(text: "Horace")),
            .image(RichImage(id: picture, width: 10, height: 5)),
        ])
        #expect(doc.plainText == "\n  Carpe diem \nHorace")
        #expect(doc.previewLine == "Carpe diem", "blank lines and pictures are skipped")
        #expect(doc.imageIDs == [picture], "a picture used twice is listed once")
        #expect(!doc.isBlank)
        #expect(RichDocument(blocks: [paragraph(.body, RichRun(text: "  "))]).isBlank)
        #expect(!RichDocument(blocks: [.image(RichImage(id: picture, width: 1, height: 1))]).isBlank)
    }

    @Test func shortCardsAreCentredLongOnesAreNot() {
        #expect(RichDocument(plainText: "la bouilloire").isShort)
        #expect(!RichDocument(plainText: String(repeating: "mot ", count: 50)).isShort)
        #expect(!RichDocument(blocks: [paragraph(.bullet, RichRun(text: "un"))]).isShort, "a list reads as a page")
    }

    // MARK: Storage

    @Test func aDocumentSurvivesStorage() throws {
        let doc = RichDocument(blocks: [
            paragraph(.heading, RichRun(text: "Prise de la Bastille", format: bold)),
            paragraph(.body, RichRun(text: "Le "), RichRun(text: "14 juillet 1789", format: RichFormat(bold: true, color: .red)),
                      RichRun(text: ", à Paris.")),
            paragraph(.quote, RichRun(text: "« Non, Sire, c'est une révolution. »", format: italic)),
            paragraph(.bullet, RichRun(text: "Voir", format: RichFormat(underline: true, strikethrough: true,
                                                                          link: "https://fr.wikipedia.org/wiki/Prise_de_la_Bastille"))),
            .image(RichImage(id: UUID(), width: 1600, height: 1200)),
            paragraph(.body, RichRun(text: "Émoji 🇫🇷 et accents")),
        ])
        let decoded = try #require(RichDocument.from(jsonData: try doc.jsonData()))
        #expect(decoded == doc)
    }

    @Test func storageWritesOnlyWhatIsSet() throws {
        let json = String(decoding: try RichDocument(plainText: "simple").jsonData(), as: UTF8.self)
        #expect(!json.contains("false"))
        #expect(json.contains("\"version\":1"))
        #expect(json.contains("\"text\":\"simple\""))
    }

    @Test func equalDocumentsStoreIdenticalBytes() throws {
        let doc = RichDocument(blocks: [paragraph(.body, RichRun(text: "x", format: RichFormat(bold: true, italic: true, color: .blue)))])
        #expect(try doc.jsonData() == doc.jsonData())
    }

    @Test func aDocumentFromALaterVersionStillOpens() throws {
        let json = """
        {"version": 9, "blocks": [
          {"type": "table", "rows": 3},
          {"type": "paragraph", "style": "callout", "runs": [{"text": "ok", "color": "teal", "glow": true}]}
        ]}
        """
        let doc = try #require(RichDocument.from(jsonData: Data(json.utf8)))
        #expect(doc.blocks == [paragraph(), paragraph(.body, RichRun(text: "ok"))],
                "unknown block, style, colour and field all degrade instead of failing")
    }

    @Test func unreadableStorageIsAbsentNotACrash() {
        #expect(RichDocument.from(jsonData: nil) == nil)
        #expect(RichDocument.from(jsonData: Data()) == nil)
        #expect(RichDocument.from(jsonData: Data("pas du json".utf8)) == nil)
    }
}

struct RichLinkTests {

    @Test func absoluteWebAddressesAreKept() {
        #expect(RichLink.normalized("https://fr.wikipedia.org/wiki/Horace") == "https://fr.wikipedia.org/wiki/Horace")
        #expect(RichLink.normalized("  http://example.com/a?b=1  ") == "http://example.com/a?b=1")
    }

    @Test func typedAddressesGainHTTPS() {
        #expect(RichLink.normalized("www.larousse.fr") == "https://www.larousse.fr")
        #expect(RichLink.normalized("fr.wikipedia.org/wiki/Paris") == "https://fr.wikipedia.org/wiki/Paris")
        #expect(RichLink.normalized("example.com:8080/x") == "https://example.com:8080/x")
    }

    @Test func mailAndPhoneAreLinksToo() {
        #expect(RichLink.normalized("mailto:taddeo@example.com") == "mailto:taddeo@example.com")
        #expect(RichLink.normalized("tel:+33612345678") == "tel:+33612345678")
        #expect(RichLink.normalized("mailto:") == nil)
    }

    @Test func dangerousOrMeaninglessInputIsRefused() {
        #expect(RichLink.normalized("javascript:alert(1)") == nil)
        #expect(RichLink.normalized("file:///etc/passwd") == nil)
        #expect(RichLink.normalized("ftp://example.com") == nil)
        #expect(RichLink.normalized("bonjour") == nil)
        #expect(RichLink.normalized("deux mots.fr") == nil)
        #expect(RichLink.normalized("https://") == nil)
        #expect(RichLink.normalized("") == nil)
    }

    @Test func normalisingTwiceChangesNothing() {
        for raw in ["www.larousse.fr", "https://fr.wikipedia.org/wiki/Horace", "tel:+33612345678", "example.com:8080/x"] {
            let once = RichLink.normalized(raw)
            #expect(once.flatMap(RichLink.normalized) == once, "\(raw)")
        }
    }
}
