import Foundation

/// One side of a knowledge card: formatted text and pictures, like an email.
///
/// The document is a list of blocks. A block is either a paragraph (a style
/// plus runs of formatted text) or a picture. Formatting is semantic, "bold" or
/// "red", never "Helvetica 17 pt" or an RGB value, so it renders correctly in
/// dark mode and in any future design, and so the stored form is small, stable,
/// readable JSON that this package can test without UIKit.
///
/// A picture is only a reference here (an identifier and a pixel size). Its
/// bytes live in their own record beside the card: iCloud caps a record at
/// 1 MB, and keeping pictures out of the text keeps every card far below it.
public struct RichDocument: Sendable, Equatable {
    public var blocks: [RichBlock]

    public init(blocks: [RichBlock] = []) {
        self.blocks = blocks
    }

    public static let empty = RichDocument()

    /// Plain text as body paragraphs, one per line.
    public init(plainText: String) {
        let lines = RichDocument.splitParagraphs(plainText)
        self.blocks = lines.map { .paragraph(RichParagraph(style: .body, runs: [RichRun(text: $0)])) }
        self = normalized()
    }

    /// Version written into every stored document, so a later format can be
    /// told apart from this one.
    public static let currentVersion = 1
}

// MARK: - Blocks, paragraphs, runs

public enum RichBlock: Sendable, Equatable {
    case paragraph(RichParagraph)
    case image(RichImage)
}

public enum RichParagraphStyle: String, Sendable, CaseIterable {
    case body
    case heading
    case bullet
    case quote
}

public struct RichParagraph: Sendable, Equatable {
    public var style: RichParagraphStyle
    public var runs: [RichRun]

    public init(style: RichParagraphStyle = .body, runs: [RichRun] = []) {
        self.style = style
        self.runs = runs
    }

    public var text: String { runs.map(\.text).joined() }
}

/// The small, closed palette a card can use. Names, not colours: the app maps
/// each name to a tint that works in both light and dark mode.
public enum RichColor: String, Sendable, CaseIterable {
    case red, orange, green, blue, purple, gray
}

/// How a stretch of text looks. Two runs with equal formats are merged.
public struct RichFormat: Sendable, Equatable, Hashable {
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var color: RichColor?
    /// An absolute URL string, already validated by `RichLink.normalized`.
    public var link: String?

    public init(bold: Bool = false, italic: Bool = false, underline: Bool = false,
                strikethrough: Bool = false, color: RichColor? = nil, link: String? = nil) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.color = color
        self.link = link
    }

    public static let plain = RichFormat()
}

public struct RichRun: Sendable, Equatable {
    public var text: String
    public var format: RichFormat

    public init(text: String, format: RichFormat = .plain) {
        self.text = text
        self.format = format
    }
}

/// A picture placed on its own line. `width` and `height` are the stored
/// image's pixel size, kept so the layout can reserve the right space before
/// the bytes are decoded.
public struct RichImage: Sendable, Equatable, Codable {
    public var id: UUID
    public var width: Double
    public var height: Double

    public init(id: UUID, width: Double, height: Double) {
        self.id = id
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double { height > 0 ? width / height : 1 }
}

// MARK: - Normal form

extension RichDocument {

    /// Characters that end a paragraph. UITextView writes "\n", but pasted text
    /// can carry Windows, classic Mac or Unicode separators.
    static let paragraphSeparators: Set<Character> = ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}"]

    /// The Unicode object-replacement character: the placeholder a text view
    /// stores where a picture sits. It never belongs inside text.
    static let objectReplacement: Character = "\u{FFFC}"

    static func splitParagraphs(_ text: String) -> [String] {
        var lines: [String] = [""]
        for character in text {
            if paragraphSeparators.contains(character) {
                lines.append("")
            } else {
                lines[lines.count - 1].append(character)
            }
        }
        return lines
    }

    /// The canonical form of this document. Two documents that look the same
    /// have the same normal form, which is what lets a render, edit and parse
    /// cycle be tested for equality.
    ///
    /// - Runs that carry a paragraph separator are split into paragraphs of the
    ///   same style; a run's text can never span two paragraphs.
    /// - Picture placeholders inside text are removed (pictures are blocks).
    /// - Links are validated; an invalid link is dropped, its text kept.
    /// - Empty runs disappear and neighbours with equal formats merge.
    /// - A document holding nothing but one empty paragraph is the empty
    ///   document.
    /// - An empty last paragraph is always body: a heading or quote with no
    ///   text has nothing to carry its style, so it cannot survive a round
    ///   trip and is not allowed to differ.
    public func normalized() -> RichDocument {
        var out: [RichBlock] = []

        for block in blocks {
            switch block {
            case .image(let image):
                // Whole pixels, at least one: the stored size is a pixel count,
                // and a zero or NaN would break the aspect ratio downstream.
                var clean = image
                clean.width = clean.width > 0 ? max(1, clean.width.rounded()) : 1
                clean.height = clean.height > 0 ? max(1, clean.height.rounded()) : 1
                out.append(.image(clean))

            case .paragraph(let paragraph):
                var current: [RichRun] = []
                var pieces: [[RichRun]] = []
                for run in paragraph.runs {
                    var format = run.format
                    format.link = format.link.flatMap(RichLink.normalized)
                    let lines = RichDocument.splitParagraphs(run.text)
                    for (index, line) in lines.enumerated() {
                        if index > 0 {
                            pieces.append(current)
                            current = []
                        }
                        let text = line.filter { $0 != RichDocument.objectReplacement }
                        if !text.isEmpty { current.append(RichRun(text: text, format: format)) }
                    }
                }
                pieces.append(current)
                for runs in pieces {
                    out.append(.paragraph(RichParagraph(style: paragraph.style, runs: RichDocument.merged(runs))))
                }
            }
        }

        if case .paragraph(var last)? = out.last, last.runs.isEmpty, last.style != .body, last.style != .bullet {
            last.style = .body
            out[out.count - 1] = .paragraph(last)
        }
        if out.count == 1, case .paragraph(let only) = out[0], only.runs.isEmpty, only.style == .body {
            out = []
        }
        return RichDocument(blocks: out)
    }

    static func merged(_ runs: [RichRun]) -> [RichRun] {
        var result: [RichRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = result.last, last.format == run.format {
                result[result.count - 1].text += run.text
            } else {
                result.append(run)
            }
        }
        return result
    }

    /// The document without blank paragraphs at either end: what is worth
    /// storing after an edit. Blank lines between paragraphs are kept, since
    /// they are the writer's spacing.
    public func trimmed() -> RichDocument {
        var blocks = normalized().blocks
        func isBlank(_ block: RichBlock) -> Bool {
            if case .paragraph(let p) = block {
                return p.text.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return false
        }
        while let first = blocks.first, isBlank(first) { blocks.removeFirst() }
        while let last = blocks.last, isBlank(last) { blocks.removeLast() }
        return RichDocument(blocks: blocks)
    }
}

// MARK: - Reading the document

extension RichDocument {

    /// Every paragraph's text, one per line, pictures left out. This is what
    /// search looks through.
    public var plainText: String {
        blocks.compactMap { block -> String? in
            if case .paragraph(let p) = block { return p.text }
            return nil
        }
        .joined(separator: "\n")
    }

    /// The first line with visible text, trimmed: what a list row shows.
    public var previewLine: String? {
        for block in blocks {
            if case .paragraph(let p) = block {
                let line = p.text.trimmingCharacters(in: .whitespaces)
                if !line.isEmpty { return line }
            }
        }
        return nil
    }

    /// Identifiers of every picture, in reading order, without duplicates.
    public var imageIDs: [UUID] {
        var seen: Set<UUID> = []
        var ids: [UUID] = []
        for block in blocks {
            if case .image(let image) = block, seen.insert(image.id).inserted {
                ids.append(image.id)
            }
        }
        return ids
    }

    public var hasImages: Bool { !imageIDs.isEmpty }

    /// True when there is nothing to read and nothing to see.
    public var isBlank: Bool {
        !hasImages && plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Short enough to be displayed centred, like a word on a flash card,
    /// rather than laid out as a page of text.
    public var isShort: Bool {
        let paragraphs = blocks.filter { if case .paragraph = $0 { return true } else { return false } }
        let hasList = blocks.contains { if case .paragraph(let p) = $0 { return p.style == .bullet } else { return false } }
        return !hasList && paragraphs.count <= 3 && plainText.count <= 140
    }
}

// MARK: - Links

/// Validation for the links a card may carry.
public enum RichLink {

    /// Schemes a card link may use. `javascript:`, `file:` and the like are
    /// refused: a card is written by its owner, but pasted text is not.
    static let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    /// A usable absolute URL string for `raw`, or nil.
    ///
    /// "fr.wikipedia.org/wiki/Paris" and "www.example.com" gain "https://",
    /// because that is what someone typing an address means. Text with spaces
    /// or without a dotted host is not a link.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }) else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            guard allowedSchemes.contains(scheme) else {
                // "example.com:8080/x" parses with scheme "example.com"; only a
                // dotted first part can be such a host, so try it as one.
                return scheme.contains(".") ? withHTTPS(trimmed) : nil
            }
            if scheme == "http" || scheme == "https" {
                guard let host = url.host, !host.isEmpty else { return nil }
            } else {
                guard trimmed.count > scheme.count + 1 else { return nil }
            }
            return url.absoluteString
        }
        return withHTTPS(trimmed)
    }

    private static func withHTTPS(_ text: String) -> String? {
        guard let url = URL(string: "https://" + text),
              let host = url.host,
              host.contains("."),
              !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return url.absoluteString
    }
}

// MARK: - Storage (JSON)

extension RichDocument: Codable {
    private enum CodingKeys: String, CodingKey { case version, blocks }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try container.decodeIfPresent([RichBlock].self, forKey: .blocks) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(RichDocument.currentVersion, forKey: .version)
        try container.encode(blocks, forKey: .blocks)
    }

    /// The stored form. Sorted keys make equal documents byte-identical.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Read a stored document. Unreadable data yields nil rather than an
    /// exception: a damaged side should show as empty, not take the card down.
    public static func from(jsonData data: Data?) -> RichDocument? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(RichDocument.self, from: data)
    }
}

extension RichBlock: Codable {
    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "paragraph"
        switch type {
        case "image":
            self = .image(try RichImage(from: decoder))
        case "paragraph":
            self = .paragraph(try RichParagraph(from: decoder))
        default:
            // A block type from a later version of the app. Keeping the card
            // readable matters more than showing the unknown part.
            self = .paragraph(RichParagraph())
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .paragraph(let paragraph):
            try container.encode("paragraph", forKey: .type)
            try paragraph.encode(to: encoder)
        case .image(let image):
            try container.encode("image", forKey: .type)
            try image.encode(to: encoder)
        }
    }
}

extension RichParagraph: Codable {
    private enum CodingKeys: String, CodingKey { case style, runs }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .style) ?? RichParagraphStyle.body.rawValue
        style = RichParagraphStyle(rawValue: raw) ?? .body
        runs = try container.decodeIfPresent([RichRun].self, forKey: .runs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style.rawValue, forKey: .style)
        try container.encode(runs, forKey: .runs)
    }
}

extension RichRun: Codable {
    private enum CodingKeys: String, CodingKey {
        case text, bold, italic, underline, strikethrough, color, link
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        format = RichFormat(
            bold: try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false,
            italic: try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false,
            underline: try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false,
            strikethrough: try container.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false,
            color: try container.decodeIfPresent(String.self, forKey: .color).flatMap(RichColor.init(rawValue:)),
            link: try container.decodeIfPresent(String.self, forKey: .link)
        )
    }

    /// Only what is set is written, so plain text stays `{"text":"…"}`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        if format.bold { try container.encode(true, forKey: .bold) }
        if format.italic { try container.encode(true, forKey: .italic) }
        if format.underline { try container.encode(true, forKey: .underline) }
        if format.strikethrough { try container.encode(true, forKey: .strikethrough) }
        if let color = format.color { try container.encode(color.rawValue, forKey: .color) }
        if let link = format.link { try container.encode(link, forKey: .link) }
    }
}
