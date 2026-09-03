import Foundation

/// Builds and sends the Gemini request that writes a recipe, and decodes the
/// structured result. Request construction and parsing are pure static
/// functions, so both are tested without a network call or an API key, exactly
/// as the species identifier is.
public struct RecipeGenerationService: Sendable {
    private let http: HTTPClient
    private let model: String

    public init(http: HTTPClient = URLSessionHTTPClient(), model: String = FlaunedexConfig.geminiModel) {
        self.http = http
        self.model = model
    }

    /// Asking for a change to an existing recipe rather than a new dish.
    public struct Revision: Sendable, Equatable {
        /// The current recipe, rendered by `RecipeTextFormat`.
        public let existingText: String
        /// What to change: "sans lactose", "pour 2 personnes", "moins sucré".
        public let change: String
        public init(existingText: String, change: String) {
            self.existingText = existingText
            self.change = change
        }
    }

    // MARK: Request construction (pure)

    public static func endpointURL(model: String) -> URL {
        // Built by string so the ":generateContent" suffix is not percent-encoded.
        URL(string: "\(FlaunedexConfig.geminiBaseURL.absoluteString)/models/\(model):generateContent")!
    }

    public static func requestBody(
        request: RecipeRequest,
        revision: Revision? = nil,
        thinkingLevel: GeminiIdentificationService.ThinkingLevel = .low
    ) -> JSONValue {
        var instruction = RecipeSchema.userInstruction(request: request)
        if let revision {
            instruction += "\n\n" + RecipeSchema.revisionInstruction(
                existing: revision.existingText, change: revision.change
            )
        }
        return .obj([
            ("systemInstruction", .obj([
                ("parts", .arr([.obj([("text", .str(RecipeSchema.systemPrompt))])])),
            ])),
            ("contents", .arr([
                .obj([
                    ("role", .str("user")),
                    ("parts", .arr([.obj([("text", .str(instruction))])])),
                ]),
            ])),
            ("generationConfig", .obj([
                ("responseMimeType", .str("application/json")),
                ("responseSchema", RecipeSchema.responseSchema),
                // A little warmth: two requests for "tarte aux pommes" should
                // not return a byte-identical recipe, but the measurements must
                // not wander either.
                ("temperature", .double(0.4)),
                ("thinkingConfig", .obj([("thinkingLevel", .str(thinkingLevel.rawValue))])),
            ])),
        ])
    }

    public func makeRequest(
        request: RecipeRequest,
        apiKey: String,
        revision: Revision? = nil,
        thinkingLevel: GeminiIdentificationService.ThinkingLevel = .low
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw FlaunedexNetworkError.missingAPIKey }
        var urlRequest = URLRequest(url: Self.endpointURL(model: model))
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

    public static func parseResponse(_ data: Data) throws -> RecipeDraft {
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

    /// Decode the recipe object the model wrote inside its text part.
    public static func parsePayload(_ data: Data) throws -> RecipeDraft {
        do {
            return try JSONDecoder().decode(GeneratedRecipe.self, from: data).toDraft()
        } catch {
            throw FlaunedexNetworkError.decoding("Recipe payload: \(error)")
        }
    }

    // MARK: Networked call

    public func generate(
        request: RecipeRequest,
        apiKey: String,
        revision: Revision? = nil,
        thinkingLevel: GeminiIdentificationService.ThinkingLevel = .low
    ) async throws -> RecipeDraft {
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

/// The raw shape Gemini returns, decoded leniently.
///
/// Closed-vocabulary fields arrive as plain strings and are resolved through
/// typed accessors, so a value outside the enum degrades to nil rather than
/// throwing away a whole good recipe. Units go through `MetricConversion`, which
/// means that even in the case the schema fails to hold the model to metric,
/// a cup becomes millilitres before it is ever stored.
struct GeneratedRecipe: Decodable {
    let title: String?
    let summaryFR: String?
    let servings: Int?
    let prepMinutes: Int?
    let cookMinutes: Int?
    let difficulty: String?
    let course: String?
    let cuisine: String?
    let ingredients: [Ingredient]?
    let steps: [Step]?
    let chefTipFR: String?
    let allergensFR: [String]?
    let photoQuery: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case title
        case summaryFR = "summary_fr"
        case servings
        case prepMinutes = "prep_minutes"
        case cookMinutes = "cook_minutes"
        case difficulty, course, cuisine, ingredients, steps
        case chefTipFR = "chef_tip_fr"
        case allergensFR = "allergens_fr"
        case photoQuery = "photo_query"
        case tags
    }

    struct Ingredient: Decodable {
        let quantity: Double?
        let unit: String?
        let name: String?
        let note: String?
    }

    struct Step: Decodable {
        let text: String?
        let minutes: Int?
    }

    func toDraft() -> RecipeDraft {
        let mappedIngredients: [RecipeIngredient] = (ingredients ?? []).compactMap { raw in
            guard let name = raw.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            var quantity = raw.quantity
            var unit: MetricUnit?
            if let converted = MetricConversion.toMetric(quantity: raw.quantity ?? 0, unit: raw.unit) {
                unit = converted.unit
                // A unit with no quantity ("au goût") must not gain a phantom 0.
                quantity = raw.quantity == nil ? nil : converted.quantity
            }
            return RecipeIngredient(quantity: quantity, unit: unit, name: name, note: raw.note)
        }

        let mappedSteps: [RecipeStep] = (steps ?? []).compactMap { raw in
            guard let text = raw.text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return RecipeStep(text: text, minutes: raw.minutes)
        }

        return RecipeDraft(
            title: title ?? "Recette",
            summaryFR: summaryFR,
            servings: servings,
            prepMinutes: prepMinutes,
            cookMinutes: cookMinutes,
            difficulty: difficulty.flatMap { RecipeDifficulty(rawValue: $0.lowercased()) },
            course: course.flatMap { RecipeCourse(rawValue: $0.lowercased()) },
            cuisine: cuisine,
            ingredients: mappedIngredients,
            steps: mappedSteps,
            chefTipFR: chefTipFR,
            allergensFR: allergensFR ?? [],
            photoQuery: photoQuery,
            tags: tags ?? []
        ).normalized()
    }
}
