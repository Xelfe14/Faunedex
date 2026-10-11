import Foundation
import SwiftData
import FlaunedexCore

/// The colours a folder can wear. Names only: the palette itself lives in the
/// design layer, so a folder stored today still reads correctly if the palette
/// is retuned later.
enum FolderColor: String, CaseIterable, Identifiable {
    case indigo, blue, teal, green, amber, orange, red, pink, purple, slate

    var id: String { rawValue }
}

/// A folder of the Savoirs section. Folders nest to any depth.
///
/// CloudKit-safe on the same terms as the other models: every stored property
/// has a default, relationships are optional, and there is no unique
/// constraint. Deleting a folder deletes everything inside it (sub-folders and
/// cards), which the screen confirms first with the exact counts.
@Model
final class KnowledgeFolder {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "📚"
    var colorRaw: String = FolderColor.indigo.rawValue
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    var parent: KnowledgeFolder?

    @Relationship(deleteRule: .cascade, inverse: \KnowledgeFolder.parent)
    var children: [KnowledgeFolder]? = []

    @Relationship(deleteRule: .cascade, inverse: \KnowledgeCard.folder)
    var cards: [KnowledgeCard]? = []

    init(id: UUID = UUID(), name: String, emoji: String = "📚", color: FolderColor = .indigo) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorRaw = color.rawValue
    }

    var color: FolderColor {
        get { FolderColor(rawValue: colorRaw) ?? .indigo }
        set { colorRaw = newValue.rawValue }
    }

    /// The folder as the framework-free tree logic sees it.
    var node: FolderNode { FolderNode(id: id, parentID: parent?.id) }

    var sortedChildren: [KnowledgeFolder] {
        (children ?? []).sorted(by: KnowledgeFolder.displayOrder)
    }

    /// Hand order first, then alphabetical, so new folders land predictably.
    static func displayOrder(_ a: KnowledgeFolder, _ b: KnowledgeFolder) -> Bool {
        if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}

/// Which face of a card.
enum CardSide: String, CaseIterable, Identifiable {
    case recto
    case verso

    var id: String { rawValue }
    var frenchLabel: String { self == .recto ? "Recto" : "Verso" }
    var other: CardSide { self == .recto ? .verso : .recto }
}

/// One knowledge card: a recto, a verso, and where it stands in the deck.
///
/// Each side is stored as `RichDocument` JSON (formatted text plus picture
/// references). A plain-text copy of each side is kept beside it, because list
/// rows and search read hundreds of cards and should not decode rich documents
/// to do it. Pictures are separate `KnowledgeImage` records.
@Model
final class KnowledgeCard {
    var id: UUID = UUID()

    var rectoData: Data?
    var versoData: Data?
    var rectoText: String = ""
    var versoText: String = ""

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: Place in the deck

    /// Set when the card is "retirée": out of every session until restored.
    var retiredAt: Date?
    /// Consecutive "Maîtrisée" confirmations (the Leitner box).
    var masteryLevel: Int = 0
    /// First instant the card may be dealt again after a "Maîtrisée".
    var restUntil: Date?
    var lastMasteredAt: Date?
    /// Times the card was dealt and passed: the shuffled deck's counter.
    var timesDealt: Int = 0
    var lastDealtAt: Date?

    var folder: KnowledgeFolder?

    @Relationship(deleteRule: .cascade, inverse: \KnowledgeImage.card)
    var images: [KnowledgeImage]? = []

    init(id: UUID = UUID()) {
        self.id = id
    }

    // MARK: Typed accessors

    var recto: RichDocument { RichDocument.from(jsonData: rectoData) ?? .empty }
    var verso: RichDocument { RichDocument.from(jsonData: versoData) ?? .empty }

    func document(for side: CardSide) -> RichDocument {
        side == .recto ? recto : verso
    }

    func previewText(for side: CardSide) -> String {
        let text = side == .recto ? rectoText : versoText
        let firstLine = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return firstLine ?? ""
    }

    var mastery: MasteryState {
        get { MasteryState(level: masteryLevel, restUntil: restUntil) }
        set {
            masteryLevel = newValue.level
            restUntil = newValue.restUntil
        }
    }

    var isRetired: Bool { retiredAt != nil }

    func isResting(at now: Date = .now) -> Bool {
        !isRetired && MasteryRule.isResting(mastery, at: now)
    }

    /// The card as the framework-free dealer sees it.
    var deckEntry: DeckEntry {
        DeckEntry(id: id, timesDealt: timesDealt, mastery: mastery, isRetired: isRetired)
    }

    var hasImages: Bool { !(images ?? []).isEmpty }
}

/// A picture placed on a card, already shrunk, uprighted and stripped of its
/// metadata by `ImageDownscaler`.
///
/// External storage keeps the bytes out of the main database file (SwiftData
/// writes them beside it), and a record of their own keeps them out of the
/// card's record: iCloud limits a record to 1 MB, attached files aside.
@Model
final class KnowledgeImage {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data?
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var createdAt: Date = Date.now

    var card: KnowledgeCard?

    init(id: UUID, data: Data, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
