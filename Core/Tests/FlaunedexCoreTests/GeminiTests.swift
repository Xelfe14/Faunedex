import Testing
import Foundation
@testable import FlaunedexCore

struct GeminiTests {

    @Test func endpointURLContainsModelAndAction() {
        let url = GeminiIdentificationService.endpointURL(model: "gemini-3.6-flash")
        #expect(url.absoluteString ==
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent")
    }

    @Test func requestBodyStructure() throws {
        let body = GeminiIdentificationService.requestBody(
            base64Image: "QUJD", mimeType: "image/jpeg", thinkingLevel: .low
        )
        let json = try JSONSerialization.jsonObject(with: body.encoded())
        let obj = try #require(json as? [String: Any])

        // generationConfig
        let gen = try #require(obj["generationConfig"] as? [String: Any])
        #expect(gen["responseMimeType"] as? String == "application/json")
        #expect(gen["temperature"] == nil, "Gemini 3 models are meant to run at their default temperature")
        let thinking = try #require(gen["thinkingConfig"] as? [String: Any])
        #expect(thinking["thinkingLevel"] as? String == "low")

        // responseSchema puts scientific_name first
        let schema = try #require(gen["responseSchema"] as? [String: Any])
        let ordering = try #require(schema["propertyOrdering"] as? [String])
        #expect(ordering.first == "scientific_name")

        // image part is present with the given mime type
        let contents = try #require(obj["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let inline = try #require(parts.first?["inlineData"] as? [String: Any])
        #expect(inline["mimeType"] as? String == "image/jpeg")
        #expect(inline["data"] as? String == "QUJD")

        // system instruction present
        #expect(obj["systemInstruction"] != nil)
    }

    @Test func hintIsAppendedToTheUserTurn() throws {
        let body = GeminiIdentificationService.requestBody(
            base64Image: "QUJD", mimeType: "image/jpeg", thinkingLevel: .high,
            hintScientificName: "Hepatica nobilis"
        )
        let json = try JSONSerialization.jsonObject(with: body.encoded())
        let obj = try #require(json as? [String: Any])
        let contents = try #require(obj["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let text = try #require(parts.compactMap { $0["text"] as? String }.first)
        #expect(text.contains("Hepatica nobilis"), "the chosen candidate must reach the model")
        #expect(text.contains(GeminiSchema.userInstruction), "base instruction is kept")

        let gen = try #require(obj["generationConfig"] as? [String: Any])
        let thinking = try #require(gen["thinkingConfig"] as? [String: Any])
        #expect(thinking["thinkingLevel"] as? String == "high", "review re-runs reason harder")
    }

    @Test func noHintLeavesInstructionUnchanged() throws {
        let body = GeminiIdentificationService.requestBody(
            base64Image: "QUJD", mimeType: "image/jpeg", thinkingLevel: .low
        )
        let json = try JSONSerialization.jsonObject(with: body.encoded())
        let obj = try #require(json as? [String: Any])
        let contents = try #require(obj["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let text = try #require(parts.compactMap { $0["text"] as? String }.first)
        #expect(text == GeminiSchema.userInstruction)
    }

    @Test func makeRequestRejectsEmptyKey() {
        let svc = GeminiIdentificationService()
        #expect(throws: FlaunedexNetworkError.missingAPIKey) {
            _ = try svc.makeRequest(base64Image: "QUJD", apiKey: "")
        }
    }

    @Test func makeRequestSetsHeaders() throws {
        let svc = GeminiIdentificationService(model: "gemini-3.6-flash")
        let req = try svc.makeRequest(base64Image: "QUJD", mimeType: "image/heic", apiKey: "secret-key")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "secret-key")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(req.httpBody != nil)
    }

    @Test func parseResponseDecodesInnerJSON() throws {
        // The model returns the structured object as a JSON string in a text part;
        // build that inner payload programmatically to avoid brittle escaping.
        let inner: [String: Any] = [
            "scientific_name": "Hepatica nobilis",
            "identified": true,
            "confidence": "high",
            "french_name": "Hépatique à trois lobes",
            "english_name": "Liverleaf",
            "family": "Ranunculaceae",
            "realm": "plant",
            "animal_group": NSNull(),
            "specificite_fr": "Une des premières fleurs du sous-bois.",
            "fun_fact_fr": "Son nom vient de la théorie des signatures.",
            "season_months": [2, 3, 4],
            "toxicity_danger_fr": NSNull(),
            "similar_species": [],
            "candidates": [],
            "reasoning": "Feuilles trilobées.",
        ]
        let innerData = try JSONSerialization.data(withJSONObject: inner)
        let innerString = String(decoding: innerData, as: UTF8.self)
        let envelope: [String: Any] = [
            "candidates": [["content": ["parts": [["text": innerString]]]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)

        let result = try GeminiIdentificationService.parseResponse(data)
        #expect(result.scientificName == "Hepatica nobilis")
        #expect(result.frenchName == "Hépatique à trois lobes")
        #expect(result.realm == .plant)
        #expect(result.confidence == .high)
        #expect(result.seasonMonths == [2, 3, 4])
        #expect(!result.needsReview)
    }
}
