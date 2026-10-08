import Testing
import Foundation
@testable import FlaunedexCore

struct RecipeSchemaTests {

    @Test func endpointMatchesTheConfiguredModel() {
        #expect(RecipeGenerationService.endpointURL(model: "gemini-3.6-flash").absoluteString ==
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent")
    }

    /// The single most important property of this feature: the model is not
    /// asked nicely for metric units, it is given a vocabulary that contains
    /// nothing else.
    @Test func theUnitVocabularyOfferedToTheModelIsMetricOnly() throws {
        let schema = try JSONSerialization.jsonObject(with: RecipeSchema.responseSchema.encoded())
        let root = try #require(schema as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let ingredients = try #require(properties["ingredients"] as? [String: Any])
        let item = try #require(ingredients["items"] as? [String: Any])
        let itemProperties = try #require(item["properties"] as? [String: Any])
        let unit = try #require(itemProperties["unit"] as? [String: Any])
        let allowed = try #require(unit["enum"] as? [String])

        #expect(allowed.contains("g"))
        #expect(allowed.contains("ml"))
        #expect(allowed.contains("c. à soupe"))
        for banned in ["cup", "cups", "oz", "ounce", "lb", "pound", "tasse", "pint", "quart", "fl oz"] {
            #expect(!allowed.contains(banned), "\(banned) must not be expressible")
        }
    }

    @Test func schemaPutsTheTitleFirstAndIngredientsBeforeSteps() throws {
        let schema = try JSONSerialization.jsonObject(with: RecipeSchema.responseSchema.encoded())
        let root = try #require(schema as? [String: Any])
        let ordering = try #require(root["propertyOrdering"] as? [String])
        #expect(ordering.first == "title")
        let ingredientsAt = try #require(ordering.firstIndex(of: "ingredients"))
        let stepsAt = try #require(ordering.firstIndex(of: "steps"))
        #expect(ingredientsAt < stepsAt)
    }

    @Test func promptStatesTheMeasurementRules() {
        let prompt = RecipeSchema.systemPrompt
        #expect(prompt.contains("grammes"))
        #expect(prompt.contains("Celsius"))
        #expect(prompt.contains("Jamais de Fahrenheit"))
        #expect(prompt.contains("Jamais de tasses"))
    }

    @Test func userInstructionCarriesEveryConstraintTheCookGave() {
        let instruction = RecipeSchema.userInstruction(request: RecipeRequest(
            query: "une tarte aux poireaux", servings: 2,
            constraints: "végétarien, sans gluten", maxMinutes: 45
        ))
        #expect(instruction.contains("une tarte aux poireaux"))
        #expect(instruction.contains("2 personnes"))
        #expect(instruction.contains("végétarien, sans gluten"))
        #expect(instruction.contains("45 minutes"))
    }

    @Test func singleServingIsWrittenInTheSingular() {
        let instruction = RecipeSchema.userInstruction(request: RecipeRequest(query: "un oeuf mollet", servings: 1))
        #expect(instruction.contains("1 personne."))
    }

    @Test func servingsCannotBeZeroOrNegative() {
        #expect(RecipeRequest(query: "x", servings: 0).servings == 1)
        #expect(RecipeRequest(query: "x", servings: -3).servings == 1)
    }
}

struct RecipeRequestBodyTests {

    private func body(_ request: RecipeRequest,
                      revision: RecipeGenerationService.Revision? = nil) throws -> [String: Any] {
        let data = try RecipeGenerationService.requestBody(request: request, revision: revision).encoded()
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func bodyCarriesSchemaSystemPromptAndInstruction() throws {
        let object = try body(RecipeRequest(query: "un risotto aux champignons", servings: 4))
        let generation = try #require(object["generationConfig"] as? [String: Any])
        #expect(generation["responseMimeType"] as? String == "application/json")
        #expect(generation["responseSchema"] != nil)
        #expect(generation["temperature"] == nil, "Gemini 3 models are meant to run at their default temperature")
        #expect(object["systemInstruction"] != nil)

        let contents = try #require(object["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let text = try #require(parts.compactMap { $0["text"] as? String }.first)
        #expect(text.contains("un risotto aux champignons"))
    }

    @Test func revisionSendsTheCurrentRecipeAndTheChange() throws {
        let existing = RecipeTextFormat.render(RecipeTextRoundTripTests.tarteTatin)
        let object = try body(
            RecipeRequest(query: "Tarte Tatin", servings: 6),
            revision: .init(existingText: existing, change: "sans lactose")
        )
        let contents = try #require(object["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let text = try #require(parts.compactMap { $0["text"] as? String }.first)
        #expect(text.contains("sans lactose"))
        #expect(text.contains("# Tarte Tatin"), "the model sees the recipe it is amending")
    }

    @Test func makeRequestRejectsAnEmptyKeyAndSetsTheHeaders() throws {
        let service = RecipeGenerationService(model: "gemini-3.6-flash")
        #expect(throws: FlaunedexNetworkError.missingAPIKey) {
            _ = try service.makeRequest(request: RecipeRequest(query: "x"), apiKey: "")
        }
        let request = try service.makeRequest(request: RecipeRequest(query: "x"), apiKey: "secret-key")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "secret-key")
        #expect(request.httpBody != nil)
    }
}

struct RecipeResponseParsingTests {

    /// Build the envelope Gemini actually returns: the recipe object as a JSON
    /// string inside a text part.
    private func envelope(_ recipe: [String: Any]) throws -> Data {
        let inner = try JSONSerialization.data(withJSONObject: recipe)
        let wrapper: [String: Any] = [
            "candidates": [["content": ["parts": [["text": String(decoding: inner, as: UTF8.self)]]]]]
        ]
        return try JSONSerialization.data(withJSONObject: wrapper)
    }

    private var wellFormed: [String: Any] {
        [
            "title": "Risotto aux champignons",
            "summary_fr": "Un risotto crémeux aux cèpes.",
            "servings": 4,
            "prep_minutes": 15,
            "cook_minutes": 25,
            "difficulty": "moyen",
            "course": "plat",
            "cuisine": "italienne",
            "ingredients": [
                ["quantity": 300, "unit": "g", "name": "riz arborio", "note": NSNull()],
                ["quantity": 1, "unit": "l", "name": "bouillon de volaille", "note": "chaud"],
                ["quantity": NSNull(), "unit": "au goût", "name": "Poivre", "note": NSNull()],
                ["quantity": 2, "unit": "pièce", "name": "échalotes", "note": NSNull()],
            ],
            "steps": [
                ["text": "Faire suer les échalotes.", "minutes": NSNull()],
                ["text": "Ajouter le riz et nacrer.", "minutes": 2],
            ],
            "chef_tip_fr": "Verser le bouillon louche par louche.",
            "allergens_fr": ["lait"],
            "photo_query": "Risotto",
            "tags": ["plat", "italien"],
        ]
    }

    @Test func decodesAWellFormedRecipe() throws {
        let draft = try RecipeGenerationService.parseResponse(try envelope(wellFormed))
        #expect(draft.title == "Risotto aux champignons")
        #expect(draft.servings == 4)
        #expect(draft.difficulty == .moyen)
        #expect(draft.course == .plat)
        #expect(draft.cuisine == "italienne")
        #expect(draft.steps.count == 2)
        #expect(draft.steps[1].minutes == 2)
        #expect(draft.allergensFR == ["lait"])
        #expect(draft.photoQuery == "Risotto")
    }

    @Test func awkwardUnitsAreFoldedAwayOnArrival() throws {
        let draft = try RecipeGenerationService.parseResponse(try envelope(wellFormed))
        let pepper = try #require(draft.ingredients.first { $0.name == "Poivre" })
        #expect(pepper.unit == nil)
        #expect(pepper.quantity == nil)
        #expect(pepper.note == "au goût")

        let shallots = try #require(draft.ingredients.first { $0.name == "échalotes" })
        #expect(shallots.unit == nil, "'2 pièces d'échalotes' reads worse than '2 échalotes'")
        #expect(shallots.quantity == 2)
    }

    @Test func imperialSlippingThroughIsConvertedBeforeItIsEverStored() throws {
        var recipe = wellFormed
        recipe["ingredients"] = [
            ["quantity": 2, "unit": "cups", "name": "farine", "note": NSNull()],
            ["quantity": 4, "unit": "oz", "name": "beurre", "note": NSNull()],
        ]
        let draft = try RecipeGenerationService.parseResponse(try envelope(recipe))
        #expect(draft.ingredients[0].unit == .milliliter)
        #expect(draft.ingredients[0].quantity == 475)
        #expect(draft.ingredients[1].unit == .gram)
        #expect(draft.ingredients[1].quantity == 115)
    }

    @Test func fahrenheitInsideAStepIsConvertedBeforeItIsEverStored() throws {
        var recipe = wellFormed
        recipe["steps"] = [["text": "Preheat the oven to 400°F.", "minutes": NSNull()]]
        let draft = try RecipeGenerationService.parseResponse(try envelope(recipe))
        #expect(draft.steps[0].text == "Preheat the oven to 205 °C.")
    }

    @Test func unknownEnumValuesDegradeInsteadOfLosingTheRecipe() throws {
        var recipe = wellFormed
        recipe["difficulty"] = "impossible"
        recipe["course"] = "brunch"
        let draft = try RecipeGenerationService.parseResponse(try envelope(recipe))
        #expect(draft.difficulty == nil)
        #expect(draft.course == nil)
        #expect(draft.title == "Risotto aux champignons", "the rest of the recipe survives")
    }

    @Test func missingOptionalFieldsAreTolerated() throws {
        let minimal: [String: Any] = [
            "title": "Pain perdu",
            "servings": 2,
            "ingredients": [["quantity": 4, "unit": "tranche", "name": "pain rassis", "note": NSNull()]],
            "steps": [["text": "Tremper le pain.", "minutes": NSNull()]],
        ]
        let draft = try RecipeGenerationService.parseResponse(try envelope(minimal))
        #expect(draft.title == "Pain perdu")
        #expect(draft.summaryFR == nil)
        #expect(draft.allergensFR.isEmpty)
        #expect(draft.tags.isEmpty)
        #expect(draft.ingredients[0].unit == .slice)
    }

    @Test func namelessIngredientsAndEmptyStepsAreDropped() throws {
        var recipe = wellFormed
        recipe["ingredients"] = [
            ["quantity": 300, "unit": "g", "name": "riz", "note": NSNull()],
            ["quantity": 1, "unit": "g", "name": "  ", "note": NSNull()],
        ]
        recipe["steps"] = [["text": "  ", "minutes": NSNull()], ["text": "Servir.", "minutes": NSNull()]]
        let draft = try RecipeGenerationService.parseResponse(try envelope(recipe))
        #expect(draft.ingredients.count == 1)
        #expect(draft.steps.count == 1)
    }

    @Test func anEmptyEnvelopeIsAnError() {
        let empty = Data(#"{"candidates": []}"#.utf8)
        #expect(throws: FlaunedexNetworkError.self) {
            _ = try RecipeGenerationService.parseResponse(empty)
        }
    }

    @Test func aGeneratedRecipeStillRoundTripsThroughItsOwnText() throws {
        let draft = try RecipeGenerationService.parseResponse(try envelope(wellFormed))
        var expected = draft
        expected.photoQuery = nil
        #expect(RecipeTextFormat.parse(RecipeTextFormat.render(draft)).draft == expected)
    }
}

struct DishPhotoTests {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    @Test func searchURLTargetsArticlesAndAsksForTheLeadImage() {
        let url = DishPhotoEndpoints.search(query: "Tarte Tatin", host: FlaunedexConfig.frenchWikipediaActionAPI)
        let string = url.absoluteString
        #expect(string.hasPrefix("https://fr.wikipedia.org/w/api.php"))
        #expect(string.contains("generator=search"))
        #expect(string.contains("gsrnamespace=0"), "search stays inside real articles")
        #expect(string.contains("Tarte%20Tatin") || string.contains("Tarte+Tatin"))
        #expect(string.contains("piprop=original"))
    }

    @Test func analyticsParametersAreStrippedFromImageURLs() {
        let raw = "https://upload.wikimedia.org/wikipedia/commons/e/e5/Tarte.jpg?utm_source=fr.wikipedia.org&utm_campaign=api"
        #expect(DishPhotoEndpoints.cleanedImageURL(raw)?.absoluteString ==
                "https://upload.wikimedia.org/wikipedia/commons/e/e5/Tarte.jpg")
    }

    @Test func parsesThePageIntoAPhotoWithItsCommonsFile() throws {
        let json = """
        { "query": { "pages": [ {
            "title": "Tarte Tatin", "index": 1,
            "fullurl": "https://fr.wikipedia.org/wiki/Tarte_Tatin",
            "pageimage": "Tarte_Tatin_a_la_Michalak.jpg",
            "original": { "source": "https://upload.wikimedia.org/wikipedia/commons/e/e5/Tarte.jpg?utm_source=x" },
            "thumbnail": { "source": "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/Tarte.jpg/600px-Tarte.jpg?utm_source=x" }
        } ] } }
        """
        let photo = try #require(try DishPhotoEndpoints.parse(data(json)))
        #expect(photo.pageTitle == "Tarte Tatin")
        #expect(photo.imageURL.absoluteString == "https://upload.wikimedia.org/wikipedia/commons/e/e5/Tarte.jpg")
        #expect(photo.commonsFileTitle == "File:Tarte_Tatin_a_la_Michalak.jpg")
        #expect(photo.articleURL?.absoluteString == "https://fr.wikipedia.org/wiki/Tarte_Tatin")
    }

    @Test func anArticleWithNoImageIsNotAnError() throws {
        let json = #"{ "query": { "pages": [ { "title": "Plat obscur" } ] } }"#
        #expect(try DishPhotoEndpoints.parse(data(json)) == nil)
    }

    @Test func noResultsAtAllIsNotAnError() throws {
        #expect(try DishPhotoEndpoints.parse(data(#"{ "batchcomplete": true }"#)) == nil)
    }

    @Test func thumbnailAloneIsEnoughToShowSomething() throws {
        let json = """
        { "query": { "pages": [ { "title": "X",
            "thumbnail": { "source": "https://upload.wikimedia.org/thumb.jpg" } } ] } }
        """
        let photo = try #require(try DishPhotoEndpoints.parse(data(json)))
        #expect(photo.imageURL.absoluteString == "https://upload.wikimedia.org/thumb.jpg")
    }
}
