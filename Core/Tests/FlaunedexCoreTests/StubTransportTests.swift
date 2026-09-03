import Testing
import Foundation
@testable import FlaunedexCore

/// A transport that answers from a script instead of the network.
///
/// The pieces either side of the wire are tested elsewhere: the request body is
/// checked field by field, the response parser is fed recorded payloads. What
/// those cannot show is that the two are actually wired to each other, that a
/// non-2xx status becomes an error rather than a decode failure, and that the
/// fallbacks fall back. Real calls need an API key this machine does not have,
/// so the transport is replaced and everything above it runs for real.
actor ScriptedHTTPClient: HTTPClient {
    struct Reply {
        let status: Int
        let body: Data
        init(status: Int = 200, body: Data) {
            self.status = status
            self.body = body
        }
    }

    /// Replies keyed by a substring of the request URL, in order of preference.
    private let replies: [(match: String, reply: Reply)]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [(match: String, reply: Reply)]) {
        self.replies = replies
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url?.absoluteString ?? ""
        guard let entry = replies.first(where: { url.contains($0.match) }) else {
            throw FlaunedexNetworkError.badStatus(404)
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: entry.reply.status, httpVersion: nil, headerFields: nil
        )!
        return (entry.reply.body, response)
    }

    func recordedRequests() -> [URLRequest] { requests }
}

private func geminiEnvelope(_ object: [String: Any]) throws -> Data {
    let inner = try JSONSerialization.data(withJSONObject: object)
    return try JSONSerialization.data(withJSONObject: [
        "candidates": [["content": ["parts": [["text": String(decoding: inner, as: UTF8.self)]]]]]
    ])
}

/// A function rather than a global constant: `[String: Any]` is not Sendable,
/// and these tests run under strict concurrency like the rest of the package.
private func sampleRecipe() -> [String: Any] {
    [
    "title": "Soupe de potiron",
    "summary_fr": "Une soupe d'automne.",
    "servings": 4,
    "prep_minutes": 15,
    "cook_minutes": 25,
    "difficulty": "facile",
    "course": "entrée",
    "cuisine": "française",
    "ingredients": [["quantity": 1, "unit": "kg", "name": "potiron", "note": NSNull()]],
    "steps": [["text": "Cuire le potiron.", "minutes": 25]],
    "chef_tip_fr": "Rôtir le potiron avant de le mixer.",
    "allergens_fr": [],
    "photo_query": "Soupe de potiron",
        "tags": ["automne"],
    ]
}

struct RecipeGenerationTransportTests {

    @Test func generateSendsTheRequestAndReturnsTheParsedRecipe() async throws {
        let http = ScriptedHTTPClient([
            (":generateContent", .init(body: try geminiEnvelope(sampleRecipe())))
        ])
        let service = RecipeGenerationService(http: http)
        let draft = try await service.generate(
            request: RecipeRequest(query: "une soupe de potiron", servings: 4),
            apiKey: "test-key"
        )

        #expect(draft.title == "Soupe de potiron")
        #expect(draft.servings == 4)
        #expect(draft.ingredients.first?.unit == .kilogram)

        let sent = try #require(await http.recordedRequests().first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        let body = try #require(sent.httpBody)
        let sentJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sentJSON["generationConfig"] != nil, "the schema really is attached to the call")
    }

    @Test func aRefusedKeyBecomesAStatusErrorRatherThanADecodeFailure() async throws {
        let http = ScriptedHTTPClient([
            (":generateContent", .init(status: 403, body: Data(#"{"error":"forbidden"}"#.utf8)))
        ])
        let service = RecipeGenerationService(http: http)
        await #expect(throws: FlaunedexNetworkError.badStatus(403)) {
            _ = try await service.generate(request: RecipeRequest(query: "x"), apiKey: "bad-key")
        }
    }

    @Test func rateLimitingSurfacesItsOwnStatus() async throws {
        let http = ScriptedHTTPClient([(":generateContent", .init(status: 429, body: Data()))])
        await #expect(throws: FlaunedexNetworkError.badStatus(429)) {
            _ = try await RecipeGenerationService(http: http)
                .generate(request: RecipeRequest(query: "x"), apiKey: "k")
        }
    }

    @Test func anEmptyKeyNeverReachesTheNetwork() async throws {
        let http = ScriptedHTTPClient([])
        await #expect(throws: FlaunedexNetworkError.missingAPIKey) {
            _ = try await RecipeGenerationService(http: http)
                .generate(request: RecipeRequest(query: "x"), apiKey: "")
        }
        #expect(await http.recordedRequests().isEmpty)
    }

    @Test func aRevisionCarriesTheCurrentRecipeToTheModel() async throws {
        let http = ScriptedHTTPClient([
            (":generateContent", .init(body: try geminiEnvelope(sampleRecipe())))
        ])
        _ = try await RecipeGenerationService(http: http).generate(
            request: RecipeRequest(query: "Soupe de potiron", servings: 4),
            apiKey: "k",
            revision: .init(existingText: "# Soupe de potiron\n\n## Ingrédients\n- 1 kg de potiron",
                            change: "sans lactose")
        )
        let body = try #require(await http.recordedRequests().first?.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("sans lactose"))
        #expect(text.contains("Soupe de potiron"))
    }
}

struct DishPhotoTransportTests {

    private static func page(title: String, image: String, file: String) -> Data {
        Data("""
        { "query": { "pages": [ { "title": "\(title)", "index": 1,
            "fullurl": "https://fr.wikipedia.org/wiki/\(title)",
            "pageimage": "\(file)",
            "original": { "source": "\(image)" } } ] } }
        """.utf8)
    }

    private static let commonsInfo = Data("""
    { "query": { "pages": [ { "imageinfo": [ {
        "descriptionurl": "https://commons.wikimedia.org/wiki/File:Soupe.jpg",
        "user": "Someone",
        "extmetadata": {
            "Artist": { "value": "<a href=\\"x\\">Jane Doe</a>" },
            "LicenseShortName": { "value": "CC BY-SA 4.0" }
        } } ] } ] } }
    """.utf8)

    @Test func frenchWikipediaIsPreferredAndTheLicenceIsAttached() async throws {
        let http = ScriptedHTTPClient([
            ("fr.wikipedia.org", .init(body: Self.page(
                title: "Soupe", image: "https://upload.wikimedia.org/soupe.jpg", file: "Soupe.jpg"))),
            ("commons.wikimedia.org", .init(body: Self.commonsInfo)),
        ])
        let photo = try #require(await DishPhotoService(http: http).photo(for: "Soupe de potiron"))
        #expect(photo.pageTitle == "Soupe")
        #expect(photo.commonsFileTitle == "File:Soupe.jpg")
        #expect(photo.attribution?.artist == "Jane Doe")
        #expect(photo.attribution?.licenseShortName == "CC BY-SA 4.0")
    }

    @Test func englishIsUsedWhenFrenchHasNoArticleWithAPicture() async throws {
        let http = ScriptedHTTPClient([
            ("fr.wikipedia.org", .init(body: Data(#"{ "batchcomplete": true }"#.utf8))),
            ("en.wikipedia.org", .init(body: Self.page(
                title: "Pumpkin soup", image: "https://upload.wikimedia.org/pumpkin.jpg", file: "P.jpg"))),
            ("commons.wikimedia.org", .init(body: Self.commonsInfo)),
        ])
        let photo = try #require(await DishPhotoService(http: http).photo(for: "Soupe de potiron"))
        #expect(photo.pageTitle == "Pumpkin soup")
    }

    @Test func aRecipeWithNoFindablePhotoIsStillARecipe() async throws {
        let http = ScriptedHTTPClient([
            ("wikipedia.org", .init(status: 500, body: Data())),
        ])
        #expect(await DishPhotoService(http: http).photo(for: "Plat introuvable") == nil)
    }

    @Test func aMissingLicenceDoesNotCostUsThePhoto() async throws {
        let http = ScriptedHTTPClient([
            ("fr.wikipedia.org", .init(body: Self.page(
                title: "Soupe", image: "https://upload.wikimedia.org/soupe.jpg", file: "Soupe.jpg"))),
            ("commons.wikimedia.org", .init(status: 503, body: Data())),
        ])
        let photo = try #require(await DishPhotoService(http: http).photo(for: "Soupe"))
        #expect(photo.attribution == nil)
        #expect(photo.imageURL.absoluteString == "https://upload.wikimedia.org/soupe.jpg")
    }

    @Test func anEmptyQueryDoesNotHitTheNetwork() async throws {
        let http = ScriptedHTTPClient([])
        #expect(await DishPhotoService(http: http).photo(for: "   ") == nil)
        #expect(await http.recordedRequests().isEmpty)
    }
}

/// The identification pipeline end to end, with the network replaced.
///
/// The individual parsers all have their own tests. What only shows up here is
/// the orchestration: that a Gemini answer really does drive a GBIF lookup, that
/// the enrichment fan-out lands in the assembled record, that a failing
/// enrichment source degrades one field instead of sinking the scan, and that a
/// hesitant answer routes to review rather than asserting a species.
struct IdentificationPipelineTransportTests {

    private static func gemini(
        name: String = "Vanessa atalanta",
        confidence: String = "high",
        identified: Bool = true,
        candidates: [[String: Any]] = []
    ) throws -> Data {
        try geminiEnvelope([
            "scientific_name": identified ? name : NSNull(),
            "identified": identified,
            "confidence": confidence,
            "french_name": "Vulcain (Gemini)",
            "english_name": "Red Admiral (Gemini)",
            "family": "Nymphalidae",
            "realm": "animal",
            "animal_group": "insect",
            "specificite_fr": "Papillon commun des jardins.",
            "fun_fact_fr": "Migre depuis l'Afrique du Nord.",
            "season_months": [5, 6, 7],
            "toxicity_danger_fr": NSNull(),
            "similar_species": [],
            "candidates": candidates,
            "reasoning": NSNull(),
        ])
    }

    private static let match = Data("""
    { "usageKey": 1898286, "speciesKey": 1898286, "canonicalName": "Vanessa atalanta",
      "scientificName": "Vanessa atalanta (Linnaeus, 1758)", "rank": "SPECIES",
      "status": "ACCEPTED", "confidence": 99, "matchType": "EXACT",
      "kingdom": "Animalia", "phylum": "Arthropoda", "class": "Insecta", "family": "Nymphalidae" }
    """.utf8)

    private static let facet = Data("""
    { "facets": [ { "field": "COUNTRY", "counts": [
        { "name": "FR", "count": 900 }, { "name": "IT", "count": 400 },
        { "name": "GB", "count": 300 }, { "name": "US", "count": 50 } ] } ] }
    """.utf8)

    private static let distributions = Data("""
    { "results": [ { "country": "FR", "establishmentMeans": "NATIVE" },
                   { "country": "GB", "establishmentMeans": "INTRODUCED" } ] }
    """.utf8)

    private static let vernacular = Data("""
    { "results": [ { "vernacularName": "Red Admiral", "language": "eng" } ] }
    """.utf8)

    private static let wikipedia = Data("""
    { "query": { "pages": [ { "title": "Vanessa atalanta",
        "fullurl": "https://en.wikipedia.org/wiki/Vanessa_atalanta",
        "pageimage": "Vanessa.jpg",
        "original": { "source": "https://upload.wikimedia.org/vanessa.jpg" },
        "langlinks": [ { "lang": "fr", "title": "Vulcain",
                         "url": "https://fr.wikipedia.org/wiki/Vulcain_(papillon)" } ] } ] } }
    """.utf8)

    private static let commons = Data("""
    { "query": { "pages": [ { "imageinfo": [ {
        "descriptionurl": "https://commons.wikimedia.org/wiki/File:Vanessa.jpg",
        "extmetadata": { "Artist": { "value": "Photographer" },
                         "LicenseShortName": { "value": "CC BY 4.0" } } } ] } ] } }
    """.utf8)

    private static let wikidata = Data("""
    { "results": { "bindings": [ { "fr": { "value": "Vulcain" },
                                   "en": { "value": "Red Admiral" },
                                   "iucnLabel": { "value": "Least Concern" } } ] } }
    """.utf8)

    /// Most specific patterns first: every GBIF path shares a host.
    private static func fullScript(gemini: Data) -> [(match: String, reply: ScriptedHTTPClient.Reply)] {
        [
            ("generativelanguage", .init(body: gemini)),
            ("species/match", .init(body: match)),
            ("occurrence/search", .init(body: facet)),
            ("/distributions", .init(body: distributions)),
            ("/vernacularNames", .init(body: vernacular)),
            ("en.wikipedia.org", .init(body: wikipedia)),
            ("commons.wikimedia.org", .init(body: commons)),
            ("query.wikidata.org", .init(body: wikidata)),
        ]
    }

    @Test func aConfidentScanProducesAFullyAssembledSpecies() async throws {
        let http = ScriptedHTTPClient(Self.fullScript(gemini: try Self.gemini()))
        let outcome = try await SpeciesIdentificationPipeline(http: http).run(
            base64Image: "QUJD", mimeType: "image/jpeg",
            keys: .init(gemini: "k")
        )

        #expect(!outcome.needsReview)
        let record = try #require(outcome.record)
        #expect(record.gbifKey == 1898286)
        #expect(record.scientificName == "Vanessa atalanta")
        #expect(record.frenchName == "Vulcain", "Wikidata beats the model's own French name")
        #expect(record.family == "Nymphalidae")
        #expect(record.animalGroup == .insect)
        #expect(record.specificiteFR == "Papillon commun des jardins.")
        #expect(record.seasonMonths == [5, 6, 7])
        #expect(record.referenceImageURLString == "https://upload.wikimedia.org/vanessa.jpg")
        #expect(record.imageAttribution?.artist == "Photographer")
        #expect(record.wikipediaURLString == "https://fr.wikipedia.org/wiki/Vulcain_(papillon)")
        #expect(record.conservation?.displayCategory == "LC")
    }

    @Test func theUnlockRuleReallyRunsOverTheFetchedDistribution() async throws {
        let http = ScriptedHTTPClient(Self.fullScript(gemini: try Self.gemini()))
        let outcome = try await SpeciesIdentificationPipeline(http: http).run(
            base64Image: "QUJD", keys: .init(gemini: "k")
        )
        let record = try #require(outcome.record)
        #expect(record.rangeCountries == ["FR", "IT"],
                "the US record is outside Europe and GB is introduced-only")
        #expect(record.introducedCountries == ["GB"])
        #expect(record.nativeCountries == ["FR"])
    }

    @Test func aHesitantAnswerRoutesToReviewWithoutTouchingGBIF() async throws {
        let http = ScriptedHTTPClient(Self.fullScript(gemini: try Self.gemini(
            confidence: "low",
            candidates: [
                ["scientific_name": "Vanessa atalanta", "common_name_fr": "Vulcain", "probability": 0.6],
                ["scientific_name": "Vanessa cardui", "common_name_fr": "Belle-dame", "probability": 0.3],
            ]
        )))
        let outcome = try await SpeciesIdentificationPipeline(http: http).run(
            base64Image: "QUJD", keys: .init(gemini: "k")
        )
        #expect(outcome.needsReview)
        #expect(outcome.record == nil)
        #expect(outcome.identification.candidates?.count == 2)

        let urls = await http.recordedRequests().compactMap { $0.url?.absoluteString }
        #expect(!urls.contains { $0.contains("gbif") },
                "no point resolving taxonomy for a name the model is unsure of")
    }

    @Test func aFailingEnrichmentSourceCostsOneFieldAndNoMore() async throws {
        var script = Self.fullScript(gemini: try Self.gemini())
        script = script.map { entry in
            entry.match == "en.wikipedia.org"
                ? (match: entry.match, reply: .init(status: 503, body: Data()))
                : entry
        }
        let http = ScriptedHTTPClient(script)
        let record = try #require(
            try await SpeciesIdentificationPipeline(http: http)
                .run(base64Image: "QUJD", keys: .init(gemini: "k")).record
        )
        #expect(record.referenceImageURLString == nil, "no image")
        #expect(record.wikipediaURLString == nil, "no article link")
        #expect(record.frenchName == "Vulcain", "everything else survives")
        #expect(record.rangeCountries == ["FR", "IT"])
    }

    @Test func aFailingDistributionLeavesTheSpeciesUnlockedNowhereRatherThanFailing() async throws {
        var script = Self.fullScript(gemini: try Self.gemini())
        script = script.map { entry in
            entry.match == "occurrence/search"
                ? (match: entry.match, reply: .init(status: 500, body: Data()))
                : entry
        }
        let record = try #require(
            try await SpeciesIdentificationPipeline(http: ScriptedHTTPClient(script))
                .run(base64Image: "QUJD", keys: .init(gemini: "k")).record
        )
        #expect(record.rangeCountries.isEmpty)
        #expect(record.scientificName == "Vanessa atalanta", "the card is still created")
    }

    @Test func aRefusedGeminiKeyPropagatesRatherThanSilentlyProducingNothing() async {
        let http = ScriptedHTTPClient([("generativelanguage", .init(status: 403, body: Data()))])
        await #expect(throws: FlaunedexNetworkError.badStatus(403)) {
            _ = try await SpeciesIdentificationPipeline(http: http)
                .run(base64Image: "QUJD", keys: .init(gemini: "wrong"))
        }
    }
}
