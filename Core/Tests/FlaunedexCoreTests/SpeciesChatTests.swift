import Testing
import Foundation
@testable import FlaunedexCore

struct SpeciesChatTests {

    private let fox = SpeciesChatContext(
        frenchName: "Renard roux", scientificName: "Vulpes vulpes", family: "Canidae",
        specificiteFR: "Le plus répandu des carnivores sauvages d'Europe.",
        funFactFR: "Il chasse à l'oreille.", toxicityDangerFR: nil
    )

    private func contents(_ body: JSONValue) throws -> [[String: Any]] {
        let object = try #require(try JSONSerialization.jsonObject(with: body.encoded()) as? [String: Any])
        return try #require(object["contents"] as? [[String: Any]])
    }

    private func texts(_ content: [String: Any]) -> [String] {
        ((content["parts"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }
    }

    @Test func theFirstQuestionComesWithTheBriefingAndThePhoto() throws {
        let body = SpeciesChatService.requestBody(context: fox, history: [], question: "Est-ce un mâle ?",
                                                  imageBase64: "AAAA")
        let turns = try contents(body)
        #expect(turns.count == 1)
        #expect(turns[0]["role"] as? String == "user")
        let parts = try #require(turns[0]["parts"] as? [[String: Any]])
        #expect(parts.count == 3, "briefing, photo, question")
        #expect(texts(turns[0]).first?.contains("Renard roux (Vulpes vulpes)") == true)
        #expect(parts.contains { $0["inlineData"] != nil })
        #expect(texts(turns[0]).last == "Est-ce un mâle ?")
    }

    @Test func historyIsReplayedInOrderAndTheQuestionComesLast() throws {
        let history = [
            ChatTurn(role: .user, text: "Où vit-il ?"),
            ChatTurn(role: .model, text: "Partout en Europe."),
        ]
        let turns = try contents(SpeciesChatService.requestBody(
            context: fox, history: history, question: "Et en ville ?", imageBase64: nil))
        #expect(turns.map { $0["role"] as? String } == ["user", "model", "user"])
        #expect(texts(turns[0]).last == "Où vit-il ?")
        #expect(texts(turns[1]) == ["Partout en Europe."])
        #expect(texts(turns[2]) == ["Et en ville ?"])
        #expect(!(turns[0]["parts"] as? [[String: Any]] ?? []).contains { $0["inlineData"] != nil },
                "no photo, no image part")
    }

    @Test func thePromptForbidsEdibilityAdvice() {
        #expect(SpeciesChatPrompt.systemPrompt.contains("JAMAIS de conseil de consommation"))
    }

    @Test func briefingLeavesOutWhatIsUnknown() {
        let bare = SpeciesChatContext(frenchName: nil, scientificName: "Hepatica nobilis")
        let text = SpeciesChatPrompt.briefing(bare)
        #expect(text.contains("Hepatica nobilis."))
        #expect(!text.contains("Famille"))
        #expect(!text.contains("Prudence"))
    }

    @Test func theAnswerIsTheTextWithoutThoughts() throws {
        let data = Data(#"{"candidates":[{"content":{"parts":[{"text":"réflexion","thought":true},{"text":"  Il vit partout. "}]}}]}"#.utf8)
        #expect(try SpeciesChatService.parseResponse(data) == "Il vit partout.")
    }

    @Test func anEmptyAnswerIsAnError() {
        #expect(throws: FlaunedexNetworkError.self) {
            _ = try SpeciesChatService.parseResponse(Data(#"{"candidates":[]}"#.utf8))
        }
    }

    @Test func makeRequestNeedsAKey() {
        #expect(throws: FlaunedexNetworkError.missingAPIKey) {
            _ = try SpeciesChatService().makeRequest(context: fox, history: [], question: "x",
                                                     imageBase64: nil, apiKey: "")
        }
    }

    @Test func highlightsAreFoundAndMerged() {
        let text = "Le renard chasse la nuit. Le renard chasse aussi le jour."
        let ranges = HighlightRanges.ranges(of: ["renard chasse", "chasse la nuit"], in: text)
        #expect(ranges.map { String(text[$0]) } == ["renard chasse la nuit", "renard chasse"])
        #expect(HighlightRanges.ranges(of: ["", "absent"], in: text).isEmpty)
    }

    @Test func turnsAndHighlightsSurviveARoundTrip() throws {
        let turn = ChatTurn(role: .model, text: "Bonjour")
        let highlight = SpeciesHighlight(text: "Bonjour", messageID: turn.id)
        let data = try JSONEncoder().encode([turn])
        #expect(try JSONDecoder().decode([ChatTurn].self, from: data) == [turn])
        let h = try JSONEncoder().encode([highlight])
        #expect(try JSONDecoder().decode([SpeciesHighlight].self, from: h) == [highlight])
    }
}
