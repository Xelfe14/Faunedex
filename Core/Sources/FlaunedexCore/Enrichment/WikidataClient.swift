import Foundation

/// Wikidata is the primary source for French + English common names (property
/// P1843, CC0) and a keyless fallback for conservation status (P141). One SPARQL
/// query returns all three.
public enum WikidataClient {

    public struct Result: Sendable, Equatable {
        public let names: VernacularNames
        /// IUCN category code derived from P141, e.g. "LC" — nil if absent.
        public let iucnCategory: String?
        public init(names: VernacularNames, iucnCategory: String?) {
            self.names = names
            self.iucnCategory = iucnCategory
        }
    }

    /// Build the SPARQL text for a scientific name (matched on P225, taxon name).
    public static func sparql(scientificName: String) -> String {
        let escaped = scientificName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        SELECT ?fr ?en ?iucnLabel WHERE {
          ?taxon wdt:P225 "\(escaped)".
          OPTIONAL { ?taxon wdt:P1843 ?fr FILTER(LANG(?fr) = "fr") }
          OPTIONAL { ?taxon wdt:P1843 ?en FILTER(LANG(?en) = "en") }
          OPTIONAL {
            ?taxon wdt:P141 ?iucn.
            ?iucn rdfs:label ?iucnLabel FILTER(LANG(?iucnLabel) = "en")
          }
        } LIMIT 1
        """
    }

    public static func queryURL(scientificName: String) -> URL {
        var c = URLComponents(url: FlaunedexConfig.wikidataSPARQL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "query", value: sparql(scientificName: scientificName)),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url!
    }

    private struct ResponseDTO: Decodable {
        struct Results: Decodable { let bindings: [[String: Binding]] }
        struct Binding: Decodable { let value: String? }
        let results: Results?
    }

    public static func parse(_ data: Data) throws -> Result {
        let dto = try JSONDecoder().decode(ResponseDTO.self, from: data)
        let first = dto.results?.bindings.first ?? [:]
        let names = VernacularNames(
            french: first["fr"]?.value,
            english: first["en"]?.value
        )
        return Result(names: names, iucnCategory: iucnCode(fromLabel: first["iucnLabel"]?.value))
    }

    /// Map an English IUCN status label to its short code. Order matters:
    /// "critically endangered" is checked before "endangered", and "extinct in
    /// the wild" before "extinct".
    public static func iucnCode(fromLabel label: String?) -> String? {
        guard let l = label?.lowercased() else { return nil }
        if l.contains("critically endangered") { return "CR" }
        if l.contains("extinct in the wild") { return "EW" }
        if l.contains("near threatened") { return "NT" }
        if l.contains("least concern") { return "LC" }
        if l.contains("vulnerable") { return "VU" }
        if l.contains("endangered") { return "EN" }
        if l.contains("data deficient") { return "DD" }
        if l.contains("not evaluated") || l.contains("not applicable") { return "NE" }
        if l.contains("extinct") { return "EX" }
        return nil
    }
}
