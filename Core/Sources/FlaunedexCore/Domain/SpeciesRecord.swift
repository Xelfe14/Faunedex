import Foundation

/// The fully assembled canonical species — the output of the enrichment
/// pipeline and the shape the app's SwiftData `Species` model mirrors. All
/// media is referenced by URL string; the app downloads and caches bytes.
public struct SpeciesRecord: Sendable, Equatable {
    public var gbifKey: Int
    public var scientificName: String
    public var frenchName: String?
    public var englishName: String?
    public var family: String?
    public var realm: Realm
    public var animalGroup: AnimalGroup?

    /// Natural-range unlock set (ISO alpha-2) + the native/introduced split.
    public var rangeCountries: [String]
    public var nativeCountries: [String]
    public var introducedCountries: [String]

    public var conservation: ConservationStatus?

    public var referenceImageURLString: String?
    public var referenceThumbURLString: String?
    public var imageAttribution: MediaAttribution?

    /// The "En savoir plus sur Wikipédia" link (French article if available,
    /// else English) and its title.
    public var wikipediaURLString: String?
    public var wikipediaTitle: String?

    public var specificiteFR: String?
    public var funFactFR: String?
    public var seasonMonths: [Int]?
    public var toxicityDangerFR: String?

    public var audioURLString: String?
    public var audioAttribution: MediaAttribution?
    public var audioCatalogNumber: String?

    public init(
        gbifKey: Int,
        scientificName: String,
        frenchName: String? = nil,
        englishName: String? = nil,
        family: String? = nil,
        realm: Realm,
        animalGroup: AnimalGroup? = nil,
        rangeCountries: [String] = [],
        nativeCountries: [String] = [],
        introducedCountries: [String] = [],
        conservation: ConservationStatus? = nil,
        referenceImageURLString: String? = nil,
        referenceThumbURLString: String? = nil,
        imageAttribution: MediaAttribution? = nil,
        wikipediaURLString: String? = nil,
        wikipediaTitle: String? = nil,
        specificiteFR: String? = nil,
        funFactFR: String? = nil,
        seasonMonths: [Int]? = nil,
        toxicityDangerFR: String? = nil,
        audioURLString: String? = nil,
        audioAttribution: MediaAttribution? = nil,
        audioCatalogNumber: String? = nil
    ) {
        self.gbifKey = gbifKey
        self.scientificName = scientificName
        self.frenchName = frenchName
        self.englishName = englishName
        self.family = family
        self.realm = realm
        self.animalGroup = animalGroup
        self.rangeCountries = rangeCountries
        self.nativeCountries = nativeCountries
        self.introducedCountries = introducedCountries
        self.conservation = conservation
        self.referenceImageURLString = referenceImageURLString
        self.referenceThumbURLString = referenceThumbURLString
        self.imageAttribution = imageAttribution
        self.wikipediaURLString = wikipediaURLString
        self.wikipediaTitle = wikipediaTitle
        self.specificiteFR = specificiteFR
        self.funFactFR = funFactFR
        self.seasonMonths = seasonMonths
        self.toxicityDangerFR = toxicityDangerFR
        self.audioURLString = audioURLString
        self.audioAttribution = audioAttribution
        self.audioCatalogNumber = audioCatalogNumber
    }

    /// Localized names for display, preferring French.
    public var displayName: String {
        frenchName ?? englishName ?? scientificName
    }
}
