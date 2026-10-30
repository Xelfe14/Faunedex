import Foundation
import SwiftData
import FlaunedexCore

/// The canonical dex card. One row per species (deduped in code by `gbifKey`
/// since CloudKit forbids `@Attribute(.unique)`).
///
/// CloudKit-safe by construction: every stored property has a default, and the
/// relationship is optional. Enum-typed values are stored as raw strings and
/// surfaced through typed accessors.
@Model
final class Species {
    var gbifKey: Int = 0
    var scientificName: String = ""
    var frenchName: String?
    var englishName: String?
    var family: String?

    var realmRaw: String = Realm.animal.rawValue
    var animalGroupRaw: String?

    /// Natural-range unlock set + the native/introduced split (ISO alpha-2).
    var rangeCountries: [String] = []
    var nativeCountries: [String] = []
    var introducedCountries: [String] = []

    var conservationGlobal: String?
    var conservationEurope: String?

    // Reference image + attribution (flattened for CloudKit friendliness).
    var referenceImageURLString: String?
    var referenceThumbURLString: String?
    var localImagePath: String?          // cached bytes on disk
    var imageArtist: String?
    var imageLicenseShort: String?
    var imageLicenseURL: String?
    var imageSourcePageURL: String?

    /// "En savoir plus sur Wikipédia" link (French article preferred).
    var wikipediaURLString: String?
    var wikipediaTitle: String?

    var specificiteFR: String?
    var funFactFR: String?
    var seasonMonths: [Int] = []
    var toxicityDangerFR: String?

    // Bird song + attribution.
    var audioURLString: String?
    var localAudioPath: String?
    var audioRecordist: String?
    var audioLicenseURL: String?
    var audioSourcePageURL: String?
    var audioCatalogNumber: String?

    // The observer's own layer.

    /// Questions asked about this species and Gemini's answers, oldest first.
    var chat: [ChatTurn] = []
    /// Passages of those answers the observer highlighted, shown on the card.
    var highlights: [SpeciesHighlight] = []

    var firstUnlockedAt: Date = Date.now
    /// Catalogue number in discovery order — the "N° 007" that gives the
    /// collection its Pokédex character. Assigned when the species is created.
    var dexNumber: Int = 0
    var enrichmentStatusRaw: String = EnrichmentStatus.pending.rawValue

    @Relationship(deleteRule: .cascade, inverse: \Sighting.species)
    var sightings: [Sighting]? = []

    init(gbifKey: Int, scientificName: String, realm: Realm) {
        self.gbifKey = gbifKey
        self.scientificName = scientificName
        self.realmRaw = realm.rawValue
    }

    // MARK: Typed accessors

    var realm: Realm { Realm(rawValue: realmRaw) ?? .animal }
    var animalGroup: AnimalGroup? { animalGroupRaw.flatMap(AnimalGroup.init(rawValue:)) }
    var enrichmentStatus: EnrichmentStatus {
        get { EnrichmentStatus(rawValue: enrichmentStatusRaw) ?? .pending }
        set { enrichmentStatusRaw = newValue.rawValue }
    }

    var displayName: String { frenchName ?? englishName ?? scientificName }
    var conservationBadge: String? { conservationEurope ?? conservationGlobal }
    var wikipediaURL: URL? { wikipediaURLString.flatMap(URL.init(string:)) }

    var isNotable: Bool {
        guard let c = conservationBadge?.uppercased() else { return false }
        return ["NT", "VU", "EN", "CR", "EW", "EX"].contains(c)
    }

    enum EnrichmentStatus: String, Codable { case pending, partial, complete }
}

/// One physical observation the user made: a photo, where and when.
@Model
final class Sighting {
    var id: UUID = UUID()
    var photoRelativePath: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var horizontalAccuracy: Double = -1
    var capturedAt: Date = Date.now
    var countryISO: String?
    /// How many times the reverse geocode has been tried. The country lookup is
    /// online-only and independent of identification, so it needs its own
    /// counter: a sighting identified from cache while the geocoder was
    /// unreachable would otherwise keep its country empty forever.
    var geocodeAttempts: Int = 0
    var note: String?

    /// Set once the queued scan resolves to a species key.
    var speciesKey: Int?
    var statusRaw: String = Status.pendingIdentification.rawValue
    var retryCount: Int = 0
    /// Low-confidence candidate list (JSON) for the review UI.
    var geminiCandidatesJSON: String?

    var species: Species?

    init(id: UUID = UUID(), photoRelativePath: String, latitude: Double, longitude: Double,
         horizontalAccuracy: Double, capturedAt: Date = .now) {
        self.id = id
        self.photoRelativePath = photoRelativePath
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.capturedAt = capturedAt
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .pendingIdentification }
        set { statusRaw = newValue.rawValue }
    }

    /// A capture taken with no usable GPS fix is stored at (0, 0). Those are
    /// hidden from the map and must never be reverse-geocoded, since (0, 0) is
    /// a real point in the Atlantic.
    var hasCoordinate: Bool { !(latitude == 0 && longitude == 0) }

    /// Whether the country still needs looking up, and is still worth retrying.
    var needsGeocoding: Bool { countryISO == nil && hasCoordinate && geocodeAttempts < 5 }

    enum Status: String, Codable {
        case pendingIdentification, pendingGeocoding, complete, failed, needsReview
    }
}

/// A recipe in the cook's own bank.
///
/// CloudKit-safe on the same terms as `Species` and `Sighting`: every stored
/// property has a default, there is no unique constraint, and the enums are
/// held as raw strings behind typed accessors.
///
/// Ingredients and steps are stored as arrays of the Codable value types from
/// FlaunedexCore rather than as their own entities. They are never queried
/// individually, they are always read and written with the recipe they belong
/// to, and keeping them inline means the CloudKit schema gains one record type
/// instead of three.
@Model
final class Recipe {
    var id: UUID = UUID()
    var title: String = ""
    var summaryFR: String?

    var servings: Int = 4
    var prepMinutes: Int = 0
    var cookMinutes: Int = 0

    var difficultyRaw: String?
    var courseRaw: String?
    var cuisine: String?

    var ingredients: [RecipeIngredient] = []
    var steps: [RecipeStep] = []

    var chefTipFR: String?
    var allergens: [String] = []

    // MARK: The cook's own layer

    /// Free-form notes the cook adds: what they changed, what they learned,
    /// what to do differently next time. Never written by the model.
    var notes: String?
    /// Tags the cook invents. This is the organisation the app does not impose.
    var tags: [String] = []
    var isFavorite: Bool = false
    /// Position in the manual ordering, so the bank can be arranged by hand.
    var sortIndex: Int = 0
    /// How many times the cook says they have actually made this.
    var timesCooked: Int = 0

    // MARK: Photo of the finished dish

    var photoQuery: String?
    var imageURLString: String?
    var thumbURLString: String?
    /// Downloaded bytes on disk, so a recipe is readable with its picture in a
    /// kitchen with no signal.
    var localImagePath: String?
    var imageArtist: String?
    var imageLicenseShort: String?
    var imageLicenseURL: String?
    var imageSourcePageURL: String?
    var articleURLString: String?

    // MARK: Provenance

    var sourceRaw: String = Source.gemini.rawValue
    /// What the cook originally asked for, kept so a revision has context and
    /// so it is always visible where a recipe came from.
    var originalPrompt: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), title: String, source: Source = .gemini) {
        self.id = id
        self.title = title
        self.sourceRaw = source.rawValue
    }

    /// Where the recipe came from. A recipe that started with the chatbot but
    /// has since been rewritten is marked as edited, because after that it is
    /// the cook's text and should not be presented as the model's.
    enum Source: String, Codable {
        case gemini
        case edited
        case manual

        var frenchLabel: String {
            switch self {
            case .gemini: return "Proposée par Gemini"
            case .edited: return "Modifiée par vous"
            case .manual: return "Écrite par vous"
            }
        }

        var symbolName: String {
            switch self {
            case .gemini: return "sparkles"
            case .edited: return "pencil"
            case .manual: return "hand.draw"
            }
        }
    }

    // MARK: Typed accessors

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .gemini }
        set { sourceRaw = newValue.rawValue }
    }
    var difficulty: RecipeDifficulty? {
        get { difficultyRaw.flatMap(RecipeDifficulty.init(rawValue:)) }
        set { difficultyRaw = newValue?.rawValue }
    }
    var course: RecipeCourse? {
        get { courseRaw.flatMap(RecipeCourse.init(rawValue:)) }
        set { courseRaw = newValue?.rawValue }
    }

    var totalMinutes: Int { prepMinutes + cookMinutes }
    var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }
    var articleURL: URL? { articleURLString.flatMap(URL.init(string:)) }
    var hasNotes: Bool { !(notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Bridging to the pure value type

    /// The recipe as the framework-free value Core works with.
    var draft: RecipeDraft {
        RecipeDraft(
            title: title,
            summaryFR: summaryFR,
            servings: servings > 0 ? servings : nil,
            prepMinutes: prepMinutes > 0 ? prepMinutes : nil,
            cookMinutes: cookMinutes > 0 ? cookMinutes : nil,
            difficulty: difficulty,
            course: course,
            cuisine: cuisine,
            ingredients: ingredients,
            steps: steps,
            chefTipFR: chefTipFR,
            allergensFR: allergens,
            photoQuery: photoQuery,
            tags: tags
        )
    }

    /// Overwrite the recipe's content from a draft, leaving the cook's own
    /// layer (notes, favourite, tags, ordering, photo) untouched unless the
    /// draft carries something for it.
    func apply(_ raw: RecipeDraft) {
        let draft = raw.normalized()
        title = draft.title
        summaryFR = draft.summaryFR
        servings = draft.servings ?? servings
        prepMinutes = draft.prepMinutes ?? 0
        cookMinutes = draft.cookMinutes ?? 0
        difficulty = draft.difficulty
        course = draft.course
        cuisine = draft.cuisine
        ingredients = draft.ingredients
        steps = draft.steps
        chefTipFR = draft.chefTipFR
        allergens = draft.allergensFR
        if !draft.tags.isEmpty { tags = draft.tags }
        // A draft parsed back from edited text carries no photo query, so the
        // one already resolved is kept rather than cleared.
        if let query = draft.photoQuery { photoQuery = query }
        updatedAt = .now
    }
}

/// A knowledge card in the Savoirs collection: something worth knowing,
/// explained once, then reviewed until it sticks.
///
/// CloudKit-safe on the same terms as the other models: every stored property
/// has a default, no unique constraint, enums held as raw strings.
@Model
final class KnowledgeCard {
    var id: UUID = UUID()
    var title: String = ""
    /// The `key` of the card's `KnowledgeCategory`. Named for the fixed themes
    /// it first held, and kept so, since renaming a stored property would
    /// change the iCloud schema.
    var themeRaw: String = KnowledgeTheme.divers.rawValue
    var summaryFR: String?
    /// Where the word comes from: always there for a word to define.
    var etymologyFR: String?
    var bodyFR: String = ""
    var keyPoints: [String] = []
    var question: String?
    var answer: String?
    var funFactFR: String?
    var tags: [String] = []

    // MARK: The learner's own layer

    /// Never written by the model.
    var notes: String?
    var isFavorite: Bool = false

    // MARK: Picture and link

    /// The Wikipedia article the card is illustrated from. The text itself is
    /// the model's, and the card says so; the article is "en savoir plus".
    var wikipediaQuery: String?
    var imageURLString: String?
    var thumbURLString: String?
    var localImagePath: String?
    var imageArtist: String?
    var imageLicenseShort: String?
    var imageLicenseURL: String?
    var imageSourcePageURL: String?
    var articleURLString: String?

    // MARK: Review

    var reviewBox: Int = 0
    /// Nil until the first review: a new card is always due.
    var reviewDueAt: Date?
    var reviewCount: Int = 0
    var lapseCount: Int = 0
    var lastReviewedAt: Date?

    // MARK: Provenance

    var sourceRaw: String = Recipe.Source.gemini.rawValue
    var originalPrompt: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), title: String, source: Source = .gemini) {
        self.id = id
        self.title = title
        self.sourceRaw = source.rawValue
    }

    /// The same three origins as a recipe, and the labels read right for both:
    /// "une recette" and "une fiche" are feminine alike.
    typealias Source = Recipe.Source

    // MARK: Typed accessors

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .gemini }
        set { sourceRaw = newValue.rawValue }
    }
    var categoryKey: String {
        get { themeRaw }
        set { themeRaw = newValue }
    }
    var articleURL: URL? { articleURLString.flatMap(URL.init(string:)) }

    var review: ReviewState {
        get {
            ReviewState(box: reviewBox, dueAt: reviewDueAt, reviewCount: reviewCount,
                        lapseCount: lapseCount, lastReviewedAt: lastReviewedAt)
        }
        set {
            reviewBox = newValue.box
            reviewDueAt = newValue.dueAt
            reviewCount = newValue.reviewCount
            lapseCount = newValue.lapseCount
            lastReviewedAt = newValue.lastReviewedAt
        }
    }

    func isDue(at now: Date = .now) -> Bool { review.isDue(at: now) }

    /// The front of the flashcard. A card written by hand may have no question
    /// yet, and is still reviewable on its title.
    var reviewQuestion: String {
        if let question, !question.trimmingCharacters(in: .whitespaces).isEmpty { return question }
        return "Que retenir de « \(title) » ?"
    }

    /// The back of the flashcard: the answer, or failing that the one-line
    /// summary, or the points to remember.
    var reviewAnswer: String {
        if let answer, !answer.trimmingCharacters(in: .whitespaces).isEmpty { return answer }
        if let summaryFR, !summaryFR.isEmpty { return summaryFR }
        return keyPoints.joined(separator: "\n")
    }

    // MARK: Bridging to the pure value type

    /// The card's content. The category is left out: it is a key here, and
    /// whoever needs its name looks it up.
    var draft: KnowledgeDraft {
        KnowledgeDraft(title: title, summaryFR: summaryFR, etymologyFR: etymologyFR, bodyFR: bodyFR,
                       keyPointsFR: keyPoints, questionFR: question, answerFR: answer,
                       funFactFR: funFactFR, wikipediaQuery: wikipediaQuery, tags: tags)
    }

    /// Overwrite the card's content from a draft, leaving its category and the
    /// learner's layer (notes, favourite, review history, picture) untouched.
    func apply(_ raw: KnowledgeDraft) {
        let draft = raw.normalized()
        title = draft.title
        summaryFR = draft.summaryFR
        etymologyFR = draft.etymologyFR
        bodyFR = draft.bodyFR
        keyPoints = draft.keyPointsFR
        question = draft.questionFR
        answer = draft.answerFR
        funFactFR = draft.funFactFR
        if let query = draft.wikipediaQuery { wikipediaQuery = query }
        tags = draft.tags
        updatedAt = .now
    }
}

/// A shelf of the Savoirs collection, which the learner names, decorates and
/// orders as they like.
///
/// Cards point to it by `key`, never by name, so renaming a category moves no
/// card. The first eleven are created from `KnowledgeTheme` with its raw values
/// as keys, which is also how a copy created on a second device before iCloud
/// caught up is recognised and merged; the learner's own get a UUID.
@Model
final class KnowledgeCategory {
    var key: String = ""
    var name: String = ""
    var symbolName: String = "lightbulb"
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    init(key: String, name: String, symbolName: String, sortIndex: Int) {
        self.key = key
        self.name = name
        self.symbolName = symbolName
        self.sortIndex = sortIndex
    }
}
