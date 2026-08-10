import Foundation

/// End-to-end: photo → Gemini identification → GBIF taxonomy + distribution →
/// enrichment → assembled `SpeciesRecord`. All networking flows through the
/// injected `HTTPClient`, so the whole pipeline can be driven with fixtures.
///
/// Enrichment steps are best-effort: a failing image/name/status/audio lookup
/// degrades that field to nil rather than failing the identification.
public struct SpeciesIdentificationPipeline: Sendable {
    private let http: HTTPClient
    private let gemini: GeminiIdentificationService
    private let gbif: GBIFService

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
        self.gemini = GeminiIdentificationService(http: http)
        self.gbif = GBIFService(http: http)
    }

    public struct Keys: Sendable {
        public let gemini: String
        public let iucn: String?
        public let xenoCanto: String?
        public init(gemini: String, iucn: String? = nil, xenoCanto: String? = nil) {
            self.gemini = gemini
            self.iucn = iucn
            self.xenoCanto = xenoCanto
        }
    }

    /// The result of a scan. When `record` is nil the caller should show the
    /// review flow using `identification.candidates`.
    public struct Outcome: Sendable {
        public let identification: GeminiIdentification
        public let taxon: TaxonMatch?
        public let record: SpeciesRecord?
        public var needsReview: Bool { record == nil }
    }

    /// - Parameter hintScientificName: set by the review flow when the user has
    ///   picked one of the candidates, so the model confirms that species
    ///   instead of identifying from scratch.
    public func run(
        base64Image: String,
        mimeType: String = "image/heic",
        keys: Keys,
        thinkingLevel: GeminiIdentificationService.ThinkingLevel = .low,
        hintScientificName: String? = nil
    ) async throws -> Outcome {

        // 1. Identify.
        let id = try await gemini.identify(
            base64Image: base64Image, mimeType: mimeType, apiKey: keys.gemini,
            thinkingLevel: thinkingLevel, hintScientificName: hintScientificName
        )
        guard !id.needsReview, let scientificName = id.scientificName else {
            return Outcome(identification: id, taxon: nil, record: nil)
        }

        // 2. Canonical taxonomy — required for a proper, dedupable card.
        guard let taxon = try await gbif.match(name: scientificName), taxon.isTrustworthy() else {
            let untrusted = try? await gbif.match(name: scientificName)
            return Outcome(identification: id, taxon: untrusted, record: nil)
        }

        // 3. Distribution (natural-range unlock).
        let distribution = (try? await gbif.distribution(speciesKey: taxon.speciesKey))
            ?? DistributionResult(rangeCountries: [])

        // 4. Enrichment fan-out (best effort).
        let (genus, species) = Self.splitBinomial(taxon.canonicalName)
        let (_, group) = gbif.realmAndGroup(for: taxon)

        async let wikipedia = try? enrichWikipedia(scientificName: taxon.canonicalName)
        async let wikidata = try? enrichWikidata(scientificName: taxon.canonicalName)
        async let vernacular = try? gbif.vernacularNames(speciesKey: taxon.speciesKey)
        async let iucn = enrichIUCN(genus: genus, species: species, token: keys.iucn)
        async let audio = enrichBirdSong(genus: genus, species: species, group: group, key: keys.xenoCanto)

        let wiki = await wikipedia ?? nil
        let imageAttribution = try? await enrichImageAttribution(fileTitle: wiki?.commonsFileTitle)

        let record = SpeciesAssembler.assemble(
            taxon: taxon,
            gemini: id,
            distribution: distribution,
            wikipedia: wiki,
            imageAttribution: imageAttribution,
            wikidata: await wikidata ?? nil,
            gbifVernacular: await vernacular ?? nil,
            iucnEuropeCategory: nil,
            iucnGlobalCategory: await iucn,
            birdAudio: await audio
        )
        return Outcome(identification: id, taxon: taxon, record: record)
    }

    // MARK: - Enrichment helpers

    private func enrichWikipedia(scientificName: String) async throws -> WikipediaResult? {
        let data = try await http.getData(WikipediaClient.lookupURL(scientificName: scientificName))
        return try WikipediaClient.parse(data)
    }

    private func enrichImageAttribution(fileTitle: String?) async throws -> MediaAttribution? {
        guard let fileTitle else { return nil }
        let data = try await http.getData(CommonsClient.imageInfoURL(fileTitle: fileTitle))
        return try CommonsClient.parse(data)
    }

    private func enrichWikidata(scientificName: String) async throws -> WikidataClient.Result {
        let data = try await http.getData(
            WikidataClient.queryURL(scientificName: scientificName),
            headers: ["Accept": "application/sparql-results+json"]
        )
        return try WikidataClient.parse(data)
    }

    private func enrichIUCN(genus: String, species: String, token: String?) async -> String? {
        guard let token, !token.isEmpty, !genus.isEmpty, !species.isEmpty else { return nil }
        let headers = IUCNClient.authHeaders(token: token)
        guard let taxaData = try? await http.getData(
            IUCNClient.taxaURL(genus: genus, species: species), headers: headers
        ) else { return nil }
        guard let assessmentID = IUCNClient.parseAssessmentIDs(taxaData).first else { return nil }
        guard let assessment = try? await http.getData(
            IUCNClient.assessmentURL(id: assessmentID), headers: headers
        ) else { return nil }
        return IUCNClient.parseCategory(assessment)
    }

    private func enrichBirdSong(genus: String, species: String, group: AnimalGroup?, key: String?) async -> BirdAudio? {
        guard group == .bird, let key, !key.isEmpty, !genus.isEmpty, !species.isEmpty else { return nil }
        guard let data = try? await http.getData(
            XenoCantoClient.recordingsURL(genus: genus, species: species, key: key)
        ) else { return nil }
        return try? XenoCantoClient.parse(data)
    }

    /// Split "Genus species" → (genus, species). Extra epithets are ignored.
    static func splitBinomial(_ name: String) -> (genus: String, species: String) {
        let parts = name.split(separator: " ", maxSplits: 2).map(String.init)
        let genus = parts.first ?? ""
        let species = parts.count > 1 ? parts[1].lowercased() : ""
        return (genus, species)
    }
}
