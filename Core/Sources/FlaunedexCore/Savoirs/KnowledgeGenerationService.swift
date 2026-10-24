import Foundation

/// Builds and sends the Gemini request that writes a knowledge card, and
/// decodes the structured result. Construction and parsing are pure static
/// functions, tested without a network call, exactly as for recipes.
public struct KnowledgeGenerationService: Sendable {
    private let http: HTTPClient
    private let model: String

    public init(http: HTTPClient = URLSessionHTTPClient(), model: String = FlaunedexConfig.geminiModel) {
        self.http = http
        self.model = model
    }

    /// Asking for a change to an existing card rather than a new one.
    public struct Revision: Sendable, Equatable {
        /// The current card, rendered by `KnowledgeSchema.render`.
        public let existingText: String
        /// What to change: "plus simple", "ajoute les dates clés".
        public let change: String
        public init(existingText: String, change: String) {
            self.existingText = existingText
            self.change = change
        }
    }

    // MARK: Request construction (pure)

    public static func requestBody(
        request: KnowledgeRequest,
        revision: Revision? = nil,
        thinkingLevel: GeminiIdentificationService.ThinkingLevel = .low
    ) -> JSONValue {
        var instruction = KnowledgeSchema.userInstruction(request: request)
        if let revision {
            instruction += "\n\n" + KnowledgeSchema.revisionInstruction(
                existing: revision.existingText, change: revision.change
            )
        }
        return .obj([
            ("systemInstruction", .obj([
                ("parts", .arr([.obj([("text", .str(KnowledgeSchema.systemPrompt))])])),
            ])),
            ("contents", .arr([
                .obj([
                    ("role", .str("user")),
                    ("parts", .arr([.obj([("text", .str(instruction))])])),
                ]),
            ])),
            ("generationConfig", .obj([
                ("responseMimeType", .str("application/json")),
                ("responseSchema", KnowledgeSchema.responseSchema(categories: request.categories)),
                // No temperature, as everywhere else: Gemini 3 is meant to run
                // at its default and can loop below it.
                ("thinkingConfig", .obj([("thinkingLevel", .str(thinkingLevel.rawValue))])),
            ])),
        ])
    }

    public func makeRequest(
        request: KnowledgeRequest,
        apiKey: String,
        revision: Revision? = nil,
        thinkingLevel: GeminiIdentificationService.ThinkingLevel = .low
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw FlaunedexNetworkError.missingAPIKey }
        var urlRequest = URLRequest(url: RecipeGenerationService.endpointURL(model: model))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try Self.requestBody(
            request: request, revision: revision, thinkingLevel: thinkingLevel
        ).encoded()
        return urlRequest
    }

    // MARK: Response parsing (pure)

    private struct GenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    public static func parseResponse(_ data: Data) throws -> KnowledgeDraft {
        let wrapper: GenerateContentResponse
        do {
            wrapper = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        } catch {
            throw FlaunedexNetworkError.decoding("Gemini envelope: \(error)")
        }
        let text = (wrapper.candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty, let payload = text.data(using: .utf8) else {
            throw FlaunedexNetworkError.decoding("Gemini returned no text part")
        }
        return try parsePayload(payload)
    }

    /// Decode the card object the model wrote inside its text part.
    public static func parsePayload(_ data: Data) throws -> KnowledgeDraft {
        do {
            return try JSONDecoder().decode(GeneratedKnowledge.self, from: data).toDraft()
        } catch {
            throw FlaunedexNetworkError.decoding("Knowledge payload: \(error)")
        }
    }

    // MARK: Networked call

    public func generate(
        request: KnowledgeRequest,
        apiKey: String,
        revision: Revision? = nil,
        thinkingLevel: GeminiIdentificationService.ThinkingLevel = .low
    ) async throws -> KnowledgeDraft {
        let urlRequest = try makeRequest(
            request: request, apiKey: apiKey, revision: revision, thinkingLevel: thinkingLevel
        )
        let (data, response) = try await http.data(for: urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw FlaunedexNetworkError.badStatus(response.statusCode)
        }
        return try Self.parseResponse(data)
    }
}

/// The raw shape Gemini returns, decoded leniently: every field optional, so a
/// card with a gap still arrives. The category is matched by the app.
struct GeneratedKnowledge: Decodable {
    let title: String?
    let theme: String?
    let summaryFR: String?
    let etymologyFR: String?
    let bodyFR: String?
    let keyPointsFR: [String]?
    let questionFR: String?
    let answerFR: String?
    let funFactFR: String?
    let wikipediaQuery: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case title, theme, tags
        case summaryFR = "summary_fr"
        case etymologyFR = "etymology_fr"
        case bodyFR = "body_fr"
        case keyPointsFR = "key_points_fr"
        case questionFR = "question_fr"
        case answerFR = "answer_fr"
        case funFactFR = "fun_fact_fr"
        case wikipediaQuery = "wikipedia_query"
    }

    func toDraft() -> KnowledgeDraft {
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return KnowledgeDraft(
            title: cleanTitle.isEmpty ? "Fiche" : cleanTitle,
            category: theme,
            summaryFR: summaryFR,
            etymologyFR: etymologyFR,
            bodyFR: bodyFR ?? "",
            keyPointsFR: keyPointsFR ?? [],
            questionFR: questionFR,
            answerFR: answerFR,
            funFactFR: funFactFR,
            wikipediaQuery: wikipediaQuery,
            tags: tags ?? []
        ).normalized()
    }
}
