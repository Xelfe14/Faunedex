import Foundation

/// Orchestrates the GBIF calls: fetch + parse for taxonomy, distribution, and
/// vernacular names. The parsing and classification logic it composes is unit
/// tested independently; this layer stays thin.
public struct GBIFService: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Resolve a raw scientific name to a canonical taxon. Returns nil when GBIF
    /// has no usable match; the returned match may still be untrustworthy
    /// (`TaxonMatch.isTrustworthy()`).
    public func match(name: String) async throws -> TaxonMatch? {
        let data = try await http.getData(GBIFEndpoints.match(name: name))
        return try GBIFResponses.parseMatch(data)
    }

    /// Compute the natural-range distribution for a species key.
    public func distribution(speciesKey: Int, minimumOccurrences: Int = 1) async throws -> DistributionResult {
        async let facetData = http.getData(GBIFEndpoints.occurrenceCountryFacet(speciesKey: speciesKey))
        async let distData = http.getData(GBIFEndpoints.distributions(speciesKey: speciesKey))

        let facetCounts = try await GBIFResponses.parseCountryFacet(facetData)
        // Distributions are enrichment-only; a failure there shouldn't sink the
        // whole range, so tolerate it.
        let rows: [GBIFResponses.DistributionRow]
        if let data = try? await distData {
            rows = (try? GBIFResponses.parseDistributions(data)) ?? []
        } else {
            rows = []
        }
        return DistributionPipeline.compute(
            facetCounts: facetCounts,
            distributionRows: rows,
            minimumOccurrences: minimumOccurrences
        )
    }

    /// GBIF vernacular names (a fallback source; Wikidata is primary).
    public func vernacularNames(speciesKey: Int) async throws -> VernacularNames {
        let data = try await http.getData(GBIFEndpoints.vernacularNames(speciesKey: speciesKey))
        return try GBIFResponses.parseVernacular(data)
    }

    /// Resolve realm + animal sub-group from a taxon match.
    public func realmAndGroup(for taxon: TaxonMatch) -> (realm: Realm?, animalGroup: AnimalGroup?) {
        let realm = taxon.realm
        let group: AnimalGroup? = (realm == .animal) ? AnimalGroupClassifier.classify(taxon) : nil
        return (realm, group)
    }
}
