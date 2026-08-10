import Foundation

/// Builds and sends the Gemini `generateContent` identification request and
/// decodes the structured result. The request body and response parsing are
/// separated out as pure functions so both are unit-testable without a network
/// call or an API key.
public struct GeminiIdentificationService: Sendable {
    private let http: HTTPClient
    private let model: String

    public init(http: HTTPClient = URLSessionHTTPClient(), model: String = FlaunedexConfig.geminiModel) {
        self.http = http
        self.model = model
    }

    /// Gemini 3.x reasoning depth. `low` is the fast default identification pass;
    /// `high` is the escalation used when the first pass is unsure.
    public enum ThinkingLevel: String, Sendable { case low, high }

    // MARK: Request construction (pure)

    public static func endpointURL(model: String) -> URL {
        // Build by string so the `:generateContent` suffix isn't percent-encoded.
        URL(string: "\(FlaunedexConfig.geminiBaseURL.absoluteString)/models/\(model):generateContent")!
    }

    /// The full request body as ordered JSON.
    ///
    /// `hintScientificName` is used by the review flow: when the user picks one
    /// of the candidates, the model is asked to confirm and describe that
    /// species rather than identify from scratch.
    public static func requestBody(
        base64Image: String,
        mimeType: String,
        thinkingLevel: ThinkingLevel,
        hintScientificName: String? = nil
    ) -> JSONValue {
        var instruction = GeminiSchema.userInstruction
        if let hint = hintScientificName, !hint.isEmpty {
            instruction += " " + GeminiSchema.hintInstruction(for: hint)
        }
        return .obj([
            ("systemInstruction", .obj([
                ("parts", .arr([.obj([("text", .str(GeminiSchema.systemPrompt))])])),
            ])),
            ("contents", .arr([
                .obj([
                    ("role", .str("user")),
                    ("parts", .arr([
                        .obj([("inlineData", .obj([
                            ("mimeType", .str(mimeType)),
                            ("data", .str(base64Image)),
                        ]))]),
                        .obj([("text", .str(instruction))]),
                    ])),
                ]),
            ])),
            ("generationConfig", .obj([
                ("responseMimeType", .str("application/json")),
                ("responseSchema", GeminiSchema.responseSchema),
                ("temperature", .int(0)),
                ("thinkingConfig", .obj([("thinkingLevel", .str(thinkingLevel.rawValue))])),
            ])),
        ])
    }

    public func makeRequest(
        base64Image: String,
        mimeType: String = "image/heic",
        apiKey: String,
        thinkingLevel: ThinkingLevel = .low,
        hintScientificName: String? = nil
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw FlaunedexNetworkError.missingAPIKey }
        var request = URLRequest(url: Self.endpointURL(model: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try Self.requestBody(
            base64Image: base64Image, mimeType: mimeType,
            thinkingLevel: thinkingLevel, hintScientificName: hintScientificName
        ).encoded()
        return request
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

    /// Extract and decode the JSON payload the model returned in its text part.
    public static func parseResponse(_ data: Data) throws -> GeminiIdentification {
        let wrapper: GenerateContentResponse
        do {
            wrapper = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        } catch {
            throw FlaunedexNetworkError.decoding("Gemini envelope: \(error)")
        }
        let text = (wrapper.candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
        guard let jsonData = text.data(using: .utf8), !text.isEmpty else {
            throw FlaunedexNetworkError.decoding("Gemini returned no text part")
        }
        do {
            return try JSONDecoder().decode(GeminiIdentification.self, from: jsonData)
        } catch {
            throw FlaunedexNetworkError.decoding("Gemini payload: \(error)")
        }
    }

    // MARK: Networked call

    /// Identify a species from a base64-encoded image.
    public func identify(
        base64Image: String,
        mimeType: String = "image/heic",
        apiKey: String,
        thinkingLevel: ThinkingLevel = .low,
        hintScientificName: String? = nil
    ) async throws -> GeminiIdentification {
        let request = try makeRequest(
            base64Image: base64Image, mimeType: mimeType, apiKey: apiKey,
            thinkingLevel: thinkingLevel, hintScientificName: hintScientificName
        )
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw FlaunedexNetworkError.badStatus(response.statusCode)
        }
        return try Self.parseResponse(data)
    }
}
