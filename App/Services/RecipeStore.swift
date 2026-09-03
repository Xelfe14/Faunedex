import Foundation
import SwiftData
import Observation
import FlaunedexCore

/// The cooking section's brain: asks Gemini for a recipe, finds a photograph of
/// the dish, saves both, and owns every later change the cook makes.
///
/// It mirrors `ScanCoordinator` on the nature side. The pure work (prompt,
/// schema, parsing, unit conversion, text round trip) lives in FlaunedexCore
/// and is tested there; this layer is deliberately thin and does the parts that
/// need SwiftData, the Keychain and the file system.
@MainActor
@Observable
final class RecipeStore {
    private let context: ModelContext
    private let keys: APIKeys
    private let generator = RecipeGenerationService()
    private let dishPhotos = DishPhotoService()
    private let images = PhotoStore(folder: "Recipes")

    /// A request is in flight. Drives the spinner and disables the ask button.
    var isWorking = false
    /// The last failure, in French, for the screen to show.
    var lastError: String?

    init(context: ModelContext, keys: APIKeys) {
        self.context = context
        self.keys = keys
    }

    var hasGeminiKey: Bool { keys.hasGeminiKey }

    enum RecipeError: LocalizedError {
        case noKey
        case network(String)

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "Ajoutez votre clé Gemini dans Réglages pour demander une recette."
            case .network(let detail):
                return detail
            }
        }
    }

    // MARK: Asking for a recipe

    /// Ask for a new recipe and store it. The photograph is fetched afterwards
    /// and never blocks the result: a recipe with no picture is still a recipe.
    @discardableResult
    func generate(request: RecipeRequest) async throws -> Recipe {
        guard keys.hasGeminiKey else { throw RecipeError.noKey }
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        let draft: RecipeDraft
        do {
            draft = try await generator.generate(request: request, apiKey: keys.geminiKey)
        } catch {
            let message = Self.frenchMessage(for: error)
            lastError = message
            throw RecipeError.network(message)
        }

        let recipe = Recipe(title: draft.title, source: .gemini)
        recipe.apply(draft)
        recipe.originalPrompt = request.query
        recipe.sortIndex = nextSortIndex()
        context.insert(recipe)
        save()

        await attachPhoto(to: recipe, query: draft.photoQuery ?? draft.title)
        return recipe
    }

    /// Ask for a change to a recipe that already exists, sending the current
    /// text so the model amends this dish instead of inventing another one.
    func revise(_ recipe: Recipe, change: String) async throws {
        guard keys.hasGeminiKey else { throw RecipeError.noKey }
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        let existing = RecipeTextFormat.render(recipe.draft)
        let request = RecipeRequest(query: recipe.title, servings: recipe.servings)
        do {
            let draft = try await generator.generate(
                request: request,
                apiKey: keys.geminiKey,
                revision: .init(existingText: existing, change: change),
                thinkingLevel: .high
            )
            let hadPhoto = recipe.imageURLString != nil
            recipe.apply(draft)
            save()
            if !hadPhoto {
                await attachPhoto(to: recipe, query: draft.photoQuery ?? draft.title)
            }
        } catch {
            let message = Self.frenchMessage(for: error)
            lastError = message
            throw RecipeError.network(message)
        }
    }

    // MARK: The cook's own edits

    /// Replace a recipe's whole content with text the cook wrote.
    ///
    /// This is the point of the free-text editor: whatever arrived from the
    /// chatbot, what is stored afterwards is what the cook typed. The recipe is
    /// re-marked as edited, so the card never again claims the model wrote it.
    func applyFreeText(_ text: String, to recipe: Recipe) {
        let parsed = RecipeTextFormat.parse(text)
        recipe.apply(parsed.draft)
        recipe.notes = parsed.notes
        if recipe.source == .gemini { recipe.source = .edited }
        save()
    }

    /// An empty recipe the cook fills in themselves, with no model involved.
    func createBlank() -> Recipe {
        let recipe = Recipe(title: "Nouvelle recette", source: .manual)
        recipe.servings = 4
        recipe.sortIndex = nextSortIndex()
        context.insert(recipe)
        save()
        return recipe
    }

    func setNotes(_ notes: String, on recipe: Recipe) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.notes = trimmed.isEmpty ? nil : trimmed
        recipe.updatedAt = .now
        save()
    }

    func removeIngredient(at offsets: IndexSet, from recipe: Recipe) {
        recipe.ingredients.remove(atOffsets: offsets)
        markEdited(recipe)
    }

    func moveIngredient(from offsets: IndexSet, to destination: Int, in recipe: Recipe) {
        recipe.ingredients.move(fromOffsets: offsets, toOffset: destination)
        markEdited(recipe)
    }

    func removeStep(at offsets: IndexSet, from recipe: Recipe) {
        recipe.steps.remove(atOffsets: offsets)
        markEdited(recipe)
    }

    func moveStep(from offsets: IndexSet, to destination: Int, in recipe: Recipe) {
        recipe.steps.move(fromOffsets: offsets, toOffset: destination)
        markEdited(recipe)
    }

    /// Rewrite every quantity for a different number of eaters. Times are left
    /// alone, because doubling a batch does not double its cooking time.
    func rescale(_ recipe: Recipe, toServings servings: Int) {
        let scaled = recipe.draft.scaled(toServings: servings)
        recipe.ingredients = scaled.ingredients
        recipe.servings = servings
        markEdited(recipe)
    }

    func toggleFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
        save()
    }

    func recordCooked(_ recipe: Recipe) {
        recipe.timesCooked += 1
        save()
    }

    func setTags(_ tags: [String], on recipe: Recipe) {
        recipe.tags = RecipeDraft.uniqueTrimmed(tags)
        recipe.updatedAt = .now
        save()
    }

    func delete(_ recipe: Recipe) {
        if let path = recipe.localImagePath { images.delete(path) }
        context.delete(recipe)
        save()
    }

    /// Persist a hand-arranged order. Called with the list exactly as the cook
    /// left it after dragging.
    func persistOrder(_ ordered: [Recipe]) {
        for (index, recipe) in ordered.enumerated() where recipe.sortIndex != index {
            recipe.sortIndex = index
        }
        save()
    }

    // MARK: Photograph

    /// Find a photograph of the finished dish and cache it on disk.
    ///
    /// The picture is a real photograph from Wikipedia with its Commons licence,
    /// not an image the model made up, and it is credited on the card. Storing
    /// the bytes locally means a recipe still shows its picture in a kitchen
    /// with no signal.
    func attachPhoto(to recipe: Recipe, query: String) async {
        guard let photo = await dishPhotos.photo(for: query) else { return }
        recipe.imageURLString = photo.imageURL.absoluteString
        recipe.thumbURLString = photo.thumbnailURL?.absoluteString
        recipe.articleURLString = photo.articleURL?.absoluteString
        recipe.imageArtist = photo.attribution?.artist
        recipe.imageLicenseShort = photo.attribution?.licenseShortName
        recipe.imageLicenseURL = photo.attribution?.licenseURL
        recipe.imageSourcePageURL = photo.attribution?.sourcePageURL
        recipe.photoQuery = query
        save()

        let target = photo.thumbnailURL ?? photo.imageURL
        if let data = await download(target) {
            recipe.localImagePath = try? images.save(data, id: recipe.id)
            save()
        }
    }

    /// Look the photograph up again, for a recipe whose title the cook changed
    /// or that was created without one.
    func refreshPhoto(for recipe: Recipe) async {
        isWorking = true
        defer { isWorking = false }
        await attachPhoto(to: recipe, query: recipe.photoQuery ?? recipe.title)
    }

    func localImageData(for recipe: Recipe) -> Data? {
        recipe.localImagePath.flatMap { images.load($0) }
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

    private func markEdited(_ recipe: Recipe) {
        if recipe.source == .gemini { recipe.source = .edited }
        recipe.updatedAt = .now
        save()
    }

    private func nextSortIndex() -> Int {
        let all = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        return (all.map(\.sortIndex).max() ?? -1) + 1
    }

    private func save() {
        try? context.save()
    }

    /// Turn a networking failure into something a cook can act on.
    static func frenchMessage(for error: Error) -> String {
        guard let network = error as? FlaunedexNetworkError else {
            return "La demande a échoué. Vérifiez votre connexion et réessayez."
        }
        switch network {
        case .missingAPIKey:
            return "Ajoutez votre clé Gemini dans Réglages."
        case .badStatus(let code) where code == 400 || code == 403:
            return "Clé Gemini refusée (\(code)). Vérifiez-la dans Réglages."
        case .badStatus(let code) where code == 429:
            return "Trop de demandes d'affilée. Patientez un instant, puis réessayez."
        case .badStatus(let code):
            return "Le service a répondu \(code). Réessayez dans un moment."
        case .invalidResponse:
            return "Réponse inattendue du service. Réessayez."
        case .decoding:
            return "La recette reçue était illisible. Réessayez, en reformulant si besoin."
        }
    }
}
