import Foundation

/// One species suggested as findable near the user right now.
public struct NearbySuggestion: Sendable, Equatable, Identifiable {
    public let speciesKey: Int
    /// How many records back this suggestion in the search area & season —
    /// a rough proxy for "how likely you are to run into it".
    public let occurrenceCount: Int
    public let scientificName: String
    public let frenchName: String?
    public let englishName: String?
    public let family: String?
    public let realm: Realm?
    public let animalGroup: AnimalGroup?

    public var id: Int { speciesKey }
    /// Common name for display, first letter capitalised. Vernacular sources are
    /// user-contributed and inconsistently cased ("myrtille commune" next to
    /// "Gentiane Pourpre"); only the first character is touched so proper nouns
    /// like "Laurier-rose des Alpes" survive intact.
    public var displayName: String {
        let raw = frenchName ?? englishName ?? scientificName
        guard let first = raw.first else { return raw }
        return first.uppercased() + raw.dropFirst()
    }

    public init(
        speciesKey: Int, occurrenceCount: Int, scientificName: String,
        frenchName: String? = nil, englishName: String? = nil, family: String? = nil,
        realm: Realm? = nil, animalGroup: AnimalGroup? = nil
    ) {
        self.speciesKey = speciesKey
        self.occurrenceCount = occurrenceCount
        self.scientificName = scientificName
        self.frenchName = frenchName
        self.englishName = englishName
        self.family = family
        self.realm = realm
        self.animalGroup = animalGroup
    }
}

/// "Découvertes" — what could I find around me, right now, that I haven't
/// collected yet? Built on the same GBIF occurrence index the app already uses:
/// search near a coordinate, restricted to the current season, faceted by
/// species, then subtract everything already in the dex.
public enum NearbyEndpoints {

    /// GBIF backbone kingdom keys (stable identifiers in the GBIF taxonomy).
    public static func kingdomKey(for realm: Realm) -> Int {
        switch realm {
        case .animal: return 1
        case .fungus: return 5
        case .plant: return 6
        }
    }

    /// Occurrences within `radiusKm` of a point, in the given month window,
    /// faceted by species.
    public static func speciesFacet(
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        months: ClosedRange<Int>?,
        realm: Realm?,
        facetLimit: Int = 60
    ) -> URL {
        var c = URLComponents(url: FlaunedexConfig.gbifBaseURL.appendingPathComponent("occurrence/search"),
                              resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "geoDistance", value: String(format: "%.5f,%.5f,%.0fkm", latitude, longitude, radiusKm)),
            URLQueryItem(name: "hasCoordinate", value: "true"),
            URLQueryItem(name: "occurrenceStatus", value: "PRESENT"),
            URLQueryItem(name: "taxonRank", value: "SPECIES"),
            URLQueryItem(name: "limit", value: "0"),
            URLQueryItem(name: "facet", value: "speciesKey"),
            URLQueryItem(name: "facetLimit", value: String(facetLimit)),
        ]
        if let months {
            // GBIF accepts a range as "min,max".
            items.append(URLQueryItem(name: "month", value: "\(months.lowerBound),\(months.upperBound)"))
        }
        if let realm {
            items.append(URLQueryItem(name: "kingdomKey", value: String(kingdomKey(for: realm))))
        }
        items.append(contentsOf: GBIFEndpoints.wildPresenceBasisOfRecord.map {
            URLQueryItem(name: "basisOfRecord", value: $0)
        })
        c.queryItems = items
        return c.url!
    }

    /// Full record for one species key (name, family, taxonomy).
    public static func species(key: Int) -> URL {
        FlaunedexConfig.gbifBaseURL.appendingPathComponent("species/\(key)")
    }

    /// A month window centred on `month`, wrapping the year at both ends.
    /// December (12) widens to 11...12 rather than an invalid 11...13.
    public static func seasonWindow(around month: Int, spread: Int = 1) -> ClosedRange<Int> {
        let clamped = min(max(month, 1), 12)
        let lower = max(1, clamped - spread)
        let upper = min(12, clamped + spread)
        return lower...upper
    }
}

/// Fetches and ranks nearby suggestions.
public struct NearbyService: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Rank facet results, dropping species already collected. Pure, so the
    /// selection rule is unit-tested without the network.
    public static func rank(
        facet: [GBIFResponses.CountryCount],
        excluding collectedKeys: Set<Int>,
        limit: Int
    ) -> [(key: Int, count: Int)] {
        facet
            .compactMap { entry -> (key: Int, count: Int)? in
                guard let key = Int(entry.code) else { return nil }
                guard !collectedKeys.contains(key) else { return nil }
                return (key, entry.count)
            }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    /// Suggest species findable near a coordinate this season that the user
    /// hasn't collected. Species whose details can't be resolved are skipped.
    public func suggestions(
        latitude: Double,
        longitude: Double,
        radiusKm: Double = 25,
        month: Int,
        realm: Realm? = nil,
        excluding collectedKeys: Set<Int> = [],
        limit: Int = 12
    ) async throws -> [NearbySuggestion] {

        let facetURL = NearbyEndpoints.speciesFacet(
            latitude: latitude, longitude: longitude, radiusKm: radiusKm,
            months: NearbyEndpoints.seasonWindow(around: month), realm: realm
        )
        let data = try await http.getData(facetURL)
        // The speciesKey facet has the same {name, count} shape as the country facet.
        let facet = try GBIFResponses.parseCountryFacet(data)
        let ranked = Self.rank(facet: facet, excluding: collectedKeys, limit: limit)

        var details: [(entry: (key: Int, count: Int), taxon: TaxonMatch)] = []
        for entry in ranked {
            guard let detail = try? await speciesDetail(key: entry.key) else { continue }
            details.append((entry, detail))
        }

        // One batched Wikidata query translates every suggestion at once, so a
        // French app doesn't show a list of English labels.
        let frenchNames = await frenchNames(
            for: details.map { (key: $0.entry.key, scientificName: $0.taxon.canonicalName) }
        )

        return details.map { item in
            NearbySuggestion(
                speciesKey: item.entry.key,
                occurrenceCount: item.entry.count,
                scientificName: item.taxon.canonicalName,
                frenchName: frenchNames[item.taxon.canonicalName],
                englishName: item.taxon.vernacularName,
                family: item.taxon.family,
                realm: item.taxon.realm,
                animalGroup: item.taxon.realm == .animal ? AnimalGroupClassifier.classify(item.taxon) : nil
            )
        }
    }

    /// French common names for a batch of taxa, keyed by scientific name.
    ///
    /// Wikidata answers for the whole batch in one request, but its P1843
    /// coverage is patchy (verified live: 3 of 5 alpine plants). The taxa it
    /// misses are then looked up concurrently in GBIF's own vernacular list, so
    /// a French app rarely has to fall back to an English label. Best-effort
    /// throughout — any failure just leaves the fallback in place.
    private func frenchNames(
        for taxa: [(key: Int, scientificName: String)]
    ) async -> [String: String] {
        guard !taxa.isEmpty else { return [:] }

        var resolved: [String: String] = [:]
        if let data = try? await http.getData(
            WikidataClient.frenchNamesURL(scientificNames: taxa.map(\.scientificName))
        ), let map = try? WikidataClient.parseFrenchNames(data) {
            resolved = map
        }

        let missing = taxa.filter { resolved[$0.scientificName] == nil }
        guard !missing.isEmpty else { return resolved }

        let fallbacks = await withTaskGroup(of: (String, String?).self) { group in
            for taxon in missing {
                group.addTask {
                    guard let data = try? await http.getData(
                        GBIFEndpoints.vernacularNames(speciesKey: taxon.key)
                    ), let names = try? GBIFResponses.parseVernacular(data) else {
                        return (taxon.scientificName, nil)
                    }
                    return (taxon.scientificName, names.french)
                }
            }
            var found: [String: String] = [:]
            for await (name, french) in group {
                if let french, !french.isEmpty { found[name] = french }
            }
            return found
        }

        return resolved.merging(fallbacks) { current, _ in current }
    }

    private func speciesDetail(key: Int) async throws -> TaxonMatch {
        let data = try await http.getData(NearbyEndpoints.species(key: key))
        guard let taxon = try GBIFResponses.parseSpeciesRecord(data) else {
            throw FlaunedexNetworkError.decoding("species/\(key) had no usable record")
        }
        return taxon
    }
}
