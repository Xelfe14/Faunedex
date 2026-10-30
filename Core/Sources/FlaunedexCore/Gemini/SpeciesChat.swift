import Foundation

/// One message of a conversation about a species.
public struct ChatTurn: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, model }

    public var id: UUID
    public var role: Role
    public var text: String
    public var date: Date

    public init(id: UUID = UUID(), role: Role, text: String, date: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

/// A passage of an answer the observer highlighted, kept on the species card.
public struct SpeciesHighlight: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    /// The answer it was taken from, so the passage stays marked there.
    public var messageID: UUID?
    public var date: Date

    public init(id: UUID = UUID(), text: String, messageID: UUID?, date: Date = .now) {
        self.id = id
        self.text = text
        self.messageID = messageID
        self.date = date
    }
}

/// What is already known about the species, given to the model before the
/// first question so it answers about this species and this photo.
public struct SpeciesChatContext: Sendable, Equatable {
    public var frenchName: String?
    public var scientificName: String
    public var family: String?
    public var specificiteFR: String?
    public var funFactFR: String?
    public var toxicityDangerFR: String?

    public init(frenchName: String?, scientificName: String, family: String? = nil,
                specificiteFR: String? = nil, funFactFR: String? = nil, toxicityDangerFR: String? = nil) {
        self.frenchName = frenchName
        self.scientificName = scientificName
        self.family = family
        self.specificiteFR = specificiteFR
        self.funFactFR = funFactFR
        self.toxicityDangerFR = toxicityDangerFR
    }
}

/// The prompt for questions about an identified species.
public enum SpeciesChatPrompt {

    public static let systemPrompt = """
    Tu es un naturaliste expert de la faune et de la flore d'Europe, qui répond aux questions \
    d'un observateur sur une espèce qu'il vient de photographier sur le terrain. Tu as sous les \
    yeux sa photo et ce que l'identification en a dit.

    Règles :
    - Réponds en français, en texte simple : des phrases et de courts paragraphes, sans titres, \
    sans gras ni listes à puces. Sois précis et concret ; en général trois à six phrases suffisent.
    - Uniquement des faits établis. Si tu n'es pas sûr, dis-le. Si la photo ne permet pas de \
    répondre (sexe, âge, sous-espèce…), dis ce qu'il faudrait observer pour trancher.
    - Si la question porte sur la photo, appuie-toi sur ce que tu y vois réellement.
    - Ne donne JAMAIS de conseil de consommation, de cueillette pour manger, ni d'usage médicinal \
    à essayer : rappelle qu'une identification par photo ne suffit pas et signale les dangers.
    - Ne propose pas de déranger, capturer ou cueillir une espèce protégée.
    """

    /// The briefing that opens the conversation, sent with the photo.
    public static func briefing(_ context: SpeciesChatContext) -> String {
        var lines = ["Espèce identifiée sur la photo : \(context.frenchName.map { "\($0) (\(context.scientificName))" } ?? context.scientificName)."]
        if let family = context.family { lines.append("Famille : \(family).") }
        if let text = context.specificiteFR { lines.append("Ce qu'on en a déjà dit : \(text)") }
        if let text = context.funFactFR { lines.append("Anecdote déjà donnée : \(text)") }
        if let text = context.toxicityDangerFR { lines.append("Prudence signalée : \(text)") }
        lines.append("Réponds maintenant aux questions de l'observateur sur cette espèce et sur sa photo.")
        return lines.joined(separator: "\n")
    }
}

/// Sends a question about a species to Gemini, with the photo, the briefing and
/// the conversation so far. Construction and parsing are pure and tested.
public struct SpeciesChatService: Sendable {
    private let http: HTTPClient
    private let model: String

    public init(http: HTTPClient = URLSessionHTTPClient(), model: String = FlaunedexConfig.geminiModel) {
        self.http = http
        self.model = model
    }

    // MARK: Request construction (pure)

    /// The request body. The first user turn carries the briefing and the photo,
    /// then the history alternates as it happened, and the question comes last.
    public static func requestBody(
        context: SpeciesChatContext,
        history: [ChatTurn],
        question: String,
        imageBase64: String?,
        mimeType: String = "image/jpeg"
    ) -> JSONValue {
        let turns = history + [ChatTurn(role: .user, text: question)]
        var contents: [JSONValue] = []
        for (index, turn) in turns.enumerated() {
            var parts: [JSONValue] = []
            if index == 0 {
                parts.append(.obj([("text", .str(SpeciesChatPrompt.briefing(context)))]))
                if let imageBase64 {
                    parts.append(.obj([("inlineData", .obj([
                        ("mimeType", .str(mimeType)),
                        ("data", .str(imageBase64)),
                    ]))]))
                }
            }
            parts.append(.obj([("text", .str(turn.text))]))
            contents.append(.obj([
                ("role", .str(turn.role == .user ? "user" : "model")),
                ("parts", .arr(parts)),
            ]))
        }
        return .obj([
            ("systemInstruction", .obj([
                ("parts", .arr([.obj([("text", .str(SpeciesChatPrompt.systemPrompt))])])),
            ])),
            ("contents", .arr(contents)),
            ("generationConfig", .obj([
                // No temperature, as everywhere else: Gemini 3 runs at its default.
                ("thinkingConfig", .obj([("thinkingLevel", .str(GeminiIdentificationService.ThinkingLevel.low.rawValue))])),
            ])),
        ])
    }

    public func makeRequest(context: SpeciesChatContext, history: [ChatTurn], question: String,
                            imageBase64: String?, apiKey: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw FlaunedexNetworkError.missingAPIKey }
        var request = URLRequest(url: GeminiIdentificationService.endpointURL(model: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try Self.requestBody(context: context, history: history, question: question,
                                                imageBase64: imageBase64).encoded()
        return request
    }

    // MARK: Response parsing (pure)

    private struct Envelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                    let thought: Bool?
                }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    /// The answer's text, without any thought summary the model may include.
    public static func parseResponse(_ data: Data) throws -> String {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw FlaunedexNetworkError.decoding("Gemini envelope: \(error)")
        }
        let text = (envelope.candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw FlaunedexNetworkError.decoding("Gemini returned no answer") }
        return text
    }

    // MARK: Networked call

    public func ask(context: SpeciesChatContext, history: [ChatTurn], question: String,
                    imageBase64: String?, apiKey: String) async throws -> String {
        let request = try makeRequest(context: context, history: history, question: question,
                                      imageBase64: imageBase64, apiKey: apiKey)
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw FlaunedexNetworkError.badStatus(response.statusCode)
        }
        return try Self.parseResponse(data)
    }
}

/// Where highlighted passages sit in a message, to draw them.
public enum HighlightRanges {
    /// Every occurrence of each passage in `text`, merged where they overlap,
    /// in order. Passages are matched exactly as they were selected.
    public static func ranges(of passages: [String], in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for passage in passages where !passage.isEmpty {
            var start = text.startIndex
            while start < text.endIndex, let range = text.range(of: passage, range: start..<text.endIndex) {
                found.append(range)
                start = range.upperBound
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in found {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
