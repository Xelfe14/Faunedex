import Foundation

/// The carbon footprint of a recipe, ingredient by ingredient.
///
/// Recipes here are metric by construction, so most lines convert straight to
/// kilograms; counted things use a typical piece weight. What can't be
/// evaluated (a food the datasets don't have, a count with no typical weight)
/// is listed rather than guessed, and "au goût" amounts count as negligible.
public struct RecipeFootprint: Sendable, Equatable {

    public enum Status: Sendable, Equatable {
        /// Weighed and multiplied by the food's footprint.
        case counted
        /// "Sel au goût": a known food in an amount too small to state.
        case negligible
        /// The datasets have nothing for it.
        case unknownFood
        /// A known food counted in units with no typical weight.
        case unknownAmount
    }

    public struct Line: Sendable, Equatable, Identifiable {
        public var id: UUID { ingredient.id }
        public let ingredient: RecipeIngredient
        public let food: Food?
        public let grams: Double?
        public let kgCO2e: Double
        public let status: Status
    }

    public let lines: [Line]

    public init(ingredients: [RecipeIngredient]) {
        lines = ingredients.map { ingredient in
            guard let food = FoodCatalog.match(ingredient.name) else {
                return Line(ingredient: ingredient, food: nil, grams: nil, kgCO2e: 0, status: .unknownFood)
            }
            guard let grams = food.grams(quantity: ingredient.quantity, unit: ingredient.unit) else {
                let isAmountless = ingredient.quantity == nil || ingredient.unit == .toTaste
                return Line(ingredient: ingredient, food: food, grams: nil, kgCO2e: 0,
                            status: isAmountless ? .negligible : .unknownAmount)
            }
            return Line(ingredient: ingredient, food: food, grams: grams,
                        kgCO2e: grams / 1000 * food.kgCO2ePerKg, status: .counted)
        }
    }

    public var totalKgCO2e: Double { lines.reduce(0) { $0 + $1.kgCO2e } }

    public func perServing(_ servings: Int) -> Double {
        servings > 0 ? totalKgCO2e / Double(servings) : totalKgCO2e
    }

    /// The counted lines, heaviest footprint first.
    public var contributors: [Line] {
        lines.filter { $0.status == .counted && $0.kgCO2e > 0 }.sorted { $0.kgCO2e > $1.kgCO2e }
    }

    /// The lines left out of the total because they couldn't be evaluated.
    public var notEvaluated: [Line] {
        lines.filter { $0.status == .unknownFood || $0.status == .unknownAmount }
    }

    /// Whether anything at all was counted.
    public var hasData: Bool { lines.contains { $0.status == .counted } }
}

/// Ways to make a carbon figure mean something.
public enum CarbonComparison {

    /// An average petrol car, kg CO2e per km (Impact CO2, ADEME).
    public static let petrolCarKgPerKm = 0.1423

    public static func carKilometers(_ kgCO2e: Double) -> Double { kgCO2e / petrolCarKgPerKm }

    /// ADEME's reference meals, kg CO2e per meal (Impact CO2), lightest first.
    public static let referenceMeals: [(name: String, kgCO2e: Double)] = [
        ("un repas végétalien", 0.54),
        ("un repas végétarien", 0.85),
        ("un repas avec du poulet", 1.46),
        ("un repas avec du bœuf", 4.97),
    ]

    /// How a portion compares with ADEME's reference meals: "moins qu'un repas
    /// végétarien", "entre un repas avec du poulet et un repas avec du bœuf".
    public static func mealComparison(perServing kg: Double) -> String {
        let meals = referenceMeals
        guard let first = meals.first, let last = meals.last else { return "" }
        if kg <= first.kgCO2e { return "moins qu'\(first.name)" }
        if kg > last.kgCO2e { return "plus qu'\(last.name)" }
        for (lower, upper) in zip(meals, meals.dropFirst()) where kg <= upper.kgCO2e {
            let nearest = (kg - lower.kgCO2e) < (upper.kgCO2e - kg) ? lower : upper
            return "proche d'\(nearest.name)"
        }
        return ""
    }

    /// "2,4 kg CO₂e" or, under a kilo, "350 g CO₂e".
    public static func format(_ kgCO2e: Double) -> String {
        if kgCO2e < 1 {
            let grams = max(0, (kgCO2e * 1000 / 10).rounded() * 10)
            return "\(Formatting.number(grams)) g CO₂e"
        }
        return "\(Formatting.number((kgCO2e * 10).rounded() / 10)) kg CO₂e"
    }

    /// A per-kilo footprint: "0,4 kg CO₂e/kg".
    public static func formatPerKilo(_ kgCO2ePerKg: Double) -> String {
        let rounded = kgCO2ePerKg < 10 ? (kgCO2ePerKg * 10).rounded() / 10 : kgCO2ePerKg.rounded()
        return "\(Formatting.number(rounded)) kg CO₂e/kg"
    }
}

/// How heavy a footprint is, for colour.
public enum ImpactLevel: Sendable, Equatable {
    case low, medium, high

    /// For a kilo of food: most fruit and vegetables sit below 1, meat and
    /// cheese far above.
    public static func perKilo(_ kgCO2ePerKg: Double) -> ImpactLevel {
        kgCO2ePerKg < 1 ? .low : kgCO2ePerKg < 3 ? .medium : .high
    }

    /// For one portion, against ADEME's reference meals: up to a vegetarian
    /// meal is low, up to a chicken meal medium, beyond that high.
    public static func perServing(_ kgCO2e: Double) -> ImpactLevel {
        kgCO2e <= 0.85 ? .low : kgCO2e <= 1.46 ? .medium : .high
    }
}
