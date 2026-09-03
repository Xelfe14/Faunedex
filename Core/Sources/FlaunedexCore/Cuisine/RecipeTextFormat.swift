import Foundation

/// The result of reading a recipe back out of plain text.
public struct ParsedRecipeText: Sendable, Equatable {
    public var draft: RecipeDraft
    public var notes: String?
    public init(draft: RecipeDraft, notes: String? = nil) {
        self.draft = draft
        self.notes = notes
    }
}

/// Renders a recipe as plain text a person can edit, and reads it back.
///
/// This is what makes a recipe that arrived from a chatbot yours: the whole
/// thing, including the parts the model wrote, is presented as ordinary text in
/// an editor. Rewrite a step, delete an ingredient, add three of your own,
/// change the title, and it parses straight back into the same structured
/// recipe the app stores, searches and scales.
///
/// The contract that makes that safe is a round trip: `parse(render(x)) == x`
/// for any normalised recipe. It is pinned by tests, including on recipes with
/// fractions, notes, accents and rest times.
public enum RecipeTextFormat {

    // MARK: Section headings

    /// Canonical heading titles, and the spellings that are accepted for them.
    /// Matching is accent- and case-insensitive, so "Etapes" finds the steps.
    private enum Section: CaseIterable {
        case ingredients, steps, tip, allergens, tags, notes

        var heading: String {
            switch self {
            case .ingredients: return "Ingrédients"
            case .steps: return "Préparation"
            case .tip: return "Astuce du chef"
            case .allergens: return "Allergènes"
            case .tags: return "Mots-clés"
            case .notes: return "Mes notes"
            }
        }

        var aliases: [String] {
            switch self {
            case .ingredients: return ["ingredients", "ingredient", "les ingredients"]
            case .steps: return ["preparation", "etapes", "etape", "instructions", "steps",
                                 "methode", "realisation", "la preparation"]
            case .tip: return ["astuce du chef", "astuce", "conseil", "conseil du chef",
                               "le truc en plus", "tip"]
            case .allergens: return ["allergenes", "allergens", "allergene"]
            case .tags: return ["mots-cles", "mots cles", "tags", "etiquettes", "mots clefs"]
            case .notes: return ["mes notes", "notes", "note", "mes remarques", "remarques"]
            }
        }

        static func match(_ raw: String) -> Section? {
            let key = fold(raw)
            return allCases.first { $0.aliases.contains(key) || fold($0.heading) == key }
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Render

    public static func render(_ draft: RecipeDraft, notes: String? = nil) -> String {
        let recipe = draft.normalized()
        var lines: [String] = ["# \(recipe.title)"]

        if let summary = recipe.summaryFR {
            lines.append("")
            lines.append(summary)
        }

        let meta = metaLine(recipe)
        if !meta.isEmpty {
            lines.append("")
            lines.append(meta)
        }

        if !recipe.ingredients.isEmpty {
            lines.append("")
            lines.append("## \(Section.ingredients.heading)")
            lines.append(contentsOf: recipe.ingredients.map { "- \($0.displayLine)" })
        }

        if !recipe.steps.isEmpty {
            lines.append("")
            lines.append("## \(Section.steps.heading)")
            for (index, step) in recipe.steps.enumerated() {
                var line = "\(index + 1). \(step.text)"
                if let minutes = step.minutes { line += " (\(Formatting.duration(minutes: minutes)))" }
                lines.append(line)
            }
        }

        if let tip = recipe.chefTipFR {
            lines.append("")
            lines.append("## \(Section.tip.heading)")
            lines.append(tip)
        }

        if !recipe.allergensFR.isEmpty {
            lines.append("")
            lines.append("## \(Section.allergens.heading)")
            lines.append(recipe.allergensFR.joined(separator: ", "))
        }

        if !recipe.tags.isEmpty {
            lines.append("")
            lines.append("## \(Section.tags.heading)")
            lines.append(recipe.tags.joined(separator: ", "))
        }

        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("## \(Section.notes.heading)")
            lines.append(notes.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return lines.joined(separator: "\n")
    }

    /// "Pour 6 personnes · Préparation 30 min · Cuisson 45 min · Facile · Dessert · Cuisine française"
    static func metaLine(_ recipe: RecipeDraft) -> String {
        var parts: [String] = []
        if let servings = recipe.servings {
            parts.append("Pour \(servings) personne\(servings > 1 ? "s" : "")")
        }
        if let prep = recipe.prepMinutes {
            parts.append("Préparation \(Formatting.duration(minutes: prep))")
        }
        if let cook = recipe.cookMinutes {
            parts.append("Cuisson \(Formatting.duration(minutes: cook))")
        }
        if let difficulty = recipe.difficulty { parts.append(difficulty.frenchLabel) }
        if let course = recipe.course { parts.append(course.frenchLabel) }
        if let cuisine = recipe.cuisine { parts.append("Cuisine \(cuisine)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Parse

    public static func parse(_ text: String) -> ParsedRecipeText {
        var title = ""
        var summaryLines: [String] = []
        var ingredientLines: [String] = []
        var stepLines: [String] = []
        var tipLines: [String] = []
        var allergenLines: [String] = []
        var tagLines: [String] = []
        var noteLines: [String] = []
        var meta = MetaValues()

        var current: Section?
        var sawHeading = false
        var sawTitle = false
        /// Lines before any heading that were neither the title nor the meta
        /// line. Used by the fallback when the cook has deleted every heading.
        var loose: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("##") {
                let name = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                current = Section.match(name)
                sawHeading = true
                continue
            }

            if line.hasPrefix("#") {
                title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                sawTitle = true
                current = nil
                continue
            }

            switch current {
            case .ingredients: ingredientLines.append(line)
            case .steps: stepLines.append(line)
            case .tip: tipLines.append(line)
            case .allergens: allergenLines.append(line)
            case .tags: tagLines.append(line)
            case .notes: noteLines.append(line)
            case nil:
                if !sawTitle {
                    title = line
                    sawTitle = true
                } else if meta.absorb(line) {
                    continue
                } else if !sawHeading {
                    loose.append(line)
                }
            }
        }

        // No headings at all: the cook wrote or kept a bare list. Classify what
        // is left by shape, so a hand-typed recipe still becomes structured.
        if !sawHeading {
            for line in loose {
                if isBullet(line) { ingredientLines.append(line) }
                else if isNumbered(line) { stepLines.append(line) }
                else { summaryLines.append(line) }
            }
        } else {
            summaryLines = loose
        }

        let draft = RecipeDraft(
            title: title,
            summaryFR: joined(summaryLines),
            servings: meta.servings,
            prepMinutes: meta.prepMinutes,
            cookMinutes: meta.cookMinutes,
            difficulty: meta.difficulty,
            course: meta.course,
            cuisine: meta.cuisine,
            ingredients: ingredientLines.compactMap(parseIngredient),
            steps: stepLines.compactMap(parseStep),
            chefTipFR: joined(tipLines),
            allergensFR: splitList(allergenLines),
            photoQuery: nil,
            tags: splitList(tagLines)
        ).normalized()

        return ParsedRecipeText(draft: draft, notes: joined(noteLines))
    }

    private static func joined(_ lines: [String]) -> String? {
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func splitList(_ lines: [String]) -> [String] {
        RecipeDraft.uniqueTrimmed(
            lines.flatMap { line in
                stripBullet(line).components(separatedBy: CharacterSet(charactersIn: ",;·"))
            }
        )
    }

    // MARK: Line shapes

    /// Every character a person might reach for to start a list item.
    private static let bulletCharacters: Set<Character> = ["-", "*", "\u{2022}", "\u{2013}", "\u{00B7}"]

    static func isBullet(_ line: String) -> Bool {
        guard let first = line.trimmingCharacters(in: .whitespaces).first else { return false }
        return bulletCharacters.contains(first)
    }

    static func isNumbered(_ line: String) -> Bool {
        numberedPrefixLength(line) != nil
    }

    /// Length of a leading "12. " or "12) " marker, if present.
    private static func numberedPrefixLength(_ line: String) -> Int? {
        var digits = 0
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits += 1
            index = line.index(after: index)
        }
        guard digits > 0, index < line.endIndex, line[index] == "." || line[index] == ")" else { return nil }
        return line.distance(from: line.startIndex, to: line.index(after: index))
    }

    /// Remove a leading list marker, whether it is a bullet or a number.
    /// A line that is nothing but a marker comes back empty, and the caller
    /// drops it rather than storing an ingredient called "-".
    static func stripBullet(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, bulletCharacters.contains(first) {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if let length = numberedPrefixLength(trimmed) {
            return String(trimmed.dropFirst(length)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    // MARK: Ingredients

    /// Read "150 g de sucre (bio)" into its parts.
    ///
    /// Anything that does not look like a measurement is kept verbatim as the
    /// ingredient's name. Guessing a quantity that was never written would put
    /// a number in a cook's shopping list that nobody chose.
    public static func parseIngredient(_ rawLine: String) -> RecipeIngredient? {
        var body = stripBullet(rawLine)
        guard !body.isEmpty else { return nil }

        // Trailing "(...)" is a note about the ingredient, not a measurement.
        var note: String?
        if body.hasSuffix(")"), let open = body.lastIndex(of: "(") {
            let inner = body[body.index(after: open)..<body.index(before: body.endIndex)]
            note = inner.trimmingCharacters(in: .whitespaces)
            body = String(body[body.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        }
        guard !body.isEmpty else {
            return note.map { RecipeIngredient(name: $0) }?.normalized()
        }

        var words = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        // Quantity: a plain number, a decimal, a fraction, or "1 1/2".
        var quantity: Double?
        if let first = words.first, let value = Formatting.parseNumber(first) {
            quantity = value
            words.removeFirst()
            if let next = words.first, next.contains("/"), let fraction = Formatting.parseNumber(next) {
                quantity = value + fraction
                words.removeFirst()
            }
        }

        // Unit: longest match over the next few words, so "c. à soupe" wins over "c.".
        var unit: MetricUnit?
        if quantity != nil {
            for wordCount in stride(from: min(4, words.count), through: 1, by: -1) {
                let candidate = words[0..<wordCount].joined(separator: " ")
                if let converted = MetricConversion.toMetric(quantity: quantity ?? 0, unit: candidate) {
                    quantity = converted.quantity
                    unit = converted.unit
                    words.removeFirst(wordCount)
                    break
                }
            }
        }

        // The connector between measurement and ingredient carries no meaning.
        if let first = words.first {
            let folded = fold(first)
            if ["de", "des", "du", "of"].contains(folded) {
                words.removeFirst()
            } else if folded.hasPrefix("d'") || folded.hasPrefix("d\u{2019}") {
                words[0] = String(first.dropFirst(2))
                if words[0].isEmpty { words.removeFirst() }
            }
        }

        let name = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            // "2 gousses" with nothing after it: keep the unit word as the name
            // rather than losing the line.
            guard let unit else { return nil }
            return RecipeIngredient(quantity: quantity, name: unit.label(quantity: quantity)).normalized()
        }
        return RecipeIngredient(quantity: quantity, unit: unit, name: name, note: note).normalized()
    }

    // MARK: Steps

    /// Read "3. Laisser reposer. (20 min)" into text plus a duration.
    public static func parseStep(_ rawLine: String) -> RecipeStep? {
        var body = stripBullet(rawLine)
        guard !body.isEmpty else { return nil }

        var minutes: Int?
        if body.hasSuffix(")"), let open = body.lastIndex(of: "(") {
            let inner = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            if let parsed = Formatting.parseDuration(inner) {
                minutes = parsed
                body = String(body[body.startIndex..<open]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !body.isEmpty else { return nil }
        return RecipeStep(text: body, minutes: minutes).normalized()
    }

    // MARK: Meta line

    /// Accumulates the values found on the "Pour 6 personnes · ..." line.
    private struct MetaValues {
        var servings: Int?
        var prepMinutes: Int?
        var cookMinutes: Int?
        var difficulty: RecipeDifficulty?
        var course: RecipeCourse?
        var cuisine: String?

        /// The duration written after a label such as "Préparation".
        ///
        /// The label already establishes that a duration is meant, so a cook who
        /// types "Cuisson 45" with no unit is still understood, while a bare
        /// number anywhere else is not treated as a time.
        static func duration(after label: String, in foldedKey: String) -> Int? {
            let rest = String(foldedKey.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
            return Formatting.parseDuration(rest) ?? Formatting.firstInteger(in: rest)
        }

        /// Try to read a line as recipe metadata. Returns true when at least one
        /// value was recognised, which tells the caller the line was consumed
        /// and is not part of the summary.
        mutating func absorb(_ line: String) -> Bool {
            let segments = line.components(separatedBy: CharacterSet(charactersIn: "·•|"))
            var recognised = false
            for segment in segments {
                let raw = segment.trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty else { continue }
                let key = RecipeTextFormat.fold(raw)

                if key.hasPrefix("pour "), let value = Formatting.firstInteger(in: key) {
                    servings = value; recognised = true; continue
                }
                if key.hasPrefix("preparation"),
                   let value = MetaValues.duration(after: "preparation", in: key) {
                    prepMinutes = value; recognised = true; continue
                }
                if key.hasPrefix("cuisson"),
                   let value = MetaValues.duration(after: "cuisson", in: key) {
                    cookMinutes = value; recognised = true; continue
                }
                if let match = RecipeDifficulty.allCases.first(where: { RecipeTextFormat.fold($0.rawValue) == key }) {
                    difficulty = match; recognised = true; continue
                }
                if let match = RecipeCourse.allCases.first(where: {
                    RecipeTextFormat.fold($0.rawValue) == key || RecipeTextFormat.fold($0.frenchLabel) == key
                }) {
                    course = match; recognised = true; continue
                }
                if key.hasPrefix("cuisine ") {
                    cuisine = String(raw.dropFirst("cuisine ".count)).trimmingCharacters(in: .whitespaces)
                    recognised = true; continue
                }
                if key.hasSuffix("personnes") || key.hasSuffix("personne"),
                   let value = Formatting.firstInteger(in: key) {
                    servings = value; recognised = true; continue
                }
            }
            return recognised
        }
    }
}

public extension Formatting {

    /// Read "30 min", "1 h", "1 h 20" or "1h20" as a number of minutes.
    ///
    /// An explicit time unit is required, and the whole string has to be the
    /// duration. That strictness is the point: a recipe step ending in
    /// "(100 g)" must stay part of the instruction rather than being read as a
    /// hundred minute rest, and a loose search for digits next to the letter h
    /// would find one inside "chocolat".
    static func parseDuration(_ raw: String) -> Int? {
        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty else { return nil }

        let minuteUnit = "(?:minutes|minute|mins|min|mn)"
        if let groups = capture(folded, "^([0-9]+)\\s*(?:heures|heure|hrs|hr|h)\\s*([0-9]+)?\\s*\(minuteUnit)?$") {
            let hours = groups[0].flatMap(Int.init) ?? 0
            let minutes = groups.count > 1 ? (groups[1].flatMap(Int.init) ?? 0) : 0
            return hours * 60 + minutes
        }
        if let groups = capture(folded, "^([0-9]+)\\s*\(minuteUnit)$") {
            return groups[0].flatMap(Int.init)
        }
        return nil
    }

    /// Capture groups of the first match, or nil if the pattern does not match.
    /// A group that did not participate comes back as nil.
    private static func capture(_ text: String, _ pattern: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }

    static func firstInteger(in raw: String) -> Int? { integers(in: raw).first }

    /// Every run of digits in the string, in order.
    static func integers(in raw: String) -> [Int] {
        var out: [Int] = []
        var current = ""
        for character in raw {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                if let value = Int(current) { out.append(value) }
                current = ""
            }
        }
        if !current.isEmpty, let value = Int(current) { out.append(value) }
        return out
    }
}
