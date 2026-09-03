import Testing
import Foundation
@testable import FlaunedexCore

/// A recipe written by a chatbot only becomes the cook's own once they can
/// rewrite it by hand. That hinges on one property: text produced by the app
/// must parse back into exactly the recipe it came from. Everything here exists
/// to keep that property true.
struct RecipeTextRoundTripTests {

    static let tarteTatin = RecipeDraft(
        title: "Tarte Tatin",
        summaryFR: "Une tarte renversée aux pommes caramélisées, servie tiède.",
        servings: 6,
        prepMinutes: 30,
        cookMinutes: 45,
        difficulty: .moyen,
        course: .dessert,
        cuisine: "française",
        ingredients: [
            RecipeIngredient(quantity: 6, name: "pommes", note: "Reine des reinettes"),
            RecipeIngredient(quantity: 150, unit: .gram, name: "sucre"),
            RecipeIngredient(quantity: 100, unit: .gram, name: "beurre demi-sel"),
            RecipeIngredient(quantity: 1, name: "pâte feuilletée"),
            RecipeIngredient(quantity: 2, unit: .tablespoon, name: "huile d'olive"),
            RecipeIngredient(name: "Sel", note: "au goût"),
            RecipeIngredient(quantity: 0.5, unit: .liter, name: "eau"),
        ],
        steps: [
            RecipeStep(text: "Préchauffer le four à 180 °C."),
            RecipeStep(text: "Éplucher les pommes et les couper en quartiers."),
            RecipeStep(text: "Laisser reposer la pâte au frais.", minutes: 20),
            RecipeStep(text: "Enfourner jusqu'à ce que le caramel blondisse.", minutes: 45),
        ],
        chefTipFR: "Attendre que le caramel prenne une vraie couleur ambrée avant d'ajouter le beurre.",
        allergensFR: ["gluten", "lait"],
        photoQuery: "Tarte Tatin",
        tags: ["dessert", "classique", "de saison"]
    )

    @Test func recipeSurvivesBeingWrittenOutAndReadBack() {
        let original = Self.tarteTatin.normalized()
        let text = RecipeTextFormat.render(original)
        let parsed = RecipeTextFormat.parse(text).draft

        // `photoQuery` is a lookup hint rather than something the cook edits, so
        // it is deliberately not written into the text; the app carries the old
        // value forward instead.
        var expected = original
        expected.photoQuery = nil
        #expect(parsed == expected)
    }

    @Test func notesRoundTripAlongsideTheRecipe() {
        let notes = "J'ai essayé avec des poires, encore meilleur.\nMoule de 24 cm."
        let text = RecipeTextFormat.render(Self.tarteTatin, notes: notes)
        let parsed = RecipeTextFormat.parse(text)
        #expect(parsed.notes == notes)
    }

    @Test func absentNotesProduceNoSection() {
        let text = RecipeTextFormat.render(Self.tarteTatin)
        #expect(!text.contains("Mes notes"))
        #expect(RecipeTextFormat.parse(text).notes == nil)
    }

    @Test func renderedTextIsShapedTheWayACookExpects() {
        let text = RecipeTextFormat.render(Self.tarteTatin)
        #expect(text.hasPrefix("# Tarte Tatin"))
        #expect(text.contains("Pour 6 personnes · Préparation 30 min · Cuisson 45 min · Moyen · Dessert · Cuisine française"))
        #expect(text.contains("## Ingrédients"))
        #expect(text.contains("- 150 g de sucre"))
        #expect(text.contains("## Préparation"))
        #expect(text.contains("1. Préchauffer le four à 180 °C."))
        #expect(text.contains("3. Laisser reposer la pâte au frais. (20 min)"))

        // Ingredients come before steps: the list you shop from, then the order
        // you cook in.
        let ingredientsAt = text.range(of: "## Ingrédients")!.lowerBound
        let stepsAt = text.range(of: "## Préparation")!.lowerBound
        #expect(ingredientsAt < stepsAt)
    }

    @Test func editedTextIsAcceptedAsTheNewRecipe() {
        // Exactly what the free-text editor does: the cook rewrites the text,
        // deletes an ingredient, adds one of their own, and retitles the dish.
        let text = """
        # Tarte Tatin de Taddeo

        Pour 4 personnes · Préparation 25 min · Cuisson 50 min · Facile · Dessert

        ## Ingrédients
        - 8 pommes
        - 200 g de sucre
        - 3 gousses de vanille

        ## Préparation
        1. Préchauffer le four à 200 °C.
        2. Caraméliser le sucre à sec.

        ## Mes notes
        Le moule en fonte marche mieux.
        """
        let parsed = RecipeTextFormat.parse(text)
        #expect(parsed.draft.title == "Tarte Tatin de Taddeo")
        #expect(parsed.draft.servings == 4)
        #expect(parsed.draft.prepMinutes == 25)
        #expect(parsed.draft.cookMinutes == 50)
        #expect(parsed.draft.difficulty == .facile)
        #expect(parsed.draft.course == .dessert)
        #expect(parsed.draft.ingredients.count == 3)
        #expect(parsed.draft.ingredients[2].unit == .clove)
        #expect(parsed.draft.steps.count == 2)
        #expect(parsed.notes == "Le moule en fonte marche mieux.")
    }
}

struct RecipeIngredientParsingTests {

    private func parse(_ line: String) -> RecipeIngredient? {
        RecipeTextFormat.parseIngredient(line)
    }

    @Test func weightWithConnector() {
        let ingredient = parse("- 150 g de sucre")
        #expect(ingredient?.quantity == 150)
        #expect(ingredient?.unit == .gram)
        #expect(ingredient?.name == "sucre")
    }

    @Test func connectorIsOptional() {
        #expect(parse("150 g sucre")?.name == "sucre")
    }

    @Test func countableIngredientKeepsNoUnit() {
        let ingredient = parse("6 pommes")
        #expect(ingredient?.quantity == 6)
        #expect(ingredient?.unit == nil, "'6 pièces de pommes' is not how anyone writes it")
        #expect(ingredient?.name == "pommes")
    }

    @Test func elidedConnectorIsHandled() {
        let ingredient = parse("2 gousses d'ail")
        #expect(ingredient?.unit == .clove)
        #expect(ingredient?.name == "ail")
    }

    @Test func onlyTheFirstConnectorIsStripped() {
        let ingredient = parse("2 c. à soupe d'huile d'olive")
        #expect(ingredient?.unit == .tablespoon)
        #expect(ingredient?.name == "huile d'olive", "the olive oil keeps its own d'")
    }

    @Test func multiWordUnitWinsOverItsFirstWord() {
        #expect(parse("1 cuillère à café de sel")?.unit == .teaspoon)
        #expect(parse("1 cuillère à café de sel")?.name == "sel")
    }

    @Test func fractionsAndMixedNumbers() {
        #expect(parse("1/2 citron")?.quantity == 0.5)
        #expect(parse("1 1/2 c. à soupe de miel")?.quantity == 1.5)
        #expect(parse("0,5 l d'eau")?.quantity == 0.5)
    }

    @Test func trailingParenthesisIsANote() {
        let ingredient = parse("- 6 pommes (Reine des reinettes)")
        #expect(ingredient?.note == "Reine des reinettes")
        #expect(ingredient?.name == "pommes")
    }

    @Test func ingredientWithNoQuantityKeepsItsWholeName() {
        let ingredient = parse("Fleur de sel")
        #expect(ingredient?.quantity == nil)
        #expect(ingredient?.unit == nil)
        #expect(ingredient?.name == "Fleur de sel", "'de' is part of the name, not a connector")
    }

    @Test func americanUnitsPastedInAreConvertedOnTheSpot() {
        let ingredient = parse("- 2 cups of flour")
        #expect(ingredient?.unit == .milliliter)
        #expect(ingredient?.quantity == 475)
        #expect(ingredient?.name == "flour")
    }

    @Test func toTasteBecomesANoteRatherThanAQuantity() {
        let ingredient = RecipeIngredient(unit: .toTaste, name: "Sel").normalized()
        #expect(ingredient.unit == nil)
        #expect(ingredient.quantity == nil)
        #expect(ingredient.note == "au goût")
        #expect(ingredient.displayLine == "Sel (au goût)")
        #expect(parse(ingredient.displayLine) == ingredient)
    }

    @Test func emptyLinesAreDropped() {
        #expect(parse("") == nil)
        #expect(parse("-") == nil)
    }

    @Test func frenchElisionInDisplay() {
        #expect(RecipeIngredient(quantity: 2, unit: .clove, name: "ail").displayLine == "2 gousses d'ail")
        #expect(RecipeIngredient(quantity: 150, unit: .gram, name: "sucre").displayLine == "150 g de sucre")
        #expect(RecipeIngredient(quantity: 1, unit: .tablespoon, name: "huile").displayLine == "1 c. à soupe d'huile")
    }
}

struct RecipeStepParsingTests {

    @Test func numberedStepLosesItsNumber() {
        let step = RecipeTextFormat.parseStep("3. Éplucher les pommes.")
        #expect(step?.text == "Éplucher les pommes.")
    }

    @Test func trailingDurationIsCaptured() {
        let step = RecipeTextFormat.parseStep("4. Laisser reposer. (20 min)")
        #expect(step?.text == "Laisser reposer.")
        #expect(step?.minutes == 20)
    }

    @Test func aTrailingWeightIsNotADuration() {
        let step = RecipeTextFormat.parseStep("2. Ajouter le beurre (100 g)")
        #expect(step?.minutes == nil)
        #expect(step?.text == "Ajouter le beurre (100 g)",
                "the parenthesis belongs to the instruction and must survive")
    }

    @Test func fahrenheitInAPastedStepIsConvertedOnParse() {
        let step = RecipeTextFormat.parseStep("1. Preheat the oven to 350°F.")
        #expect(step?.text == "Preheat the oven to 175 °C.")
    }

    @Test func bulletStepsAreAccepted() {
        #expect(RecipeTextFormat.parseStep("- Mélanger.")?.text == "Mélanger.")
    }
}

struct RecipeTextResilienceTests {

    @Test func headingSynonymsAreUnderstood() {
        let text = """
        # Omelette

        ## Ingredients
        - 3 oeufs

        ## Etapes
        1. Battre les oeufs.

        ## Notes
        Beurre clarifié.
        """
        let parsed = RecipeTextFormat.parse(text)
        #expect(parsed.draft.ingredients.count == 1)
        #expect(parsed.draft.steps.count == 1)
        #expect(parsed.notes == "Beurre clarifié.")
    }

    @Test func aRecipeTypedWithNoHeadingsIsStillUnderstood() {
        // Someone pasting from a note app: a title, a list, then instructions.
        let text = """
        Salade de tomates
        Une entrée d'été.
        - 4 tomates
        - 1 c. à soupe d'huile d'olive
        1. Couper les tomates.
        2. Assaisonner.
        """
        let parsed = RecipeTextFormat.parse(text)
        #expect(parsed.draft.title == "Salade de tomates")
        #expect(parsed.draft.summaryFR == "Une entrée d'été.")
        #expect(parsed.draft.ingredients.count == 2)
        #expect(parsed.draft.steps.count == 2)
    }

    @Test func emptyTextDoesNotCrash() {
        let parsed = RecipeTextFormat.parse("")
        #expect(parsed.draft.title.isEmpty)
        #expect(parsed.draft.ingredients.isEmpty)
        #expect(parsed.notes == nil)
    }

    @Test func titleOnlyIsAValidStartingPoint() {
        let parsed = RecipeTextFormat.parse("# Idée à tester")
        #expect(parsed.draft.title == "Idée à tester")
        #expect(parsed.draft.steps.isEmpty)
    }

    @Test func blankLinesAndStrayWhitespaceAreIgnored() {
        let text = "# Test\n\n\n## Ingrédients\n\n   - 1 oeuf   \n\n"
        let parsed = RecipeTextFormat.parse(text)
        #expect(parsed.draft.ingredients.count == 1)
        #expect(parsed.draft.ingredients[0].name == "oeuf")
    }

    @Test func allergensAndTagsSplitOnCommas() {
        let text = """
        # Test

        ## Allergènes
        gluten, lait, œuf

        ## Mots-clés
        rapide, végétarien
        """
        let parsed = RecipeTextFormat.parse(text)
        #expect(parsed.draft.allergensFR == ["gluten", "lait", "œuf"])
        #expect(parsed.draft.tags == ["rapide", "végétarien"])
    }
}

struct RecipeScalingTests {

    @Test func scalingRewritesQuantitiesOnly() {
        let base = RecipeDraft(
            title: "Crêpes", servings: 4, prepMinutes: 10, cookMinutes: 20,
            ingredients: [
                RecipeIngredient(quantity: 250, unit: .gram, name: "farine"),
                RecipeIngredient(quantity: 4, name: "oeufs"),
                RecipeIngredient(name: "Sel", note: "au goût"),
            ],
            steps: [RecipeStep(text: "Mélanger.")]
        )
        let doubled = base.scaled(toServings: 8)
        #expect(doubled.servings == 8)
        #expect(doubled.ingredients[0].quantity == 500)
        #expect(doubled.ingredients[1].quantity == 8)
        #expect(doubled.ingredients[2].quantity == nil, "an ingredient with no amount stays without one")
        #expect(doubled.cookMinutes == 20, "doubling a batch does not double the cooking time")
    }

    @Test func scalingDownRoundsSensibly() {
        let base = RecipeDraft(
            title: "Gâteau", servings: 6,
            ingredients: [RecipeIngredient(quantity: 333, unit: .gram, name: "sucre")]
        )
        #expect(base.scaled(toServings: 2).ingredients[0].quantity == 110, "111 g rounds to the nearest 5")
    }

    @Test func scalingIsANoOpWithoutAServingCount() {
        let base = RecipeDraft(title: "X", ingredients: [RecipeIngredient(quantity: 10, unit: .gram, name: "y")])
        #expect(base.scaled(toServings: 8).ingredients[0].quantity == 10)
    }

    @Test func scaledRecipeStillRoundTripsThroughItsText() {
        let scaled = RecipeTextRoundTripTests.tarteTatin.normalized().scaled(toServings: 12)
        var expected = scaled
        expected.photoQuery = nil
        #expect(RecipeTextFormat.parse(RecipeTextFormat.render(scaled)).draft == expected)
    }
}

/// Scaling has to produce quantities a person can actually buy and measure.
struct RecipeScalingRoundingTests {

    private var base: RecipeDraft {
        RecipeDraft(
            title: "Tarte", servings: 6,
            ingredients: [
                RecipeIngredient(quantity: 8, name: "pommes"),
                RecipeIngredient(quantity: 1, name: "pâte feuilletée"),
                RecipeIngredient(quantity: 150, unit: .gram, name: "sucre"),
                RecipeIngredient(quantity: 2, unit: .clove, name: "vanille"),
                RecipeIngredient(quantity: 0.5, unit: .liter, name: "lait"),
            ]
        )
    }

    @Test func countedIngredientsBecomeWholeNumbers() {
        let scaled = base.scaled(toServings: 7)
        #expect(scaled.ingredients[0].quantity == 9, "9,3 pommes is not a shopping list entry")
        #expect(scaled.ingredients[1].quantity == 1, "1,2 pâte feuilletée is not a thing you can buy")
        #expect(scaled.ingredients[3].quantity == 2, "gousses are counted, not measured")
    }

    @Test func spoonsRoundToWhatASpoonCanActuallyHold() {
        let base = RecipeDraft(
            title: "Vinaigrette", servings: 6,
            ingredients: [
                RecipeIngredient(quantity: 1, unit: .tablespoon, name: "moutarde"),
                RecipeIngredient(quantity: 3, unit: .teaspoon, name: "vinaigre"),
            ]
        )
        let scaled = base.scaled(toServings: 7)
        #expect(scaled.ingredients[0].quantity == 1, "1,17 c. à soupe is not a measurement")
        #expect(scaled.ingredients[1].quantity == 3.5, "halves are the finest a spoon offers")
        #expect(base.scaled(toServings: 1).ingredients[0].quantity == 0.5, "never rounds away to nothing")
    }

    @Test func weightsAndVolumesKeepCookbookRounding() {
        let scaled = base.scaled(toServings: 7)
        #expect(scaled.ingredients[2].quantity == 175, "150 g scaled by 7/6")
        #expect(scaled.ingredients[4].quantity == 0.6, "0,5 l scaled and rounded to one decimal")
    }

    @Test func scalingDownNeverReachesZero() {
        let scaled = base.scaled(toServings: 1)
        #expect(scaled.ingredients[0].quantity == 1, "a sixth of 8 apples still means buying one")
        #expect(scaled.ingredients[1].quantity == 1)
    }

    @Test func aScaledRecipeStillRoundTrips() {
        let scaled = base.scaled(toServings: 12)
        #expect(RecipeTextFormat.parse(RecipeTextFormat.render(scaled)).draft == scaled.normalized())
    }
}
