import Testing
import Foundation
@testable import FlaunedexCore

struct KnowledgeSchemaTests {

    private func schemaRoot() throws -> [String: Any] {
        let schema = try JSONSerialization.jsonObject(with: KnowledgeSchema.responseSchema.encoded())
        return try #require(schema as? [String: Any])
    }

    @Test func themesOfferedToTheModelAreExactlyTheAppsShelves() throws {
        let properties = try #require(try schemaRoot()["properties"] as? [String: Any])
        let theme = try #require(properties["theme"] as? [String: Any])
        let allowed = try #require(theme["enum"] as? [String])
        #expect(allowed == KnowledgeTheme.allCases.map(\.rawValue))
    }

    @Test func titleComesFirstAndTheFlashcardAfterTheExplanation() throws {
        let ordering = try #require(try schemaRoot()["propertyOrdering"] as? [String])
        #expect(ordering.first == "title")
        let body = try #require(ordering.firstIndex(of: "body_fr"))
        let question = try #require(ordering.firstIndex(of: "question_fr"))
        #expect(body < question)
        let required = try #require(try schemaRoot()["required"] as? [String])
        #expect(Set(required) == Set(KnowledgeSchema.propertyOrder))
    }

    @Test func promptForbidsInventedFacts() {
        #expect(KnowledgeSchema.systemPrompt.contains("N'invente jamais"))
        #expect(KnowledgeSchema.systemPrompt.contains("sans markdown"))
    }

    @Test func instructionCarriesSubjectDepthAndFocus() {
        let short = KnowledgeSchema.userInstruction(request: KnowledgeRequest(subject: "la photosynthèse"))
        #expect(short.contains("la photosynthèse"))
        #expect(short.contains("l'essentiel"))
        #expect(!short.contains("Insiste"))

        let deep = KnowledgeSchema.userInstruction(request: KnowledgeRequest(
            subject: "la bataille de Marignan", depth: .approfondi, focus: "les dates clés"))
        #expect(deep.contains("approfondi"))
        #expect(deep.contains("Insiste en particulier sur : les dates clés."))
    }

    @Test func blankFocusIsLeftOut() {
        let instruction = KnowledgeSchema.userInstruction(request: KnowledgeRequest(subject: "x", focus: "  "))
        #expect(!instruction.contains("Insiste"))
    }

    @Test func renderedCardShowsEveryPartTheModelNeedsToAmendIt() {
        let text = KnowledgeSchema.render(KnowledgeCardFixtures.photosynthesis)
        #expect(text.hasPrefix("Titre : Photosynthèse"))
        #expect(text.contains("Rubrique : Sciences"))
        #expect(text.contains("- Elle a lieu dans les chloroplastes."))
        #expect(text.contains("Question : "))
        #expect(text.contains("Réponse : "))
    }
}

struct KnowledgeRequestBodyTests {

    private func text(of body: JSONValue) throws -> String {
        let object = try #require(try JSONSerialization.jsonObject(with: body.encoded()) as? [String: Any])
        let contents = try #require(object["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        return try #require(parts.compactMap { $0["text"] as? String }.first)
    }

    @Test func bodyCarriesSchemaAndPromptAndNoTemperature() throws {
        let body = KnowledgeGenerationService.requestBody(request: KnowledgeRequest(subject: "les marées"))
        let object = try #require(try JSONSerialization.jsonObject(with: body.encoded()) as? [String: Any])
        let generation = try #require(object["generationConfig"] as? [String: Any])
        #expect(generation["responseMimeType"] as? String == "application/json")
        #expect(generation["responseSchema"] != nil)
        #expect(generation["temperature"] == nil)
        #expect(object["systemInstruction"] != nil)
        #expect(try text(of: body).contains("les marées"))
    }

    @Test func revisionSendsTheCurrentCardAndTheChange() throws {
        let body = KnowledgeGenerationService.requestBody(
            request: KnowledgeRequest(subject: "Photosynthèse"),
            revision: .init(existingText: KnowledgeSchema.render(KnowledgeCardFixtures.photosynthesis),
                            change: "plus simple")
        )
        let sent = try text(of: body)
        #expect(sent.contains("plus simple"))
        #expect(sent.contains("Titre : Photosynthèse"))
    }

    @Test func makeRequestRejectsAnEmptyKeyAndSetsTheHeaders() throws {
        let service = KnowledgeGenerationService(model: "gemini-3.6-flash")
        #expect(throws: FlaunedexNetworkError.missingAPIKey) {
            _ = try service.makeRequest(request: KnowledgeRequest(subject: "x"), apiKey: "")
        }
        let request = try service.makeRequest(request: KnowledgeRequest(subject: "x"), apiKey: "k")
        #expect(request.url?.absoluteString.hasSuffix("gemini-3.6-flash:generateContent") == true)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "k")
    }
}

struct KnowledgeParsingTests {

    private func envelope(_ card: [String: Any]) throws -> Data {
        let inner = try JSONSerialization.data(withJSONObject: card)
        let wrapper: [String: Any] = [
            "candidates": [["content": ["parts": [["text": String(decoding: inner, as: UTF8.self)]]]]]
        ]
        return try JSONSerialization.data(withJSONObject: wrapper)
    }

    private var wellFormed: [String: Any] {
        [
            "title": "Photosynthèse",
            "theme": "sciences",
            "summary_fr": "Les plantes fabriquent leur matière avec la lumière.",
            "body_fr": "Premier paragraphe.\n\n\n\nDeuxième paragraphe.  ",
            "key_points_fr": ["- Elle a lieu dans les chloroplastes.", "2. Elle libère du dioxygène.", " ", "1.5 milliard d'années d'histoire"],
            "question_fr": "Quel gaz la photosynthèse libère-t-elle ?",
            "answer_fr": "Du dioxygène.",
            "fun_fact_fr": NSNull(),
            "wikipedia_query": "Photosynthèse",
            "tags": ["biologie", "Biologie", "plantes"],
        ]
    }

    @Test func decodesAWellFormedCard() throws {
        let draft = try KnowledgeGenerationService.parseResponse(try envelope(wellFormed))
        #expect(draft.title == "Photosynthèse")
        #expect(draft.theme == .sciences)
        #expect(draft.answerFR == "Du dioxygène.")
        #expect(draft.funFactFR == nil)
        #expect(draft.wikipediaQuery == "Photosynthèse")
    }

    @Test func paragraphsAreEvenedOutAndBulletsStripped() throws {
        let draft = try KnowledgeGenerationService.parseResponse(try envelope(wellFormed))
        #expect(draft.bodyFR == "Premier paragraphe.\n\nDeuxième paragraphe.")
        #expect(draft.keyPointsFR == [
            "Elle a lieu dans les chloroplastes.",
            "Elle libère du dioxygène.",
            "1.5 milliard d'années d'histoire",
        ])
        #expect(draft.tags == ["biologie", "plantes"])
    }

    @Test func anUnknownThemeIsFiledUnderDiversAndALabelIsUnderstood() throws {
        var card = wellFormed
        card["theme"] = "astrologie"
        #expect(try KnowledgeGenerationService.parseResponse(try envelope(card)).theme == .divers)
        card["theme"] = "Géographie"
        #expect(try KnowledgeGenerationService.parseResponse(try envelope(card)).theme == .geographie)
        card["theme"] = "SANTE"
        #expect(try KnowledgeGenerationService.parseResponse(try envelope(card)).theme == .sante)
    }

    @Test func aCardWithMissingFieldsStillArrives() throws {
        let draft = try KnowledgeGenerationService.parsePayload(Data(#"{"body_fr":"Texte."}"#.utf8))
        #expect(draft.title == "Fiche")
        #expect(draft.theme == .divers)
        #expect(draft.bodyFR == "Texte.")
        #expect(draft.keyPointsFR.isEmpty)
    }

    @Test func anEmptyEnvelopeIsADecodingError() {
        #expect(throws: FlaunedexNetworkError.self) {
            _ = try KnowledgeGenerationService.parseResponse(Data(#"{"candidates":[]}"#.utf8))
        }
    }

    @Test func keyPointsTypedOnePerLine() {
        #expect(KnowledgeDraft.keyPoints(fromLines: "• Un\n\n- Deux\n3) Trois\nUn") == ["Un", "Deux", "Trois"])
    }
}

struct ReviewSchedulerTests {

    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    /// 15 October 2026, 21:30 in Paris: late enough that "due tomorrow" and
    /// "due in 24 hours" would differ.
    private var evening: Date {
        paris.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 21, minute: 30))!
    }

    private func day(_ d: Int, month: Int = 10) -> Date {
        paris.date(from: DateComponents(year: 2026, month: month, day: d))!
    }

    @Test func aNewCardIsDue() {
        #expect(ReviewState().isDue(at: evening))
        #expect(ReviewState().isNew)
    }

    @Test func knowingANewCardBringsItBackTomorrowMorning() {
        let next = ReviewScheduler.review(ReviewState(), rating: .good, now: evening, calendar: paris)
        #expect(next.box == 1)
        #expect(next.dueAt == day(16))
        #expect(next.reviewCount == 1)
        #expect(next.lastReviewedAt == evening)
        #expect(!next.isDue(at: evening))
    }

    @Test func easySkipsABox() {
        let next = ReviewScheduler.review(ReviewState(box: 2), rating: .easy, now: evening, calendar: paris)
        #expect(next.box == 4)
        #expect(next.dueAt == day(29))
    }

    @Test func forgettingSendsALearnedCardBackToTheStart() {
        let learned = ReviewState(box: 3, dueAt: day(15), reviewCount: 3)
        let next = ReviewScheduler.review(learned, rating: .again, now: evening, calendar: paris)
        #expect(next.box == 0)
        #expect(next.lapseCount == 1)
        #expect(next.isDue(at: evening), "a missed card comes back in the same session")

        let new = ReviewScheduler.review(ReviewState(), rating: .again, now: evening, calendar: paris)
        #expect(new.lapseCount == 0, "a card never learned can't be forgotten")
    }

    @Test func theTopBoxIsACeiling() {
        let top = ReviewState(box: ReviewScheduler.maxBox)
        let next = ReviewScheduler.review(top, rating: .easy, now: evening, calendar: paris)
        #expect(next.box == ReviewScheduler.maxBox)
        #expect(ReviewScheduler.daysUntil(next.dueAt!, from: evening, calendar: paris) == 120)
    }

    @Test func delaysReadNaturally() {
        #expect(ReviewScheduler.frenchDelay(days: 0) == "aujourd'hui")
        #expect(ReviewScheduler.frenchDelay(days: 1) == "demain")
        #expect(ReviewScheduler.frenchDelay(days: 7) == "dans 7 jours")
        #expect(ReviewScheduler.frenchDelay(days: 14) == "dans 2 semaines")
        #expect(ReviewScheduler.frenchDelay(days: 30) == "dans 1 mois")
        #expect(ReviewScheduler.frenchDelay(days: 120) == "dans 4 mois")
    }

    @Test func buttonCaptionsPreviewTheSchedule() {
        let state = ReviewState(box: 1)
        #expect(ReviewScheduler.preview(state, rating: .again) == "tout de suite")
        #expect(ReviewScheduler.preview(state, rating: .good) == "dans 3 jours")
        #expect(ReviewScheduler.preview(state, rating: .easy) == "dans 7 jours")
    }
}

enum KnowledgeCardFixtures {
    static let photosynthesis = KnowledgeDraft(
        title: "Photosynthèse",
        theme: .sciences,
        summaryFR: "Les plantes fabriquent leur matière à partir de lumière, d'eau et de CO₂.",
        bodyFR: "La photosynthèse transforme l'énergie lumineuse en énergie chimique.",
        keyPointsFR: ["Elle a lieu dans les chloroplastes.", "Elle libère du dioxygène."],
        questionFR: "Quel gaz la photosynthèse libère-t-elle ?",
        answerFR: "Du dioxygène.",
        wikipediaQuery: "Photosynthèse",
        tags: ["biologie"]
    )
}
