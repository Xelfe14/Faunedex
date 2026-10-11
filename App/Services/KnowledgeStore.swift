import Foundation
import SwiftData
import UIKit
import Observation
import FlaunedexCore

/// A picture chosen in the editor and already prepared for storage, but not
/// saved yet: it becomes a `KnowledgeImage` when the card is saved, and is
/// simply forgotten if the edit is cancelled.
struct PendingImage: Identifiable {
    let id: UUID
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let image: UIImage

    var richImage: RichImage {
        RichImage(id: id, width: Double(pixelWidth), height: Double(pixelHeight))
    }

    /// Shrink, stand upright and strip a picked photo (see `ImageDownscaler`).
    /// Nil for bytes that are not a picture.
    static func prepare(from data: Data) -> PendingImage? {
        guard let output = ImageDownscaler.downscale(data),
              let image = UIImage(data: output.data) else { return nil }
        return PendingImage(id: UUID(), data: output.data,
                            pixelWidth: output.pixelWidth, pixelHeight: output.pixelHeight,
                            image: image)
    }
}

/// Which cards a session deals.
enum ReviewMode {
    /// The normal session: cards neither resting nor retired.
    case ordinary
    /// "Réviser quand même": only the cards resting after a "Maîtrisée".
    case resting
}

/// What the learner said about a card.
enum ReviewVerdict: CaseIterable {
    case mastered
    case next
    case retired
}

/// Everything a verdict changed on a card, so "Annuler" restores it exactly.
struct VerdictUndo {
    let cardID: UUID
    let verdict: ReviewVerdict
    fileprivate let masteryLevel: Int
    fileprivate let restUntil: Date?
    fileprivate let retiredAt: Date?
    fileprivate let timesDealt: Int
    fileprivate let lastDealtAt: Date?
    fileprivate let lastMasteredAt: Date?
}

/// The Savoirs section's store: folders, cards, pictures, and the verdicts
/// given during revision.
///
/// It mirrors `RecipeStore` and `ScanCoordinator`: the rules (deck, mastery,
/// document format, folder tree) live in FlaunedexCore and are tested there;
/// this layer does the parts that need SwiftData and UIKit.
@MainActor
@Observable
final class KnowledgeStore {
    private let context: ModelContext
    private let calendar: Calendar
    @ObservationIgnored private let imageCache = NSCache<NSUUID, UIImage>()

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: Folders

    @discardableResult
    func createFolder(name: String, emoji: String, color: FolderColor, parent: KnowledgeFolder?) -> KnowledgeFolder {
        let folder = KnowledgeFolder(name: Self.cleanName(name), emoji: emoji, color: color)
        let siblings = parent?.children ?? topLevelFolders()
        folder.sortIndex = (siblings.map(\.sortIndex).max() ?? -1) + 1
        context.insert(folder)
        folder.parent = parent
        save()
        return folder
    }

    func update(_ folder: KnowledgeFolder, name: String, emoji: String, color: FolderColor) {
        folder.name = Self.cleanName(name)
        folder.emoji = emoji
        folder.color = color
        save()
    }

    /// Move a folder under another (nil for the top level). Refused, returning
    /// false, when it would put the folder inside itself.
    @discardableResult
    func move(_ folder: KnowledgeFolder, to parent: KnowledgeFolder?) -> Bool {
        let nodes = allFolders().map(\.node)
        guard FolderTree.canMove(folder.id, under: parent?.id, in: nodes) else { return false }
        folder.parent = parent
        save()
        return true
    }

    func delete(_ folder: KnowledgeFolder) {
        for card in KnowledgeIndex.cards(in: folder, cards: allCards(), folders: allFolders()) {
            forgetImages(of: card)
        }
        context.delete(folder)
        save()
    }

    func allFolders() -> [KnowledgeFolder] {
        (try? context.fetch(FetchDescriptor<KnowledgeFolder>())) ?? []
    }

    func allCards() -> [KnowledgeCard] {
        (try? context.fetch(FetchDescriptor<KnowledgeCard>())) ?? []
    }

    private func topLevelFolders() -> [KnowledgeFolder] {
        allFolders().filter { $0.parent == nil }
    }

    static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Sans titre" : trimmed
    }

    // MARK: Cards

    /// Create or update a card from the two edited sides.
    ///
    /// Pictures follow the text: a picture no longer referenced by either side
    /// is deleted, a newly inserted one is stored, and a reference to a picture
    /// that exists nowhere (it cannot happen through the editor, but the data
    /// should not depend on that) is dropped from the document.
    @discardableResult
    func saveCard(_ existing: KnowledgeCard?, recto: RichDocument, verso: RichDocument,
                  pendingImages: [UUID: PendingImage], folder: KnowledgeFolder) -> KnowledgeCard {
        let card = existing ?? KnowledgeCard()
        if existing == nil { context.insert(card) }

        let stored = Dictionary((card.images ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let available = Set(stored.keys).union(pendingImages.keys)
        let cleanRecto = Self.keepingImages(in: recto.trimmed(), available: available)
        let cleanVerso = Self.keepingImages(in: verso.trimmed(), available: available)
        let referenced = Set(cleanRecto.imageIDs + cleanVerso.imageIDs)

        for (id, image) in stored where !referenced.contains(id) {
            imageCache.removeObject(forKey: id as NSUUID)
            context.delete(image)
        }
        for id in referenced where stored[id] == nil {
            guard let pending = pendingImages[id] else { continue }
            let image = KnowledgeImage(id: id, data: pending.data,
                                       pixelWidth: pending.pixelWidth, pixelHeight: pending.pixelHeight)
            context.insert(image)
            image.card = card
            imageCache.setObject(pending.image, forKey: id as NSUUID)
        }

        card.rectoData = try? cleanRecto.jsonData()
        card.versoData = try? cleanVerso.jsonData()
        card.rectoText = cleanRecto.plainText
        card.versoText = cleanVerso.plainText
        card.folder = folder
        card.updatedAt = .now
        save()
        return card
    }

    static func keepingImages(in document: RichDocument, available: Set<UUID>) -> RichDocument {
        RichDocument(blocks: document.blocks.filter { block in
            if case .image(let image) = block { return available.contains(image.id) }
            return true
        })
    }

    func delete(_ card: KnowledgeCard) {
        forgetImages(of: card)
        context.delete(card)
        save()
    }

    func retire(_ card: KnowledgeCard) {
        card.retiredAt = .now
        save()
    }

    func restore(_ card: KnowledgeCard) {
        card.retiredAt = nil
        save()
    }

    /// Clear a card's mastery by hand, from its detail screen.
    func resetMastery(_ card: KnowledgeCard) {
        card.mastery = .fresh
        save()
    }

    func move(_ card: KnowledgeCard, to folder: KnowledgeFolder) {
        card.folder = folder
        save()
    }

    // MARK: Revision

    /// Deal a session from the given cards (already narrowed to a folder and
    /// everything below it). The dealing rule is `DeckDealer`'s shuffled pack.
    func deal(from cards: [KnowledgeCard], count: Int, mode: ReviewMode, now: Date = .now) -> [KnowledgeCard] {
        let entries = cards.map(\.deckEntry)
        let pool = mode == .ordinary
            ? DeckDealer.dealable(entries, at: now)
            : DeckDealer.resting(entries, at: now)
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return DeckDealer.deal(from: pool, count: count).compactMap { byID[$0] }
    }

    /// Record the learner's verdict on a card they have just been shown.
    ///
    /// Every verdict counts the card as dealt, which advances it in the pack.
    /// "Maîtrisée" and "Suivante" then apply `MasteryRule`; "Retirer" takes the
    /// card out of play. The returned value undoes it all.
    @discardableResult
    func record(_ verdict: ReviewVerdict, on card: KnowledgeCard, now: Date = .now) -> VerdictUndo {
        let undo = VerdictUndo(
            cardID: card.id, verdict: verdict,
            masteryLevel: card.masteryLevel, restUntil: card.restUntil, retiredAt: card.retiredAt,
            timesDealt: card.timesDealt, lastDealtAt: card.lastDealtAt, lastMasteredAt: card.lastMasteredAt
        )
        card.timesDealt += 1
        card.lastDealtAt = now
        switch verdict {
        case .mastered:
            card.mastery = MasteryRule.afterMastered(card.mastery, at: now, calendar: calendar)
            card.lastMasteredAt = now
        case .next:
            card.mastery = MasteryRule.afterNotMastered(card.mastery)
        case .retired:
            card.retiredAt = now
        }
        save()
        return undo
    }

    func undo(_ undo: VerdictUndo, on card: KnowledgeCard) {
        guard card.id == undo.cardID else { return }
        card.masteryLevel = undo.masteryLevel
        card.restUntil = undo.restUntil
        card.retiredAt = undo.retiredAt
        card.timesDealt = undo.timesDealt
        card.lastDealtAt = undo.lastDealtAt
        card.lastMasteredAt = undo.lastMasteredAt
        save()
    }

    // MARK: Pictures

    /// A card's picture, decoded once and then served from memory.
    func image(for id: UUID, in card: KnowledgeCard?) -> UIImage? {
        if let cached = imageCache.object(forKey: id as NSUUID) { return cached }
        guard let record = card?.images?.first(where: { $0.id == id }),
              let data = record.data,
              let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: id as NSUUID)
        return image
    }

    private func forgetImages(of card: KnowledgeCard) {
        for image in card.images ?? [] {
            imageCache.removeObject(forKey: image.id as NSUUID)
        }
    }

    private func save() {
        try? context.save()
    }
}

/// Read-only questions about the folder tree, answered from arrays the views
/// already hold through `@Query`, so screens update live as data changes.
enum KnowledgeIndex {

    static func nodes(_ folders: [KnowledgeFolder]) -> [FolderNode] {
        folders.map(\.node)
    }

    /// The cards of a folder and of every folder below it. Nil means all cards.
    static func cards(in folder: KnowledgeFolder?, cards: [KnowledgeCard], folders: [KnowledgeFolder]) -> [KnowledgeCard] {
        guard let folder else { return cards }
        let scope = FolderTree.subtree(of: folder.id, in: nodes(folders))
        return cards.filter { card in card.folder.map { scope.contains($0.id) } ?? false }
    }

    static func status(of cards: [KnowledgeCard], at now: Date = .now) -> DeckStatus {
        DeckDealer.status(of: cards.map(\.deckEntry), at: now)
    }

    /// Card counts per folder, each folder counting everything below it.
    /// Walks up from each card once, with a visited set against loops.
    static func subtreeCounts(cards: [KnowledgeCard], folders: [KnowledgeFolder]) -> [UUID: Int] {
        var parents: [UUID: UUID] = [:]
        for folder in folders {
            if let parent = folder.parent { parents[folder.id] = parent.id }
        }
        var counts: [UUID: Int] = [:]
        for card in cards {
            var current = card.folder?.id
            var seen: Set<UUID> = []
            while let id = current, seen.insert(id).inserted {
                counts[id, default: 0] += 1
                current = parents[id]
            }
        }
        return counts
    }

    /// "Langues › Anglais › Verbes", or the label for the whole collection.
    static func pathLabel(of folder: KnowledgeFolder?, folders: [KnowledgeFolder]) -> String {
        guard let folder else { return "Tous les dossiers" }
        let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return FolderTree.path(to: folder.id, in: nodes(folders))
            .compactMap { byID[$0]?.name }
            .joined(separator: " › ")
    }

    /// Every folder in tree order with its depth, for pickers and outlines.
    static func outline(_ folders: [KnowledgeFolder]) -> [(folder: KnowledgeFolder, depth: Int)] {
        var result: [(KnowledgeFolder, Int)] = []
        var seen: Set<UUID> = []
        func visit(_ folder: KnowledgeFolder, depth: Int) {
            guard seen.insert(folder.id).inserted else { return }
            result.append((folder, depth))
            for child in folder.sortedChildren { visit(child, depth: depth + 1) }
        }
        for root in folders.filter({ $0.parent == nil }).sorted(by: KnowledgeFolder.displayOrder) {
            visit(root, depth: 0)
        }
        return result
    }

    /// French date for "Prochaine carte le 23 octobre", adding the year only
    /// when it is not the current one.
    static func returnDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let locale = Locale(identifier: "fr_FR")
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear
            ? date.formatted(.dateTime.day().month(.wide).locale(locale))
            : date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }
}
