import Foundation
import SwiftData
import Observation
import FlaunedexCore

/// The conversation about a species: questions to Gemini with the photo and
/// what the identification said, the answers kept on the species, and the
/// passages the observer highlights, which go on its card.
@MainActor
@Observable
final class SpeciesChatStore {
    private let context: ModelContext
    private let keys: APIKeys
    private let service = SpeciesChatService()
    private let photos = PhotoStore()

    /// The question in flight for a species (by GBIF key), shown while the
    /// answer is written.
    var pending: [Int: String] = [:]
    /// The last failure for a species, in French.
    var errors: [Int: String] = [:]
    /// The question that failed, so it can be sent again without retyping it.
    var failed: [Int: String] = [:]

    init(context: ModelContext, keys: APIKeys) {
        self.context = context
        self.keys = keys
    }

    var hasGeminiKey: Bool { keys.hasGeminiKey }

    /// Ask a question about `species`. The photo sent is the sighting's, or the
    /// latest one taken of the species; like for identification, a small copy
    /// with no GPS. The question and its answer are kept only once the answer
    /// has arrived, so the conversation never ends on an unanswered question.
    func ask(_ question: String, about species: Species, photo sighting: Sighting? = nil) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, pending[species.gbifKey] == nil else { return }
        guard keys.hasGeminiKey else {
            errors[species.gbifKey] = "Ajoutez votre clé Gemini dans Réglages (la roue dentée en haut à droite)."
            return
        }
        errors[species.gbifKey] = nil
        failed[species.gbifKey] = nil
        pending[species.gbifKey] = text
        defer { pending[species.gbifKey] = nil }

        let source = sighting ?? (species.sightings ?? [])
            .filter { !$0.photoRelativePath.isEmpty }
            .max { $0.capturedAt < $1.capturedAt }
        let image = source
            .flatMap { photos.load($0.photoRelativePath) }
            .flatMap { UploadImage.prepare($0) }?
            .base64EncodedString()
        let briefing = SpeciesChatContext(
            frenchName: species.frenchName, scientificName: species.scientificName, family: species.family,
            specificiteFR: species.specificiteFR, funFactFR: species.funFactFR,
            toxicityDangerFR: species.toxicityDangerFR
        )
        do {
            let answer = try await service.ask(context: briefing, history: species.chat, question: text,
                                               imageBase64: image, apiKey: keys.geminiKey)
            species.chat.append(ChatTurn(role: .user, text: text))
            species.chat.append(ChatTurn(role: .model, text: answer))
            save()
        } catch {
            errors[species.gbifKey] = Self.frenchMessage(for: error)
            failed[species.gbifKey] = text
        }
    }

    /// Keep a passage on the species card. The same passage twice is kept once.
    func highlight(_ passage: String, from turn: ChatTurn?, on species: Species) {
        let text = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !species.highlights.contains(where: { $0.text == text }) else { return }
        species.highlights.append(SpeciesHighlight(text: text, messageID: turn?.id))
        save()
    }

    func removeHighlight(_ highlight: SpeciesHighlight, from species: Species) {
        species.highlights.removeAll { $0.id == highlight.id }
        save()
    }

    /// Start the conversation over. The highlights stay on the card.
    func clearConversation(of species: Species) {
        species.chat = []
        save()
    }

    private func save() {
        try? context.save()
    }

    static func frenchMessage(for error: Error) -> String {
        guard let network = error as? FlaunedexNetworkError else {
            return "La question n'est pas partie. Vérifiez votre connexion et réessayez."
        }
        switch network {
        case .missingAPIKey:
            return "Ajoutez votre clé Gemini dans Réglages."
        case .badStatus(let code) where code == 400 || code == 403:
            return "Clé Gemini refusée (\(code)). Vérifiez-la dans Réglages."
        case .badStatus(let code) where code == 429:
            return "Trop de questions d'affilée. Patientez un instant, puis réessayez."
        case .badStatus(let code):
            return "Le service a répondu \(code). Réessayez dans un moment."
        case .invalidResponse, .decoding:
            return "La réponse reçue était illisible. Reformulez la question, puis réessayez."
        }
    }
}
