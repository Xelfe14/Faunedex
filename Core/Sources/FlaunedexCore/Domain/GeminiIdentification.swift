import Foundation

/// The structured result Gemini returns for one photo, matching the
/// `responseSchema` declared in `GeminiIdentificationRequest`.
///
/// Decoding is deliberately lenient on the closed-vocabulary fields
/// (`confidence`, `realm`, `animal_group`): they arrive as raw strings and are
/// surfaced through typed accessors so an unexpected value degrades gracefully
/// (`confidence` → `.low`) instead of failing the whole decode. The
/// authoritative `realm`/`animalGroup` for a saved species come from GBIF, not
/// from here — these are the model's hint, useful before the GBIF round-trip.
public struct GeminiIdentification: Codable, Sendable, Equatable {
    public let identified: Bool
    public let confidenceRaw: String
    public let scientificName: String?
    public let frenchName: String?
    public let englishName: String?
    public let family: String?
    public let realmRaw: String?
    public let animalGroupRaw: String?
    public let specificiteFR: String?
    public let funFactFR: String?
    public let seasonMonths: [Int]?
    public let toxicityDangerFR: String?
    public let similarSpecies: [SimilarSpecies]?
    public let candidates: [Candidate]?
    public let reasoning: String?

    enum CodingKeys: String, CodingKey {
        case identified
        case confidenceRaw = "confidence"
        case scientificName = "scientific_name"
        case frenchName = "french_name"
        case englishName = "english_name"
        case family
        case realmRaw = "realm"
        case animalGroupRaw = "animal_group"
        case specificiteFR = "specificite_fr"
        case funFactFR = "fun_fact_fr"
        case seasonMonths = "season_months"
        case toxicityDangerFR = "toxicity_danger_fr"
        case similarSpecies = "similar_species"
        case candidates
        case reasoning
    }

    /// Typed confidence; any unrecognized value is treated as `.low` so the app
    /// errs toward the safe review path.
    public var confidence: IdentificationConfidence {
        IdentificationConfidence(rawValue: confidenceRaw.lowercased()) ?? .low
    }

    public var realm: Realm? { realmRaw.flatMap { Realm(rawValue: $0.lowercased()) } }
    public var animalGroup: AnimalGroup? { animalGroupRaw.flatMap { AnimalGroup(rawValue: $0.lowercased()) } }

    /// True when the app should route to the candidate-review UI rather than
    /// present a single answer: the model wasn't sure, or gave no usable name.
    public var needsReview: Bool {
        !identified || confidence == .low || (scientificName?.isEmpty ?? true)
    }

    public init(
        identified: Bool,
        confidenceRaw: String,
        scientificName: String?,
        frenchName: String?,
        englishName: String?,
        family: String?,
        realmRaw: String?,
        animalGroupRaw: String?,
        specificiteFR: String?,
        funFactFR: String?,
        seasonMonths: [Int]?,
        toxicityDangerFR: String?,
        similarSpecies: [SimilarSpecies]?,
        candidates: [Candidate]?,
        reasoning: String?
    ) {
        self.identified = identified
        self.confidenceRaw = confidenceRaw
        self.scientificName = scientificName
        self.frenchName = frenchName
        self.englishName = englishName
        self.family = family
        self.realmRaw = realmRaw
        self.animalGroupRaw = animalGroupRaw
        self.specificiteFR = specificiteFR
        self.funFactFR = funFactFR
        self.seasonMonths = seasonMonths
        self.toxicityDangerFR = toxicityDangerFR
        self.similarSpecies = similarSpecies
        self.candidates = candidates
        self.reasoning = reasoning
    }

    /// A look-alike the user should be careful not to confuse this with.
    public struct SimilarSpecies: Codable, Sendable, Equatable {
        public let name: String
        public let howToDistinguishFR: String?

        enum CodingKeys: String, CodingKey {
            case name
            case howToDistinguishFR = "how_to_distinguish_fr"
        }

        public init(name: String, howToDistinguishFR: String?) {
            self.name = name
            self.howToDistinguishFR = howToDistinguishFR
        }
    }

    /// One of several candidate identifications, surfaced when confidence is low.
    public struct Candidate: Codable, Sendable, Equatable {
        public let scientificName: String
        public let commonNameFR: String?
        public let probability: Double?

        enum CodingKeys: String, CodingKey {
            case scientificName = "scientific_name"
            case commonNameFR = "common_name_fr"
            case probability
        }

        public init(scientificName: String, commonNameFR: String?, probability: Double?) {
            self.scientificName = scientificName
            self.commonNameFR = commonNameFR
            self.probability = probability
        }
    }
}
