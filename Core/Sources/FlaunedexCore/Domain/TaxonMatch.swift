import Foundation

/// The canonical taxon resolved from a raw scientific name via GBIF
/// `species/match`. This is the identity anchor for a species in the app:
/// `speciesKey` becomes the stable join id everywhere.
public struct TaxonMatch: Sendable, Equatable {
    /// The stable GBIF key to join on. When the matched name is a synonym this
    /// is the **accepted** taxon's key (`acceptedUsageKey`); otherwise it is the
    /// match's own `usageKey`.
    public let speciesKey: Int
    public let canonicalName: String
    public let scientificName: String?
    public let rank: String?
    public let status: String?
    public let matchType: String?
    /// GBIF's own match confidence (0–100). Low values / `matchType == NONE`
    /// should be rejected before the taxon is trusted.
    public let confidence: Int?

    public let kingdom: String?
    public let phylum: String?
    /// GBIF `class` — frequently absent for fish; never map animal groups from
    /// this alone. Named `taxonClass` because `class` is a reserved word.
    public let taxonClass: String?
    public let order: String?
    public let family: String?
    /// A common name when the record carries one (present on `species/{key}`,
    /// absent from `species/match`).
    public let vernacularName: String?

    public init(
        speciesKey: Int,
        canonicalName: String,
        scientificName: String? = nil,
        rank: String? = nil,
        status: String? = nil,
        matchType: String? = nil,
        confidence: Int? = nil,
        kingdom: String? = nil,
        phylum: String? = nil,
        taxonClass: String? = nil,
        order: String? = nil,
        family: String? = nil,
        vernacularName: String? = nil
    ) {
        self.speciesKey = speciesKey
        self.canonicalName = canonicalName
        self.scientificName = scientificName
        self.rank = rank
        self.status = status
        self.matchType = matchType
        self.confidence = confidence
        self.kingdom = kingdom
        self.phylum = phylum
        self.taxonClass = taxonClass
        self.order = order
        self.family = family
        self.vernacularName = vernacularName
    }

    /// The realm bucket implied by `kingdom`, or nil for unmodeled kingdoms.
    public var realm: Realm? { kingdom.flatMap(Realm.init(gbifKingdom:)) }

    /// True when the match is trustworthy enough to build a species from.
    /// Rejects `matchType == NONE` and low-confidence fuzzy matches.
    public func isTrustworthy(minimumConfidence: Int = 90) -> Bool {
        if let mt = matchType?.uppercased(), mt == "NONE" { return false }
        if let c = confidence, c < minimumConfidence { return false }
        return true
    }
}

/// The per-country European distribution computed for a species. `rangeCountries`
/// is what drives the natural-range unlock rule; native/introduced are stored
/// separately so the rule can be re-derived without re-fetching.
public struct DistributionResult: Sendable, Equatable {
    /// ISO 3166-1 alpha-2 codes where the species is present in Europe, after
    /// filtering artefacts and intersecting the European whitelist.
    public let rangeCountries: [String]
    public let nativeCountries: [String]
    public let introducedCountries: [String]

    public init(rangeCountries: [String], nativeCountries: [String] = [], introducedCountries: [String] = []) {
        self.rangeCountries = rangeCountries
        self.nativeCountries = nativeCountries
        self.introducedCountries = introducedCountries
    }
}
