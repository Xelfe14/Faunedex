import Foundation

/// The closed vocabulary of units a Flaunedex recipe may use.
///
/// This exists because the whole point of the cooking section is that
/// quantities are usable in a European kitchen: weights in grams, volumes in
/// millilitres, oven temperatures in degrees Celsius. A language model asked
/// for a recipe will otherwise drift into cups and ounces the moment the dish
/// it recalls came from an American source. The enum is fed to Gemini as the
/// `enum` of the `unit` field in the response schema, so a non-metric unit is
/// not merely discouraged, it is unrepresentable in a valid response.
///
/// `MetricConversion` then handles the leftover case: text the user pastes or
/// types themselves, which no schema can constrain.
public enum MetricUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case gram = "g"
    case kilogram = "kg"
    case milliliter = "ml"
    case centiliter = "cl"
    case liter = "l"
    case tablespoon = "c. à soupe"
    case teaspoon = "c. à café"
    case pinch = "pincée"
    case piece = "pièce"
    case clove = "gousse"
    case sprig = "brin"
    case bunch = "botte"
    case slice = "tranche"
    case leaf = "feuille"
    case packet = "sachet"
    case toTaste = "au goût"

    /// Units written as an abbreviation, which never take a plural.
    private var isAbbreviation: Bool {
        switch self {
        case .gram, .kilogram, .milliliter, .centiliter, .liter,
             .tablespoon, .teaspoon, .toTaste:
            return true
        default:
            return false
        }
    }

    /// The unit as it should be written next to `quantity`.
    /// "2 pièces" but "2 g", and "2 c. à soupe" rather than "2 c. à soupes".
    public func label(quantity: Double?) -> String {
        guard !isAbbreviation, let quantity, quantity > 1 else { return rawValue }
        return rawValue + "s"
    }

    /// Whether this unit measures a mass, a volume, or a count. Used to keep a
    /// conversion honest: grams never become millilitres, because that would
    /// need the ingredient's density and would silently invent a number.
    public enum Dimension: Sendable { case mass, volume, count }

    public var dimension: Dimension {
        switch self {
        case .gram, .kilogram: return .mass
        case .milliliter, .centiliter, .liter, .tablespoon, .teaspoon: return .volume
        default: return .count
        }
    }
}

/// Converts non-metric quantities into the vocabulary above, and rewrites
/// Fahrenheit oven temperatures found in free text.
///
/// Everything here is a pure function over values, so each conversion factor is
/// pinned by a test rather than trusted.
public enum MetricConversion {

    /// A quantity expressed in an allowed unit.
    public struct Converted: Sendable, Equatable {
        public let quantity: Double
        public let unit: MetricUnit
        public init(quantity: Double, unit: MetricUnit) {
            self.quantity = quantity
            self.unit = unit
        }
    }

    // MARK: Unit vocabulary

    /// Written forms that already mean an allowed unit, including the French
    /// spellings a user would type by hand.
    private static let aliases: [String: MetricUnit] = [
        "g": .gram, "gr": .gram, "gramme": .gram, "grammes": .gram,
        "gram": .gram, "grams": .gram,
        "kg": .kilogram, "kilo": .kilogram, "kilos": .kilogram,
        "kilogramme": .kilogram, "kilogrammes": .kilogram, "kilogram": .kilogram, "kilograms": .kilogram,
        "ml": .milliliter, "millilitre": .milliliter, "millilitres": .milliliter,
        "milliliter": .milliliter, "milliliters": .milliliter,
        "cl": .centiliter, "centilitre": .centiliter, "centilitres": .centiliter,
        "l": .liter, "litre": .liter, "litres": .liter, "liter": .liter, "liters": .liter,
        "c. a soupe": .tablespoon, "c a soupe": .tablespoon, "cuillere a soupe": .tablespoon,
        "cuilleres a soupe": .tablespoon, "c.a.s": .tablespoon, "cas": .tablespoon,
        "cs": .tablespoon, "tbsp": .tablespoon, "tablespoon": .tablespoon, "tablespoons": .tablespoon,
        "c. a cafe": .teaspoon, "c a cafe": .teaspoon, "cuillere a cafe": .teaspoon,
        "cuilleres a cafe": .teaspoon, "c.a.c": .teaspoon, "cac": .teaspoon,
        "cc": .teaspoon, "tsp": .teaspoon, "teaspoon": .teaspoon, "teaspoons": .teaspoon,
        "pincee": .pinch, "pincees": .pinch, "pinch": .pinch, "pinches": .pinch,
        "piece": .piece, "pieces": .piece, "unite": .piece, "unites": .piece,
        "gousse": .clove, "gousses": .clove, "clove": .clove, "cloves": .clove,
        "brin": .sprig, "brins": .sprig, "sprig": .sprig, "sprigs": .sprig,
        "botte": .bunch, "bottes": .bunch, "bunch": .bunch, "bunches": .bunch,
        "tranche": .slice, "tranches": .slice, "slice": .slice, "slices": .slice,
        "feuille": .leaf, "feuilles": .leaf, "leaf": .leaf, "leaves": .leaf,
        "sachet": .packet, "sachets": .packet, "packet": .packet, "packets": .packet,
        "au gout": .toTaste, "to taste": .toTaste,
    ]

    /// Imperial and US-customary units, with the factor that turns one of them
    /// into `unit`. Volumes use the US customary values, since that is what an
    /// American recipe means when it says "cup".
    private static let imperial: [String: (factor: Double, unit: MetricUnit)] = [
        "oz": (28.349523125, .gram), "ounce": (28.349523125, .gram), "ounces": (28.349523125, .gram),
        "once": (28.349523125, .gram), "onces": (28.349523125, .gram),
        "lb": (453.59237, .gram), "lbs": (453.59237, .gram),
        "pound": (453.59237, .gram), "pounds": (453.59237, .gram),
        "livre": (453.59237, .gram), "livres": (453.59237, .gram),
        "stick": (113.0, .gram), "sticks": (113.0, .gram),
        "fl oz": (29.5735295625, .milliliter), "floz": (29.5735295625, .milliliter),
        "fluid ounce": (29.5735295625, .milliliter), "fluid ounces": (29.5735295625, .milliliter),
        "cup": (236.5882365, .milliliter), "cups": (236.5882365, .milliliter),
        "tasse": (236.5882365, .milliliter), "tasses": (236.5882365, .milliliter),
        "pint": (473.176473, .milliliter), "pints": (473.176473, .milliliter),
        "quart": (946.352946, .milliliter), "quarts": (946.352946, .milliliter),
        "gallon": (3.785411784, .liter), "gallons": (3.785411784, .liter),
    ]

    /// Lower-cased, accent-stripped, whitespace-collapsed form used for lookup,
    /// so "Cuillère à soupe" and "cuillere a soupe" are the same key.
    static func normalizedKey(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let collapsed = folded
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " .").union(.whitespacesAndNewlines))
            .replacingOccurrences(of: "..", with: ".")
    }

    /// Resolve a written unit to the allowed vocabulary, without converting.
    /// Returns nil for anything unrecognised, which callers keep as free text
    /// rather than guessing at.
    public static func unit(for raw: String?) -> MetricUnit? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let key = normalizedKey(raw)
        if let direct = aliases[key] { return direct }
        // "c.a.s" style keys keep their dots; try again without them.
        let dotless = key.replacingOccurrences(of: ".", with: "")
        return aliases[dotless]
    }

    /// Convert a quantity written in any recognised unit into the metric
    /// vocabulary. Recognised-but-already-metric input is returned unchanged,
    /// so this is safe to run over everything.
    ///
    /// Returns nil when the unit is not recognised at all: inventing a number
    /// for "1 handful" would be worse than leaving the words alone.
    public static func toMetric(quantity: Double, unit rawUnit: String?) -> Converted? {
        if let known = unit(for: rawUnit) {
            return Converted(quantity: cookingRounded(quantity), unit: known)
        }
        guard let rawUnit else { return nil }
        let key = normalizedKey(rawUnit)
        guard let entry = imperial[key] ?? imperial[key.replacingOccurrences(of: ".", with: "")] else {
            return nil
        }
        return Converted(quantity: cookingRounded(quantity * entry.factor), unit: entry.unit)
    }

    // MARK: Rounding

    /// Round the way a cookbook does. Nobody weighs 453.59 g of flour, and
    /// nobody measures 0.4523 l either, so precision is dropped in proportion
    /// to the size of the number.
    public static func cookingRounded(_ value: Double) -> Double {
        let magnitude = abs(value)
        if magnitude >= 100 { return (value / 5).rounded() * 5 }
        if magnitude >= 10 { return value.rounded() }
        return (value * 10).rounded() / 10
    }

    // MARK: Temperature

    /// Fahrenheit to Celsius, rounded to the nearest 5 because that is the
    /// granularity an oven dial actually offers.
    public static func celsius(fromFahrenheit f: Double) -> Double {
        let c = (f - 32) * 5 / 9
        return (c / 5).rounded() * 5
    }

    /// Rewrite Fahrenheit oven temperatures inside a free-text instruction.
    ///
    /// A step such as "Preheat the oven to 350°F" survives the response schema
    /// untouched, because the schema constrains ingredient units and not prose.
    /// This catches it on the way in and on every later edit.
    public static func normalizeTemperatures(in text: String) -> String {
        let pattern = "([0-9]{2,3})\\s*(?:°\\s*F\\b|℉|degres?\\s*F\\b|degrees?\\s*F\\b|deg\\s*F\\b|\\sF\\b)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let ns = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        // Replace from the end so earlier ranges stay valid.
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let value = Double(ns.substring(with: match.range(at: 1))) else { continue }
            let celsius = self.celsius(fromFahrenheit: value)
            let replacement = "\(Formatting.number(celsius)) °C"
            let full = match.range(at: 0)
            result = (result as NSString).replacingCharacters(in: full, with: replacement)
        }
        return result
    }
}

/// Number formatting shared by the recipe text format and the UI, kept in one
/// place so what is written and what is parsed back cannot drift apart.
public enum Formatting {

    /// Write a quantity the French way: no trailing zeros, comma for decimals.
    /// 150 becomes "150", 0.5 becomes "0,5", 1.25 becomes "1,25".
    public static func number(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e9 {
            return String(Int(value.rounded()))
        }
        let rounded = (value * 100).rounded() / 100
        var s = String(format: "%.2f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",")
    }

    /// Read a quantity written by a person: "150", "0,5", "1.25", "1/2", "1 1/2".
    public static func parseNumber(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !s.isEmpty else { return nil }

        // Mixed number, "1 1/2".
        let parts = s.split(separator: " ")
        if parts.count == 2, let whole = Double(parts[0]), let fraction = fractionValue(String(parts[1])) {
            return whole + fraction
        }
        if let fraction = fractionValue(s) { return fraction }
        return Double(s)
    }

    private static func fractionValue(_ s: String) -> Double? {
        let bits = s.split(separator: "/")
        guard bits.count == 2,
              let numerator = Double(bits[0]), let denominator = Double(bits[1]),
              denominator != 0 else { return nil }
        return numerator / denominator
    }

    /// "1 h 20" for 80 minutes, "45 min" for 45.
    public static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest)"
    }
}
