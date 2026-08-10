import Foundation

/// The Gemini `responseSchema` (OpenAPI subset) and the French system prompt.
/// Kept together because they must stay in lock-step: every schema field is
/// described to the model in the prompt.
public enum GeminiSchema {

    /// Field order fed to `propertyOrdering`. `scientific_name` is deliberately
    /// first so the model commits to an identity before writing everything that
    /// hangs off it.
    public static let propertyOrder = [
        "scientific_name", "identified", "confidence",
        "french_name", "english_name", "family", "realm", "animal_group",
        "specificite_fr", "fun_fact_fr", "season_months",
        "toxicity_danger_fr", "similar_species", "candidates", "reasoning",
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

    /// The full response schema.
    public static var responseSchema: JSONValue {
        let similarItem: JSONValue = .obj([
            ("type", .str("object")),
            ("properties", .obj([
                ("name", string()),
                ("how_to_distinguish_fr", string(nullable: true)),
            ])),
            ("required", .strings(["name", "how_to_distinguish_fr"])),
            ("propertyOrdering", .strings(["name", "how_to_distinguish_fr"])),
        ])

        let candidateItem: JSONValue = .obj([
            ("type", .str("object")),
            ("properties", .obj([
                ("scientific_name", string()),
                ("common_name_fr", string(nullable: true)),
                ("probability", .obj([("type", .str("number")), ("nullable", .bool(true))])),
            ])),
            ("required", .strings(["scientific_name", "common_name_fr", "probability"])),
            ("propertyOrdering", .strings(["scientific_name", "common_name_fr", "probability"])),
        ])

        return .obj([
            ("type", .str("object")),
            ("properties", .obj([
                ("scientific_name", string(nullable: true)),
                ("identified", .obj([("type", .str("boolean"))])),
                ("confidence", stringEnum(["high", "medium", "low"])),
                ("french_name", string(nullable: true)),
                ("english_name", string(nullable: true)),
                ("family", string(nullable: true)),
                ("realm", stringEnum(["plant", "animal", "fungus"], nullable: true)),
                ("animal_group", stringEnum(
                    ["mammal", "bird", "reptile", "amphibian", "fish", "insect", "arachnid", "mollusk", "other"],
                    nullable: true)),
                ("specificite_fr", string(nullable: true)),
                ("fun_fact_fr", string(nullable: true)),
                ("season_months", .obj([
                    ("type", .str("array")),
                    ("items", .obj([("type", .str("integer")), ("minimum", .int(1)), ("maximum", .int(12))])),
                    ("nullable", .bool(true)),
                ])),
                ("toxicity_danger_fr", string(nullable: true)),
                ("similar_species", .obj([
                    ("type", .str("array")), ("items", similarItem), ("nullable", .bool(true)),
                ])),
                ("candidates", .obj([
                    ("type", .str("array")), ("items", candidateItem), ("nullable", .bool(true)),
                ])),
                ("reasoning", string(nullable: true)),
            ])),
            ("required", .strings(propertyOrder)),
            ("propertyOrdering", .strings(propertyOrder)),
        ])
    }

    /// The French system prompt. It defines the naturalist voice and describes
    /// every field, mirroring the "Spécificité / Fun Fact" style the user liked.
    public static let systemPrompt = """
    Tu es un naturaliste expert de la faune et de la flore d'Europe. On te fournit UNE photo prise \
    sur le terrain. Identifie l'espèce (plante, animal, oiseau, insecte, etc.) avec le plus de \
    précision possible, puis renseigne un objet JSON conforme au schéma imposé. N'ajoute aucun texte \
    hors du JSON.

    Règles d'identification :
    - Donne le nom scientifique binominal latin de l'espèce la plus probable dans « scientific_name ».
    - Sois honnête sur ta certitude via « confidence » (high / medium / low). Si tu hésites entre \
    plusieurs espèces, mets « identified » à false ou « confidence » à low, et liste les hypothèses \
    plausibles dans « candidates » (avec une probabilité entre 0 et 1). Ne présente jamais une \
    identification incertaine comme certaine.
    - « realm » vaut plant, animal ou fungus. Renseigne « animal_group » uniquement pour un animal.

    Style des textes en français (ton d'un passionné, précis mais accessible, sans titres ni \
    markdown à l'intérieur des chaînes) :
    - « specificite_fr » : 2 à 3 phrases sur ce qui caractérise l'espèce — son habitat, où et quand \
    on la rencontre, comment la reconnaître sur le terrain. Faits vérifiables uniquement.
    - « fun_fact_fr » : 2 à 3 phrases pour une anecdote marquante — étymologie du nom, histoire, \
    croyance ancienne, usage traditionnel, particularité de comportement. De quoi retenir l'espèce.
    - « season_months » : les mois (1–12) de floraison pour une plante, ou de plus forte activité / \
    d'observation pour un animal.
    - « toxicity_danger_fr » : signale toute toxicité, venin ou danger, TOUJOURS avec prudence ; \
    laisse null si rien de notable. Ne donne JAMAIS de conseil de consommation ou de comestibilité.
    - « similar_species » : les sosies avec lesquels on peut la confondre et comment les distinguer.

    Concentre-toi sur les espèces présentes en Europe. Écris tous les champs « _fr » dans un français \
    naturel et soigné.
    """

    /// The short user-turn instruction paired with the image.
    public static let userInstruction = "Identifie l'espèce sur cette photo et renseigne le JSON demandé."

    /// Appended when the user has picked a candidate in the review flow: the
    /// model confirms and describes that species instead of starting over.
    public static func hintInstruction(for scientificName: String) -> String {
        "L'observateur pense qu'il s'agit de « \(scientificName) ». Si la photo est compatible, "
        + "retiens cette espèce et renseigne ses informations. Sinon, corrige-la et explique "
        + "brièvement pourquoi dans « reasoning »."
    }
}
