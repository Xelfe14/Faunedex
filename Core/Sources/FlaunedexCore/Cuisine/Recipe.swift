import Foundation

/// How hard the recipe is. French raw values, because they are what the model
/// is asked to produce and what the UI displays.
public enum RecipeDifficulty: String, Codable, Sendable, CaseIterable, Hashable {
    case facile
    case moyen
    case difficile

    public var frenchLabel: String {
        switch self {
        case .facile: return "Facile"
        case .moyen: return "Moyen"
        case .difficile: return "Difficile"
        }
    }
}

/// Where the dish sits in a meal. Used for the default organisation of the
/// recipe bank, on top of whatever tags the cook adds themselves.
public enum RecipeCourse: String, Codable, Sendable, CaseIterable, Hashable {
    case apero = "apéritif"
    case entree = "entrée"
    case plat = "plat"
    case accompagnement
    case dessert
    case petitDejeuner = "petit-déjeuner"
    case boisson
    case sauce

    public var frenchLabel: String {
        switch self {
        case .apero: return "Apéritif"
        case .entree: return "Entrée"
        case .plat: return "Plat"
        case .accompagnement: return "Accompagnement"
        case .dessert: return "Dessert"
        case .petitDejeuner: return "Petit-déjeuner"
        case .boisson: return "Boisson"
        case .sauce: return "Sauce"
        }
    }

    public var symbolName: String {
        switch self {
        case .apero: return "wineglass"
        case .entree: return "carrot"
        case .plat: return "fork.knife"
        case .accompagnement: return "leaf"
        case .dessert: return "birthday.cake"
        case .petitDejeuner: return "cup.and.saucer"
        case .boisson: return "mug"
        case .sauce: return "drop"
        }
    }
}

/// One line of the ingredient list.
///
/// `id` is identity for SwiftUI lists only. Two ingredients holding the same
/// quantity, unit, name and note *are* the same ingredient, so equality and
/// hashing deliberately ignore the identifier. Without that, a recipe could
/// never be compared with the one parsed back out of its own text.
public struct RecipeIngredient: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var quantity: Double?
    public var unit: MetricUnit?
    public var name: String
    /// A qualifier the cook should see but that is not part of the measurement:
    /// "bio", "à température ambiante", "au goût".
    public var note: String?

    public init(id: UUID = UUID(), quantity: Double? = nil, unit: MetricUnit? = nil,
                name: String, note: String? = nil) {
        self.id = id
        self.quantity = quantity
        self.unit = unit
        self.name = name
        self.note = note
    }

    public static func == (lhs: RecipeIngredient, rhs: RecipeIngredient) -> Bool {
        lhs.quantity == rhs.quantity && lhs.unit == rhs.unit
            && lhs.name == rhs.name && lhs.note == rhs.note
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(quantity)
        hasher.combine(unit)
        hasher.combine(name)
        hasher.combine(note)
    }

    /// Fold the two units that read badly in French into plain prose, so what is
    /// stored is always what should be displayed.
    ///
    /// "6 pièces de pommes" is not how anyone writes a shopping list, and
    /// "sel au goût" is a note about the salt rather than an amount of it.
    /// Normalising here rather than at render time is what keeps the free-text
    /// round trip stable: text that is parsed and written again does not drift.
    public func normalized() -> RecipeIngredient {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = copy.note?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.note = n.isEmpty ? nil : n
        }
        if let q = copy.quantity, q <= 0 { copy.quantity = nil }
        switch copy.unit {
        case .piece:
            copy.unit = nil
        case .toTaste:
            copy.unit = nil
            copy.quantity = nil
            if copy.note == nil { copy.note = "au goût" }
        default:
            break
        }
        return copy
    }

    /// "150 g de sucre", "6 pommes", "2 gousses d'ail (dégermées)".
    public var displayLine: String {
        var head: String
        switch (quantity, unit) {
        case let (q?, u?):
            head = "\(Formatting.number(q)) \(u.label(quantity: q)) \(Self.frenchDe(before: name))"
        case let (q?, nil):
            head = "\(Formatting.number(q)) \(name)"
        case let (nil, u?):
            head = "\(u.rawValue) \(Self.frenchDe(before: name))"
        case (nil, nil):
            head = name
        }
        if let note, !note.isEmpty { head += " (\(note))" }
        return head
    }

    /// French elision: "de sucre" but "d'ail", "d'huile d'olive".
    static func frenchDe(before name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                 locale: Locale(identifier: "fr_FR"))
        guard let first = folded.first else { return "de \(name)" }
        return "aeiouyh".contains(first) ? "d'\(name)" : "de \(name)"
    }
}

/// One numbered instruction.
public struct RecipeStep: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    /// Minutes this step takes, when the step is mostly waiting (proving,
    /// simmering, resting). Nil for an action that takes as long as it takes.
    public var minutes: Int?

    public init(id: UUID = UUID(), text: String, minutes: Int? = nil) {
        self.id = id
        self.text = text
        self.minutes = minutes
    }

    public static func == (lhs: RecipeStep, rhs: RecipeStep) -> Bool {
        lhs.text == rhs.text && lhs.minutes == rhs.minutes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(minutes)
    }

    public func normalized() -> RecipeStep {
        var copy = self
        copy.text = MetricConversion.normalizeTemperatures(
            in: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let m = copy.minutes, m <= 0 { copy.minutes = nil }
        return copy
    }
}

/// A complete recipe as a value: what Gemini returns, what the free-text editor
/// parses, and what the app stores. Deliberately framework-free so the whole
/// thing is testable with `swift test` and no Xcode, exactly like the
/// identification side of the app.
public struct RecipeDraft: Codable, Sendable, Equatable {
    public var title: String
    public var summaryFR: String?
    public var servings: Int?
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var difficulty: RecipeDifficulty?
    public var course: RecipeCourse?
    /// Culinary tradition, free text: "française", "italienne", "thaïlandaise".
    public var cuisine: String?
    public var ingredients: [RecipeIngredient]
    public var steps: [RecipeStep]
    /// One short piece of advice from the "chef", the thing that makes the dish
    /// work. The cooking equivalent of the species card's fun fact.
    public var chefTipFR: String?
    public var allergensFR: [String]
    /// What to search for when looking up a photograph of the finished dish.
    public var photoQuery: String?
    public var tags: [String]

    public init(
        title: String,
        summaryFR: String? = nil,
        servings: Int? = nil,
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        difficulty: RecipeDifficulty? = nil,
        course: RecipeCourse? = nil,
        cuisine: String? = nil,
        ingredients: [RecipeIngredient] = [],
        steps: [RecipeStep] = [],
        chefTipFR: String? = nil,
        allergensFR: [String] = [],
        photoQuery: String? = nil,
        tags: [String] = []
    ) {
        self.title = title
        self.summaryFR = summaryFR
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.difficulty = difficulty
        self.course = course
        self.cuisine = cuisine
        self.ingredients = ingredients
        self.steps = steps
        self.chefTipFR = chefTipFR
        self.allergensFR = allergensFR
        self.photoQuery = photoQuery
        self.tags = tags
    }

    public var totalMinutes: Int? {
        let sum = (prepMinutes ?? 0) + (cookMinutes ?? 0)
        return sum > 0 ? sum : nil
    }

    /// Run every element through its own normalisation and drop empties. This
    /// is the single gate every recipe passes through, whether it arrived from
    /// the model or from the cook's own typing.
    public func normalized() -> RecipeDraft {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.summaryFR = Self.cleaned(summaryFR)
        copy.chefTipFR = Self.cleaned(chefTipFR)
        copy.cuisine = Self.cleaned(cuisine)?.lowercased()
        copy.photoQuery = Self.cleaned(photoQuery)
        if let s = copy.servings, s <= 0 { copy.servings = nil }
        if let m = copy.prepMinutes, m <= 0 { copy.prepMinutes = nil }
        if let m = copy.cookMinutes, m <= 0 { copy.cookMinutes = nil }
        copy.ingredients = ingredients
            .map { $0.normalized() }
            .filter { !$0.name.isEmpty }
        copy.steps = steps
            .map { $0.normalized() }
            .filter { !$0.text.isEmpty }
        copy.allergensFR = Self.uniqueTrimmed(allergensFR)
        copy.tags = Self.uniqueTrimmed(tags)
        return copy
    }

    private static func cleaned(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Trim, drop empties, and de-duplicate case-insensitively while keeping the
    /// order and the original casing of the first occurrence.
    ///
    /// Public because the tag editor needs exactly this rule: a cook typing
    /// "Rapide" when "rapide" already exists should not end up with two tags
    /// that filter differently.
    public static func uniqueTrimmed(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                      locale: Locale(identifier: "fr_FR"))
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(trimmed)
        }
        return out
    }

    /// Rewrite every quantity for a different number of eaters.
    ///
    /// Only the numbers move. Times are left alone on purpose: doubling a cake
    /// does not double its baking time, and quietly saying otherwise would be
    /// worse than saying nothing.
    ///
    /// Things that are counted rather than measured are rounded to whole units.
    /// Scaling six apples up by a seventh is arithmetically 9.33 apples, and
    /// putting "9,3 pommes" on a shopping list is not a quantity anyone can act
    /// on. Weights and volumes keep their cookbook rounding, where a fractional
    /// value is perfectly usable.
    public func scaled(toServings target: Int) -> RecipeDraft {
        guard let current = servings, current > 0, target > 0, target != current else { return self }
        let factor = Double(target) / Double(current)
        var copy = self
        copy.servings = target
        copy.ingredients = ingredients.map { ingredient in
            var scaled = ingredient
            guard let quantity = ingredient.quantity else { return scaled }
            let target = quantity * factor
            if ingredient.unit == nil || ingredient.unit?.dimension == .count {
                // Counted things come in whole units. Nobody buys 9.3 apples.
                scaled.quantity = max(1, target.rounded())
            } else if ingredient.unit == .tablespoon || ingredient.unit == .teaspoon {
                // A spoon is a physical object: you can level it or half it,
                // and that is the end of the resolution it offers.
                scaled.quantity = max(0.5, (target * 2).rounded() / 2)
            } else {
                scaled.quantity = MetricConversion.cookingRounded(target)
            }
            return scaled
        }
        return copy
    }
}
