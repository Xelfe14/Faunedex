import Foundation

/// The Gemini `responseSchema` and French system prompt for knowledge cards.
/// Kept together for the same reason as on the recipe side: every field in one
/// is described in the other, and they have to move together.
public enum KnowledgeSchema {

    /// Field order fed to `propertyOrdering`. The title and the one-sentence
    /// summary come first so the model commits to what the card is about before
    /// it explains it; the etymology follows the definition, as in a
    /// dictionary; the flashcard comes after the explanation it tests.
    public static let propertyOrder = [
        "title", "theme", "summary_fr", "etymology_fr", "body_fr", "key_points_fr",
        "question_fr", "answer_fr", "fun_fact_fr", "wikipedia_query", "tags",
    ]

    private static func string(nullable: Bool = false) -> JSONValue {
        var pairs: [(String, JSONValue)] = [("type", .str("string"))]
        if nullable { pairs.append(("nullable", .bool(true))) }
        return .obj(pairs)
    }

    private static func strings(nullable: Bool = false) -> JSONValue {
        var pairs: [(String, JSONValue)] = [("type", .str("array")), ("items", string())]
        if nullable { pairs.append(("nullable", .bool(true))) }
        return .obj(pairs)
    }

    /// The schema, with `theme` limited to the learner's own category names,
    /// so a card lands on one of their shelves and never on an invented one.
    public static func responseSchema(categories: [String]) -> JSONValue {
        var theme: [(String, JSONValue)] = [("type", .str("string"))]
        if !categories.isEmpty { theme.append(("enum", .strings(categories))) }
        return .obj([
            ("type", .str("object")),
            ("properties", .obj([
                ("title", string()),
                ("theme", .obj(theme)),
                ("summary_fr", string()),
                ("etymology_fr", string(nullable: true)),
                ("body_fr", string()),
                ("key_points_fr", strings()),
                ("question_fr", string()),
                ("answer_fr", string()),
                ("fun_fact_fr", string(nullable: true)),
                ("wikipedia_query", string(nullable: true)),
                ("tags", strings(nullable: true)),
            ])),
            ("required", .strings(propertyOrder)),
            ("propertyOrdering", .strings(propertyOrder)),
        ])
    }

    /// The French system prompt. Accuracy is stated as a hard rule, because a
    /// card is made to be memorised: a wrong date learned by heart is worse
    /// than no card at all.
    public static let systemPrompt = """
    Tu es un vulgarisateur francophone rigoureux, à mi-chemin entre l'encyclopédiste et le \
    professeur. On te donne un sujet ; tu écris UNE fiche de connaissance claire, exacte et facile \
    à retenir, en renseignant un objet JSON conforme au schéma imposé. N'ajoute aucun texte hors \
    du JSON.

    Règles d'exactitude, impératives :
    - Uniquement des faits établis et vérifiables. N'invente jamais une date, un chiffre, une \
    citation ni une source.
    - Quand un point est débattu ou incertain, dis-le dans le texte plutôt que de trancher.
    - Si le sujet est ambigu, traite le sens le plus courant et précise-le dans « summary_fr ».

    Champs :
    - « title » : le nom du sujet, court (deux à six mots).
    - « theme » : la rubrique qui convient le mieux, parmi la liste imposée.
    - « summary_fr » : une seule phrase qui dit l'essentiel, celle qu'on garderait si on ne \
    devait en retenir qu'une. Pour un mot ou une expression, c'est sa définition.
    - « etymology_fr » : l'étymologie du mot, ou du terme principal du sujet : la langue \
    d'origine, la forme et le sens premiers, et le chemin jusqu'au sens actuel, en deux à \
    quatre phrases. OBLIGATOIRE quand le sujet est un mot ou une expression à définir. Pour \
    un autre sujet, renseigne-la quand le terme principal a une étymologie qui éclaire le \
    sens ; sinon null. Si l'origine est inconnue ou discutée, dis-le, sans jamais l'inventer.
    - « body_fr » : l'explication, en paragraphes courts séparés par une ligne vide. Commence par \
    le plus important, donne le contexte et le « pourquoi », puis un exemple concret.
    - « key_points_fr » : trois à cinq points à retenir, chacun une phrase courte et autonome.
    - « question_fr » : une question de révision précise dont la réponse se trouve dans la fiche. \
    Jamais une question à laquelle on répond par oui ou non.
    - « answer_fr » : la réponse à cette question, en une ou deux phrases.
    - « fun_fact_fr » : une anecdote vraie et marquante qui aide à mémoriser ; null s'il n'y en a \
    pas de solide.
    - « wikipedia_query » : le titre de l'article Wikipédia en français qui correspond le mieux \
    au sujet (« Photosynthèse », « Bataille de Marignan »). Pas de phrase.
    - « tags » : deux à quatre mots-clés en français courant.

    Écris tout en français naturel et soigné, sans markdown à l'intérieur des chaînes : ni titres, \
    ni gras, ni puces.
    """

    /// The user turn, built from what the learner asked for.
    public static func userInstruction(request: KnowledgeRequest) -> String {
        var lines = ["Écris une fiche de connaissance sur : \(request.subject)."]
        switch request.depth {
        case .essentiel:
            lines.append("Niveau : l'essentiel. « body_fr » tient en deux paragraphes courts, 120 mots environ au total.")
        case .approfondi:
            lines.append("Niveau : approfondi. « body_fr » compte quatre ou cinq paragraphes, 350 mots environ au total, avec les nuances et les notions liées.")
        }
        if request.asksForDefinition {
            lines.append("Le sujet est un mot ou une expression à définir : « summary_fr » en donne la définition et « etymology_fr » est obligatoire.")
        }
        if let focus = request.focus?.trimmingCharacters(in: .whitespacesAndNewlines), !focus.isEmpty {
            lines.append("Insiste en particulier sur : \(focus).")
        }
        return lines.joined(separator: " ")
    }

    /// Appended when the learner asks for a change to a card they already
    /// have, so the model amends that card instead of writing another.
    public static func revisionInstruction(existing: String, change: String) -> String {
        """
        Voici la fiche actuelle :

        \(existing)

        Modifie-la ainsi : \(change). Garde tout le reste identique autant que possible, \
        et renvoie la fiche complète et à jour.
        """
    }

    /// The card as plain text, as sent back to the model with a revision.
    public static func render(_ draft: KnowledgeDraft) -> String {
        var lines = ["Titre : \(draft.title)"]
        if let category = draft.category { lines.append("Rubrique : \(category)") }
        if let summary = draft.summaryFR { lines.append("Résumé : \(summary)") }
        if let etymology = draft.etymologyFR { lines.append("Étymologie : \(etymology)") }
        if !draft.bodyFR.isEmpty { lines += ["", "Explication :", draft.bodyFR] }
        if !draft.keyPointsFR.isEmpty {
            lines += ["", "À retenir :"] + draft.keyPointsFR.map { "- \($0)" }
        }
        if draft.questionFR != nil || draft.answerFR != nil { lines.append("") }
        if let question = draft.questionFR { lines.append("Question : \(question)") }
        if let answer = draft.answerFR { lines.append("Réponse : \(answer)") }
        if let fact = draft.funFactFR { lines += ["", "Le saviez-vous : \(fact)"] }
        return lines.joined(separator: "\n")
    }
}
