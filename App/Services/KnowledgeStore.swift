import Foundation
import SwiftData
import Observation
import FlaunedexCore

/// The Savoirs section's brain: asks Gemini for a card, illustrates it from
/// Wikipedia, saves it, and records every review.
///
/// It mirrors `RecipeStore`. The prompt, schema, parsing and scheduling live in
/// FlaunedexCore and are tested there; this layer does the parts that need
/// SwiftData, the Keychain and the file system.
@MainActor
@Observable
final class KnowledgeStore {
    private let context: ModelContext
    private let keys: APIKeys
    private let generator = KnowledgeGenerationService()
    private let pictures = DishPhotoService()
    private let images = PhotoStore(folder: "Knowledge")

    /// A request is in flight. Drives the spinner and disables the ask button.
    var isWorking = false

    init(context: ModelContext, keys: APIKeys) {
        self.context = context
        self.keys = keys
        ensureCategories()
    }

    /// Where a card goes when it has no category, and where the cards of a
    /// deleted category move to.
    nonisolated static let fallbackKey = KnowledgeTheme.divers.rawValue

    var hasGeminiKey: Bool { keys.hasGeminiKey }

    enum KnowledgeError: LocalizedError {
        case noKey
        case network(String)

        var errorDescription: String? {
            switch self {
            case .noKey: return "Ajoutez votre clé Gemini dans Réglages pour créer une fiche."
            case .network(let detail): return detail
            }
        }
    }

    // MARK: Asking for a card

    /// Ask for a new card and store it, in `categoryKey` if the learner chose
    /// one, otherwise in whichever of their categories the model picks. The
    /// picture is fetched afterwards and never blocks the result.
    @discardableResult
    func generate(request: KnowledgeRequest, categoryKey: String? = nil) async throws -> KnowledgeCard {
        guard keys.hasGeminiKey else { throw KnowledgeError.noKey }
        isWorking = true
        defer { isWorking = false }

        let categories = allCategories()
        var request = request
        request.categories = categories.map(\.name)
        let draft: KnowledgeDraft
        do {
            draft = try await generator.generate(request: request, apiKey: keys.geminiKey)
        } catch {
            throw KnowledgeError.network(Self.frenchMessage(for: error))
        }

        let card = KnowledgeCard(title: draft.title, source: .gemini)
        card.apply(draft)
        card.categoryKey = categoryKey
            ?? KnowledgeCategoryMatch.index(of: draft.category, in: request.categories).map { categories[$0].key }
            ?? Self.fallbackKey
        card.originalPrompt = request.subject
        context.insert(card)
        save()

        await attachPicture(to: card, query: draft.wikipediaQuery ?? draft.title)
        return card
    }

    /// Ask for a change to a card that already exists. Its category and its
    /// review history are kept: rewording a card doesn't make it unknown, nor
    /// move it off the shelf the learner put it on.
    func revise(_ card: KnowledgeCard, change: String) async throws {
        guard keys.hasGeminiKey else { throw KnowledgeError.noKey }
        isWorking = true
        defer { isWorking = false }

        var current = card.draft
        current.category = category(forKey: card.categoryKey)?.name
        do {
            let draft = try await generator.generate(
                request: KnowledgeRequest(subject: card.title),
                apiKey: keys.geminiKey,
                revision: .init(existingText: KnowledgeSchema.render(current), change: change),
                thinkingLevel: .high
            )
            let hadPicture = card.imageURLString != nil
            card.apply(draft)
            save()
            if !hadPicture {
                await attachPicture(to: card, query: card.wikipediaQuery ?? card.title)
            }
        } catch {
            throw KnowledgeError.network(Self.frenchMessage(for: error))
        }
    }

    // MARK: The learner's own edits

    /// A card the learner wrote themselves, with no model involved. Only
    /// created once they save, so an abandoned editor leaves nothing behind.
    @discardableResult
    func create(_ draft: KnowledgeDraft, categoryKey: String, notes: String) -> KnowledgeCard {
        let card = KnowledgeCard(title: draft.title, source: .manual)
        context.insert(card)
        applyEdit(draft, categoryKey: categoryKey, notes: notes, to: card)
        return card
    }

    /// Replace the card's content with what the learner typed. A card the
    /// model wrote is re-marked as edited, so it never again claims otherwise.
    func applyEdit(_ draft: KnowledgeDraft, categoryKey: String, notes: String, to card: KnowledgeCard) {
        card.apply(draft)
        card.categoryKey = categoryKey
        if draft.wikipediaQuery == nil { card.wikipediaQuery = nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        card.notes = trimmed.isEmpty ? nil : trimmed
        if card.source == .gemini { card.source = .edited }
        save()
    }

    func setNotes(_ notes: String, on card: KnowledgeCard) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        card.notes = trimmed.isEmpty ? nil : trimmed
        card.updatedAt = .now
        save()
    }

    func toggleFavorite(_ card: KnowledgeCard) {
        card.isFavorite.toggle()
        save()
    }

    func delete(_ card: KnowledgeCard) {
        if let path = card.localImagePath { images.delete(path) }
        context.delete(card)
        save()
    }

    // MARK: Categories

    func allCategories() -> [KnowledgeCategory] {
        let all = (try? context.fetch(FetchDescriptor<KnowledgeCategory>())) ?? []
        return all.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    func category(forKey key: String) -> KnowledgeCategory? {
        allCategories().first { $0.key == key }
    }

    /// Start a new collection with the eleven first categories, and merge the
    /// copies of a category that iCloud may bring from another device.
    ///
    /// Only an empty collection is seeded, so a category the learner deleted
    /// stays deleted. Divers is always kept, as the place cards fall back to.
    func ensureCategories() {
        let all = ((try? context.fetch(FetchDescriptor<KnowledgeCategory>())) ?? [])
            .sorted { $0.createdAt < $1.createdAt }
        if all.isEmpty {
            for (index, theme) in KnowledgeTheme.allCases.enumerated() {
                context.insert(KnowledgeCategory(key: theme.rawValue, name: theme.frenchLabel,
                                                 symbolName: theme.symbolName, sortIndex: index))
            }
            save()
            return
        }
        var seen = Set<String>()
        for category in all {
            if seen.contains(category.key) {
                context.delete(category)
            } else {
                seen.insert(category.key)
            }
        }
        if !seen.contains(Self.fallbackKey) {
            let divers = KnowledgeTheme.divers
            context.insert(KnowledgeCategory(key: Self.fallbackKey, name: divers.frenchLabel,
                                             symbolName: divers.symbolName,
                                             sortIndex: (all.map(\.sortIndex).max() ?? 0) + 1))
        }
        save()
    }

    /// A new category, last in the list. A name already in use returns that
    /// category instead of making a twin.
    @discardableResult
    func createCategory(name: String, symbolName: String) -> KnowledgeCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let existing = allCategories()
        if let index = KnowledgeCategoryMatch.index(of: trimmed, in: existing.map(\.name)) {
            return existing[index]
        }
        let category = KnowledgeCategory(key: UUID().uuidString, name: trimmed, symbolName: symbolName,
                                         sortIndex: (existing.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(category)
        save()
        return category
    }

    func updateCategory(_ category: KnowledgeCategory, name: String, symbolName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { category.name = trimmed }
        category.symbolName = symbolName
        save()
    }

    /// Delete a category; its cards move to Divers rather than disappearing.
    func deleteCategory(_ category: KnowledgeCategory) {
        guard category.key != Self.fallbackKey else { return }
        let key = category.key
        let cards = (try? context.fetch(FetchDescriptor<KnowledgeCard>(
            predicate: #Predicate { $0.themeRaw == key }))) ?? []
        for card in cards { card.categoryKey = Self.fallbackKey }
        context.delete(category)
        save()
    }

    /// Persist an order arranged by hand.
    func persistCategoryOrder(_ ordered: [KnowledgeCategory]) {
        for (index, category) in ordered.enumerated() where category.sortIndex != index {
            category.sortIndex = index
        }
        save()
    }

    /// Move one card to another shelf.
    func setCategory(_ key: String, for card: KnowledgeCard) {
        card.categoryKey = key
        card.updatedAt = .now
        save()
    }

    // MARK: Review

    func record(_ rating: ReviewRating, for card: KnowledgeCard, now: Date = .now) {
        card.review = ReviewScheduler.review(card.review, rating: rating, now: now)
        save()
    }

    /// Put a card back at the start, as if it had never been reviewed.
    func resetReview(of card: KnowledgeCard) {
        card.review = ReviewState()
        save()
    }

    // MARK: Picture

    /// Illustrate the card with the lead image of the matching Wikipedia
    /// article, credited, and keep the article as the "en savoir plus" link.
    /// Uses the same lookup as recipe photographs.
    func attachPicture(to card: KnowledgeCard, query: String) async {
        guard let photo = await pictures.photo(for: query) else { return }
        card.imageURLString = photo.imageURL.absoluteString
        card.thumbURLString = photo.thumbnailURL?.absoluteString
        card.articleURLString = photo.articleURL?.absoluteString
        card.imageArtist = photo.attribution?.artist
        card.imageLicenseShort = photo.attribution?.licenseShortName
        card.imageLicenseURL = photo.attribution?.licenseURL
        card.imageSourcePageURL = photo.attribution?.sourcePageURL
        card.wikipediaQuery = query
        save()

        let target = photo.thumbnailURL ?? photo.imageURL
        if let data = await download(target) {
            card.localImagePath = try? images.save(data, id: card.id)
            save()
        }
    }

    func refreshPicture(for card: KnowledgeCard) async {
        isWorking = true
        defer { isWorking = false }
        await attachPicture(to: card, query: card.wikipediaQuery ?? card.title)
    }

    func localImageData(for card: KnowledgeCard) -> Data? {
        card.localImagePath.flatMap { images.load($0) }
    }

    private func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(FlaunedexConfig.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty else { return nil }
        return data
    }

    // MARK: Plumbing

    private func save() {
        try? context.save()
    }

    /// Turn a networking failure into something the learner can act on.
    static func frenchMessage(for error: Error) -> String {
        if let network = error as? FlaunedexNetworkError, case .decoding = network {
            return "La fiche reçue était illisible. Réessayez, en reformulant si besoin."
        }
        return RecipeStore.frenchMessage(for: error)
    }
}
