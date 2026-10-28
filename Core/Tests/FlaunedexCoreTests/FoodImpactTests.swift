import Testing
import Foundation
@testable import FlaunedexCore

/// From an ingredient line to kilograms of CO2e: which food it is, what it
/// weighs, and what the recipe adds up to.
struct FoodImpactTests {

    private func id(_ name: String) -> String? { FoodCatalog.match(name)?.id }

    // MARK: Matching

    @Test func longestNameWins() {
        #expect(id("pommes de terre") == "pomme-de-terre")
        #expect(id("pommes") == "produce:pomme")
        #expect(id("lait de coco") == "lait-coco")
        #expect(id("lait demi-écrémé") == "lait")
        #expect(id("huile d'olive vierge extra") == "huile-olive")
        #expect(id("jus de citron vert") == "citron-vert")
        #expect(id("jus de citron") == "produce:citron")
        #expect(id("chou-fleur") == "produce:choufleur")
        #expect(id("crème de marrons") == "creme-marrons")
    }

    @Test func cabbagesAndSquashesFindTheirOwnRow() {
        #expect(id("chou rouge") == "produce:chourouge")
        #expect(id("chou kale") == "produce:choukale")
        #expect(id("kale") == "produce:choukale")
        #expect(id("chou frisé") == "produce:chou", "in a recipe, a chou frisé is usually a savoy cabbage")
        #expect(id("chou") == "produce:chou")
        #expect(id("potimarron") == "produce:potimarron")
        #expect(id("courge butternut") == "produce:butternut")
        #expect(id("courge") == "produce:courge")
        #expect(id("figues de Barbarie") == "produce:figuedebarbarie")
        #expect(id("figues") == "produce:figue")
        #expect(id("amandes fraîches") == "produce:amandefraiche")
        #expect(id("poudre d'amande") == "amande")
    }

    @Test func readsRecipeSpelling() {
        #expect(id("Œufs") == "oeuf")
        #expect(id("jaunes d'œufs") == "jaune-oeuf")
        #expect(id("bœuf haché") == "boeuf-hache")
        #expect(id("épinards frais") == "produce:epinard")
        #expect(id("poireaux") == "produce:poireau")
        #expect(id("crème fraîche épaisse") == "creme-epaisse")
    }

    @Test func processedProduceIsNotFreshProduce() {
        #expect(id("tomates pelées") == "tomate-conserve")
        #expect(id("concentré de tomate") == "concentre-tomate")
        #expect(id("tomates") == "produce:tomate")
        #expect(FoodCatalog.match("tomates pelées")?.produce == nil, "a tin has no season")
        #expect(FoodCatalog.match("tomates")?.produce?.id == "tomate")
    }

    @Test func unknownFoodsStayUnknown() {
        #expect(FoodCatalog.match("champignons de Paris") == nil, "no ADEME figure, so no guess")
        #expect(FoodCatalog.match("câpres") == nil)
        #expect(FoodCatalog.match("") == nil)
    }

    @Test func everyAliasFindsItsOwnFood() {
        for food in FoodCatalog.all {
            for alias in food.aliases {
                let found = FoodCatalog.match(alias)
                #expect(found != nil, "\(alias) finds nothing")
            }
        }
    }

    // MARK: Weights

    @Test func weighsEachKindOfUnit() throws {
        let egg = try #require(FoodCatalog.match("œufs"))
        #expect(egg.grams(quantity: 2, unit: nil) == 110)
        let garlic = try #require(FoodCatalog.match("ail"))
        #expect(garlic.grams(quantity: 3, unit: .clove) == 15)
        let oil = try #require(FoodCatalog.match("huile d'olive"))
        #expect(abs((oil.grams(quantity: 2, unit: .tablespoon) ?? 0) - 27.6) < 0.001)
        let cream = try #require(FoodCatalog.match("crème liquide"))
        #expect(cream.grams(quantity: 20, unit: .centiliter) == 200)
        let salt = try #require(FoodCatalog.match("sel"))
        #expect(salt.grams(quantity: 1, unit: .pinch) == 0.5)
        #expect(salt.grams(quantity: nil, unit: .toTaste) == nil)
        let flour = try #require(FoodCatalog.match("farine"))
        #expect(flour.grams(quantity: 1, unit: .kilogram) == 1000)
    }

    // MARK: Footprint

    private var bolognese: [RecipeIngredient] {
        [
            RecipeIngredient(quantity: 400, unit: .gram, name: "bœuf haché"),
            RecipeIngredient(quantity: 2, unit: nil, name: "oignons"),
            RecipeIngredient(quantity: 200, unit: .gram, name: "champignons de Paris"),
            RecipeIngredient(quantity: nil, unit: nil, name: "sel", note: "au goût"),
            RecipeIngredient(quantity: 3, unit: nil, name: "poignées d'épinards"),
        ]
    }

    @Test func addsUpWhatItCanWeigh() throws {
        let footprint = RecipeFootprint(ingredients: bolognese)
        let beef = try #require(FoodCatalog.match("bœuf haché"))
        let onion = try #require(FoodCatalog.match("oignon"))
        let expected = 0.4 * beef.kgCO2ePerKg + 0.2 * onion.kgCO2ePerKg
        #expect(abs(footprint.totalKgCO2e - expected) < 1e-9)
        #expect(footprint.contributors.first?.food?.id == "boeuf-hache")
        #expect(footprint.perServing(4) == footprint.totalKgCO2e / 4)
        #expect(footprint.hasData)
    }

    @Test func saysWhatItLeftOut() {
        let footprint = RecipeFootprint(ingredients: bolognese)
        let statuses = footprint.lines.map(\.status)
        #expect(statuses == [.counted, .counted, .unknownFood, .negligible, .unknownAmount])
        #expect(footprint.notEvaluated.map(\.ingredient.name) == ["champignons de Paris", "poignées d'épinards"])
    }

    @Test func emptyRecipeHasNoData() {
        let footprint = RecipeFootprint(ingredients: [])
        #expect(footprint.totalKgCO2e == 0)
        #expect(!footprint.hasData)
    }

    // MARK: Words

    @Test func formatsFiguresTheFrenchWay() {
        #expect(CarbonComparison.format(2.43) == "2,4 kg CO₂e")
        #expect(CarbonComparison.format(0.348) == "350 g CO₂e")
        #expect(CarbonComparison.formatPerKilo(0.396) == "0,4 kg CO₂e/kg")
        #expect(CarbonComparison.formatPerKilo(35.7) == "36 kg CO₂e/kg")
    }

    @Test func comparesWithAdemesReferenceMeals() {
        #expect(CarbonComparison.mealComparison(perServing: 0.3) == "moins qu'un repas végétalien")
        #expect(CarbonComparison.mealComparison(perServing: 0.9) == "proche d'un repas végétarien")
        #expect(CarbonComparison.mealComparison(perServing: 4.5) == "proche d'un repas avec du bœuf")
        #expect(CarbonComparison.mealComparison(perServing: 6) == "plus qu'un repas avec du bœuf")
        #expect(abs(CarbonComparison.carKilometers(1.423) - 10) < 1e-9)
    }

    @Test func gradesFootprints() {
        #expect(ImpactLevel.perKilo(0.4) == .low)
        #expect(ImpactLevel.perKilo(1.9) == .medium)
        #expect(ImpactLevel.perKilo(35.7) == .high)
        #expect(ImpactLevel.perServing(0.6) == .low)
        #expect(ImpactLevel.perServing(3.6) == .high)
    }

    @Test func lowerImpactRequestNamesTheHeaviestIngredients() {
        let footprint = RecipeFootprint(ingredients: bolognese)
        let change = RecipeSchema.lowerImpactChange(footprint: footprint, servings: 4)
        #expect(change.contains("400 g de bœuf haché"))
        #expect(change.contains("4 personnes"))
        #expect(change.contains("légumineuses"))
        #expect(!change.hasSuffix("."), "the revision template adds its own full stop")
    }
}
