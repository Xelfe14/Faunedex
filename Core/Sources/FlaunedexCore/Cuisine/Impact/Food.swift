import Foundation

/// One ingredient the footprint calculator knows: what a recipe calls it, its
/// carbon footprint per kilo, and what it weighs when a recipe counts it
/// instead of weighing it.
///
/// Fresh fruit and vegetables take their footprint from Impact CO2, everything
/// else from Agribalyse 3.2 (both ADEME), so a tomato carries the same figure in
/// the seasonal calendar and in a recipe.
public struct Food: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// How recipes write it, singular and lower case, without accents.
    public let aliases: [String]
    public let kgCO2ePerKg: Double
    /// The dataset entry the footprint was read from, for the card's credits.
    public let source: String
    /// Its row in the seasonal calendar, for fresh produce.
    public let produceID: String?
    /// Grams in one counted unit: "2 courgettes", "3 œufs".
    public let gramsPerPiece: Double?
    /// Density, for volumes and spoons: a spoon of flour weighs less than a
    /// spoon of honey.
    public let gramsPerMilliliter: Double
    /// Grams per clove, sprig, bunch, slice, leaf or packet, where this food
    /// differs from the general rule.
    public let unitGrams: [MetricUnit: Double]

    public init(id: String, name: String, aliases: [String], kgCO2ePerKg: Double, source: String,
                produceID: String?, gramsPerPiece: Double?, gramsPerMilliliter: Double,
                unitGrams: [MetricUnit: Double]) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.kgCO2ePerKg = kgCO2ePerKg
        self.source = source
        self.produceID = produceID
        self.gramsPerPiece = gramsPerPiece
        self.gramsPerMilliliter = gramsPerMilliliter
        self.unitGrams = unitGrams
    }

    public static func == (lhs: Food, rhs: Food) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var produce: Produce? { produceID.flatMap(ProduceCatalog.produce(id:)) }

    /// Grams of this food in one ingredient line, or nil when the amount can't
    /// be known: "au goût", or a count of something with no typical weight.
    public func grams(quantity: Double?, unit: MetricUnit?) -> Double? {
        guard let quantity, quantity > 0 else { return nil }
        switch unit {
        case .gram?: return quantity
        case .kilogram?: return quantity * 1000
        case .milliliter?: return quantity * gramsPerMilliliter
        case .centiliter?: return quantity * 10 * gramsPerMilliliter
        case .liter?: return quantity * 1000 * gramsPerMilliliter
        case .tablespoon?: return quantity * 15 * gramsPerMilliliter
        case .teaspoon?: return quantity * 5 * gramsPerMilliliter
        case .pinch?: return quantity * 0.5
        case .toTaste?: return nil
        case nil, .piece?: return gramsPerPiece.map { quantity * $0 }
        case let other?:
            return (unitGrams[other] ?? Self.typicalUnitGrams[other]).map { quantity * $0 }
        }
    }

    /// What a clove, sprig, bunch, slice, leaf or packet usually weighs.
    static let typicalUnitGrams: [MetricUnit: Double] = [
        .clove: 5, .sprig: 1, .bunch: 50, .slice: 30, .leaf: 1, .packet: 10,
    ]
}

/// Every food the calculator knows, and the matching from an ingredient line
/// to one of them.
public enum FoodCatalog {
    public static let all: [Food] = produceFoods + pantryFoods

    private static let index: [(words: [String], food: Food)] = all.flatMap { food in
        food.aliases.map { (words: words(of: $0), food: food) }
    }

    /// The food an ingredient name refers to, or nil when it isn't known.
    ///
    /// Every alias is looked for as a run of whole words, and the longest one
    /// found wins, so "pommes de terre" is a potato and never an apple,
    /// "lait de coco" is not milk, and "huile d'olive" is not an olive. Ties go
    /// to the alias that comes first in the name: in "sauce soja et miel" the
    /// sauce is what the line is about.
    public static func match(_ ingredientName: String) -> Food? {
        let name = words(of: ingredientName)
        guard !name.isEmpty else { return nil }
        var best: (food: Food, length: Int, start: Int, letters: Int)?
        for entry in index {
            let length = entry.words.count
            guard length > 0, length <= name.count else { continue }
            guard let start = (0...(name.count - length)).first(where: {
                Array(name[$0..<($0 + length)]) == entry.words
            }) else { continue }
            let letters = entry.words.reduce(0) { $0 + $1.count }
            if let current = best {
                let isBetter = length != current.length ? length > current.length
                    : start != current.start ? start < current.start
                    : letters > current.letters
                guard isBetter else { continue }
            }
            best = (entry.food, length, start, letters)
        }
        return best?.food
    }

    /// Lower case, no accents, "œ" spelled out, punctuation as spaces, and each
    /// word made singular the cheap way, by dropping a final "s" or "x". The
    /// same treatment applies to aliases and to recipe text, so it only has to
    /// be consistent, not grammatical: "noix" and "noix" both become "noi".
    static func words(of text: String) -> [String] {
        let spelled = text.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        var words: [String] = []
        var current = ""
        for scalar in spelled.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(singular(current))
                current = ""
            }
        }
        if !current.isEmpty { words.append(singular(current)) }
        return words
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3, let last = word.last, last == "s" || last == "x" else { return word }
        return String(word.dropLast())
    }
}
