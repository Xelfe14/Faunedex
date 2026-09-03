import Foundation

/// The Gemini `responseSchema` and French system prompt for recipe writing.
/// Schema and prompt live together for the same reason they do on the
/// identification side: every field in one is described in the other, and they
/// have to move together.
public enum RecipeSchema {

    /// Field order fed to `propertyOrdering`. `title` first so the model
    /// commits to a dish before it writes anything that depends on it, and
    /// `ingredients` before `steps` because the steps refer back to them.
    public static let propertyOrder = [
        "title", "summary_fr", "servings", "prep_minutes", "cook_minutes",
        "difficulty", "course", "cuisine",
        "ingredients", "steps",
        "chef_tip_fr", "allergens_fr", "photo_query", "tags",
    ]

    private static func string(nullable: Bool = false) -> JSONValue {
        var pairs: [(String, JSONValue)] = [("type", .str("string"))]
        if nullable { pairs.append(("nullable", .bool(true))) }
        return .obj(pairs)
    }

    private static func stringEnum(_ values: [String], nullable: Bool = false) -> JSONValue {
        var pairs: [(String, JSONValue)] = [("type", .str("string")), ("enum", .strings(values))]
        if nullable { pairs.append(("nullable", .bool(true))) }
        return .obj(pairs)
    }

    private static func integer(nullable: Bool = false) -> JSONValue {
        var pairs: [(String, JSONValue)] = [("type", .str("integer"))]
        if nullable { pairs.append(("nullable", .bool(true))) }
        return .obj(pairs)
    }

    /// The unit vocabulary offered to the model. Because this is an `enum` in
    /// the response schema, a cup or an ounce is not a discouraged answer, it is
    /// an invalid one: the API itself will not let the model emit it. That is
    /// the mechanism behind the promise that amounts are always European.
    public static var allowedUnits: [String] { MetricUnit.allCases.map(\.rawValue) }

    public static var responseSchema: JSONValue {
        let ingredientItem: JSONValue = .obj([
            ("type", .str("object")),
            ("properties", .obj([
                ("quantity", .obj([("type", .str("number")), ("nullable", .bool(true))])),
                ("unit", stringEnum(allowedUnits, nullable: true)),
                ("name", string()),
                ("note", string(nullable: true)),
            ])),
            ("required", .strings(["quantity", "unit", "name", "note"])),
            ("propertyOrdering", .strings(["quantity", "unit", "name", "note"])),
        ])

        let stepItem: JSONValue = .obj([
            ("type", .str("object")),
            ("properties", .obj([
                ("text", string()),
                ("minutes", integer(nullable: true)),
            ])),
            ("required", .strings(["text", "minutes"])),
            ("propertyOrdering", .strings(["text", "minutes"])),
        ])

        return .obj([
            ("type", .str("object")),
            ("properties", .obj([
                ("title", string()),
                ("summary_fr", string(nullable: true)),
                ("servings", integer()),
                ("prep_minutes", integer(nullable: true)),
                ("cook_minutes", integer(nullable: true)),
                ("difficulty", stringEnum(RecipeDifficulty.allCases.map(\.rawValue), nullable: true)),
                ("course", stringEnum(RecipeCourse.allCases.map(\.rawValue), nullable: true)),
                ("cuisine", string(nullable: true)),
                ("ingredients", .obj([("type", .str("array")), ("items", ingredientItem)])),
                ("steps", .obj([("type", .str("array")), ("items", stepItem)])),
                ("chef_tip_fr", string(nullable: true)),
                ("allergens_fr", .obj([
                    ("type", .str("array")), ("items", string()), ("nullable", .bool(true)),
                ])),
                ("photo_query", string(nullable: true)),
                ("tags", .obj([
                    ("type", .str("array")), ("items", string()), ("nullable", .bool(true)),
                ])),
            ])),
            ("required", .strings(propertyOrder)),
            ("propertyOrdering", .strings(propertyOrder)),
        ])
    }

    /// The French system prompt. The measurement rules are stated as hard
    /// constraints rather than preferences, because the schema can stop a bad
    /// `unit` value but cannot stop "environ deux tasses" appearing inside a
    /// step written as prose.
    public static let systemPrompt = """
    Tu es un chef de cuisine francophone qui écrit des recettes claires, fiables et \
    reproductibles à la maison. On te demande une recette ; tu renseignes un objet JSON conforme \
    au schéma imposé. N'ajoute aucun texte hors du JSON.

    Règles de mesure, impératives et sans exception :
    - Toutes les masses en grammes (g) ou kilogrammes (kg). Jamais d'onces ni de livres.
    - Tous les volumes en millilitres (ml), centilitres (cl) ou litres (l). Jamais de tasses, \
    de cups, de pintes ni d'onces liquides.
    - Toutes les températures en degrés Celsius (°C), écrites « 180 °C ». Jamais de Fahrenheit, \
    y compris à l'intérieur des étapes.
    - Toutes les durées en minutes entières.
    - Les cuillères sont « c. à soupe » (15 ml) et « c. à café » (5 ml).
    - Utilise « pièce » pour ce qui se compte (œufs, pommes), « gousse », « brin », « botte », \
    « tranche », « feuille », « sachet » quand c'est la façon naturelle d'acheter l'ingrédient.
    - Un ingrédient ajouté « au goût » prend l'unité « au goût » et aucune quantité.

    Règles de contenu :
    - « ingredients » d'abord, dans l'ordre où on s'en sert, chacun avec sa quantité exacte pour \
    le nombre de personnes demandé. Un ingrédient par entrée, jamais « sel et poivre » ensemble.
    - « steps » ensuite : des étapes numérotées, chacune une action concrète et vérifiable, dans \
    l'ordre. Indique les repères sensoriels (« jusqu'à ce que le beurre mousse et blondisse ») \
    plutôt que des consignes vagues. Renseigne « minutes » quand l'étape consiste surtout à \
    attendre (repos, cuisson, levée).
    - « summary_fr » : une à deux phrases sur ce qu'est le plat et ce qu'on obtient.
    - « chef_tip_fr » : un seul conseil, celui qui fait vraiment la différence sur ce plat \
    (le tour de main, l'erreur classique à éviter).
    - « allergens_fr » : les allergènes majeurs présents (gluten, lait, œuf, fruits à coque, \
    poisson, crustacés, soja, sésame, moutarde, sulfites…). Liste vide s'il n'y en a pas.
    - « photo_query » : le nom courant du plat terminé, en français, tel qu'on le chercherait dans \
    une encyclopédie (« Tarte Tatin », « Blanquette de veau »). Pas de phrase.
    - « tags » : deux à cinq mots-clés en français courant, utiles pour ranger la recette \
    (« végétarien », « rapide », « de saison », « sans gluten », « plat unique »).

    Écris tout en français naturel et soigné, sans markdown à l'intérieur des chaînes.
    """

    /// The user turn, built from what the cook actually asked for.
    public static func userInstruction(request: RecipeRequest) -> String {
        var lines = ["Écris la recette demandée : \(request.query)."]
        lines.append("Prévois exactement \(request.servings) personne\(request.servings > 1 ? "s" : "").")
        if let constraints = request.constraints, !constraints.isEmpty {
            lines.append("Contraintes à respecter absolument : \(constraints).")
        }
        if let maxMinutes = request.maxMinutes {
            lines.append("Le temps total (préparation + cuisson) ne doit pas dépasser \(maxMinutes) minutes.")
        }
        return lines.joined(separator: " ")
    }

    /// Appended when the cook asks for a change to a recipe they already have,
    /// so the model adjusts that dish instead of inventing a different one.
    public static func revisionInstruction(existing: String, change: String) -> String {
        """
        Voici la recette actuelle :

        \(existing)

        Modifie-la ainsi : \(change). Garde tout le reste identique autant que possible, \
        et renvoie la recette complète et à jour.
        """
    }
}

/// What the cook asked for.
public struct RecipeRequest: Sendable, Equatable {
    /// Free text: "une tarte aux poireaux", "un curry thaï vert au poulet".
    public var query: String
    public var servings: Int
    /// Dietary or practical constraints: "végétarien, sans gluten".
    public var constraints: String?
    /// A ceiling on total time, when the cook is in a hurry.
    public var maxMinutes: Int?

    public init(query: String, servings: Int = 4, constraints: String? = nil, maxMinutes: Int? = nil) {
        self.query = query
        self.servings = max(1, servings)
        self.constraints = constraints
        self.maxMinutes = maxMinutes
    }
}
