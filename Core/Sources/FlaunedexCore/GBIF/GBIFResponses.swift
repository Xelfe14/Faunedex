import Foundation

/// Decoders that turn raw GBIF JSON into the app's domain types. Kept as pure
/// functions over `Data` so every one is unit-testable against a saved fixture.
public enum GBIFResponses {

    private static let decoder = JSONDecoder()

    // MARK: - species/match

    struct MatchDTO: Decodable {
        let usageKey: Int?
        let acceptedUsageKey: Int?
        let speciesKey: Int?
        let scientificName: String?
        let canonicalName: String?
        let species: String?
        let rank: String?
        let status: String?
        let confidence: Int?
        let matchType: String?
        let kingdom: String?
        let phylum: String?
        let taxonClass: String?
        let order: String?
        let family: String?

        enum CodingKeys: String, CodingKey {
            case usageKey, acceptedUsageKey, speciesKey, scientificName, canonicalName, species
            case rank, status, confidence, matchType, kingdom, phylum, order, family
            case taxonClass = "class"
        }
    }

    /// Parse a `species/match` response. Returns nil when there is no usable key
    /// (a `matchType == NONE` with no keys at all). A returned value may still be
    /// untrustworthy — callers gate with `TaxonMatch.isTrustworthy()`.
    public static func parseMatch(_ data: Data) throws -> TaxonMatch? {
        let dto = try decoder.decode(MatchDTO.self, from: data)
        // Collapse subspecies to the species-rank card, prefer accepted taxon for
        // synonyms, and fall back to the raw usage key.
        guard let key = dto.speciesKey ?? dto.acceptedUsageKey ?? dto.usageKey else {
            return nil
        }
        let name = dto.species ?? dto.canonicalName ?? dto.scientificName ?? ""
        guard !name.isEmpty else { return nil }
        return TaxonMatch(
            speciesKey: key,
            canonicalName: name,
            scientificName: dto.scientificName,
            rank: dto.rank,
            status: dto.status,
            matchType: dto.matchType,
            confidence: dto.confidence,
            kingdom: dto.kingdom,
            phylum: dto.phylum,
            taxonClass: dto.taxonClass,
            order: dto.order,
            family: dto.family
        )
    }

    // MARK: - species/{key}

    struct SpeciesRecordDTO: Decodable {
        let key: Int?
        let nubKey: Int?
        let speciesKey: Int?
        let canonicalName: String?
        let scientificName: String?
        let species: String?
        let rank: String?
        let vernacularName: String?
        let kingdom: String?
        let phylum: String?
        let taxonClass: String?
        let order: String?
        let family: String?

        enum CodingKeys: String, CodingKey {
            case key, nubKey, speciesKey, canonicalName, scientificName, species, rank
            case vernacularName, kingdom, phylum, order, family
            case taxonClass = "class"
        }
    }

    /// Parse a full `species/{key}` record (used by the nearby suggestions,
    /// which start from a species key rather than a name).
    public static func parseSpeciesRecord(_ data: Data) throws -> TaxonMatch? {
        let dto = try decoder.decode(SpeciesRecordDTO.self, from: data)
        guard let key = dto.speciesKey ?? dto.nubKey ?? dto.key else { return nil }
        let name = dto.canonicalName ?? dto.species ?? dto.scientificName ?? ""
        guard !name.isEmpty else { return nil }
        return TaxonMatch(
            speciesKey: key,
            canonicalName: name,
            scientificName: dto.scientificName,
            rank: dto.rank,
            kingdom: dto.kingdom,
            phylum: dto.phylum,
            taxonClass: dto.taxonClass,
            order: dto.order,
            family: dto.family,
            vernacularName: dto.vernacularName
        )
    }

    // MARK: - occurrence facet

    struct FacetResponseDTO: Decodable {
        struct Facet: Decodable {
            struct Count: Decodable { let name: String; let count: Int }
            let field: String?
            let counts: [Count]
        }
        let facets: [Facet]?
    }

    /// One country's occurrence count from the facet.
    public struct CountryCount: Sendable, Equatable {
        public let code: String
        public let count: Int
        public init(code: String, count: Int) {
            self.code = code
            self.count = count
        }
    }

    /// Parse the country facet out of an `occurrence/search` response.
    public static func parseCountryFacet(_ data: Data) throws -> [CountryCount] {
        let dto = try decoder.decode(FacetResponseDTO.self, from: data)
        let facets = dto.facets ?? []
        // Prefer the explicit country facet; fall back to the sole facet present.
        let country = facets.first { ($0.field ?? "").uppercased() == "COUNTRY" } ?? facets.first
        return (country?.counts ?? []).map { CountryCount(code: $0.name.uppercased(), count: $0.count) }
    }

    // MARK: - distributions

    struct DistributionsDTO: Decodable {
        struct Row: Decodable {
            let country: String?
            let establishmentMeans: String?
        }
        let results: [Row]?
    }

    /// A parsed distribution row: an ISO country code + its establishment means.
    public struct DistributionRow: Sendable, Equatable {
        public let country: String
        public let establishmentMeans: String?
        public init(country: String, establishmentMeans: String?) {
            self.country = country
            self.establishmentMeans = establishmentMeans
        }
    }

    /// Parse `species/{key}/distributions`, keeping only rows with a clean
    /// country code (dropping TDWG/island/free-text rows).
    public static func parseDistributions(_ data: Data) throws -> [DistributionRow] {
        let dto = try decoder.decode(DistributionsDTO.self, from: data)
        return (dto.results ?? []).compactMap { row in
            guard let c = row.country, c.count == 2 else { return nil }
            return DistributionRow(country: c.uppercased(), establishmentMeans: row.establishmentMeans)
        }
    }

    // MARK: - vernacular names

    struct VernacularDTO: Decodable {
        struct Row: Decodable {
            let vernacularName: String?
            let language: String?
        }
        let results: [Row]?
    }

    /// Parse GBIF vernacular names, returning the first French and English name.
    public static func parseVernacular(_ data: Data) throws -> VernacularNames {
        let dto = try decoder.decode(VernacularDTO.self, from: data)
        let rows = dto.results ?? []
        func firstName(languages: Set<String>) -> String? {
            rows.first {
                guard let l = $0.language?.lowercased() else { return false }
                return languages.contains(l) && ($0.vernacularName?.isEmpty == false)
            }?.vernacularName
        }
        return VernacularNames(
            french: firstName(languages: ["fra", "fr"]),
            english: firstName(languages: ["eng", "en"])
        )
    }
}
