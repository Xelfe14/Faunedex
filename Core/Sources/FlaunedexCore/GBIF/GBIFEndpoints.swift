import Foundation

/// Builds the exact GBIF REST URLs the pipeline uses. Pure URL construction so
/// it can be unit-tested without touching the network.
public enum GBIFEndpoints {

    /// `species/match` — resolve a raw scientific name to a canonical taxon.
    public static func match(name: String) -> URL {
        var c = URLComponents(url: FlaunedexConfig.gbifBaseURL.appendingPathComponent("species/match"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "name", value: name)]
        return c.url!
    }

    /// Basis-of-record values that count as genuine present-day wild presence.
    /// Everything GBIF offers **except** `LIVING_SPECIMEN` (zoo/captive) and
    /// `FOSSIL_SPECIMEN` (extinct/subfossil) — the two that would otherwise
    /// unlock a country a species doesn't actually live in today.
    public static let wildPresenceBasisOfRecord = [
        "HUMAN_OBSERVATION",
        "MACHINE_OBSERVATION",
        "OBSERVATION",
        "PRESERVED_SPECIMEN",
        "MATERIAL_SAMPLE",
        "MATERIAL_CITATION",
        "OCCURRENCE",
    ]

    /// `occurrence/search` faceted by country — the primary per-country presence
    /// source. `limit=0` returns no records but the full country facet (fast).
    public static func occurrenceCountryFacet(speciesKey: Int) -> URL {
        var c = URLComponents(url: FlaunedexConfig.gbifBaseURL.appendingPathComponent("occurrence/search"),
                              resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "taxonKey", value: String(speciesKey)),
            URLQueryItem(name: "continent", value: "EUROPE"),
            URLQueryItem(name: "hasCoordinate", value: "true"),
            URLQueryItem(name: "occurrenceStatus", value: "PRESENT"),
            URLQueryItem(name: "limit", value: "0"),
            URLQueryItem(name: "facet", value: "country"),
            URLQueryItem(name: "facetLimit", value: "100"),
        ]
        // One repeated param per accepted basis-of-record value (GBIF ORs them).
        items.append(contentsOf: wildPresenceBasisOfRecord.map {
            URLQueryItem(name: "basisOfRecord", value: $0)
        })
        c.queryItems = items
        return c.url!
    }

    /// `species/{key}/distributions` — checklist distributions, used only to
    /// enrich native vs introduced (never as the primary presence list).
    public static func distributions(speciesKey: Int, limit: Int = 1000) -> URL {
        var c = URLComponents(url: FlaunedexConfig.gbifBaseURL.appendingPathComponent("species/\(speciesKey)/distributions"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        return c.url!
    }

    /// `species/{key}/vernacularNames` — fallback common-name source.
    public static func vernacularNames(speciesKey: Int, limit: Int = 1000) -> URL {
        var c = URLComponents(url: FlaunedexConfig.gbifBaseURL.appendingPathComponent("species/\(speciesKey)/vernacularNames"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        return c.url!
    }
}
