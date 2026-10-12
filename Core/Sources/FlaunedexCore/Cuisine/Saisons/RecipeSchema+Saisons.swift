import Foundation

extension RecipeSchema {

    /// Tell the model what is in season around Paris this month.
    ///
    /// The lists come from the same calendar the Saisons screen draws, so a
    /// recipe asked for in October leans on the leeks and squash the calendar
    /// shows in October, not on what the model happens to associate with the
    /// dish.
    public static func seasonalInstruction(month: Int) -> String {
        let seasonal = ProduceCatalog.seasonal(in: month)
        let names = { (status: SeasonStatus) in
            seasonal.filter { $0.status(in: month) == status }
                .map { $0.plainName.lowercased() }
                .joined(separator: ", ")
        }
        var text = "Nous sommes en \(SeasonCalendar.monthName(month)) et je cuisine à Paris : "
            + "construis la recette autour des fruits et légumes de saison en France ce mois-ci "
            + "(\(names(.france)))."
        let european = names(.europe)
        if !european.isEmpty {
            text += " À défaut, ceux que l'Europe du Sud fournit en ce moment (\(european))."
        }
        text += " Évite les fruits et légumes hors saison ou importés de loin, sauf si ma demande les cite."
        return text
    }

    /// The change sent to the model to make a recipe lighter on the climate,
    /// naming the ingredients that weigh the most so it knows where to act.
    public static func lowerImpactChange(footprint: RecipeFootprint, servings: Int) -> String {
        let heaviest = footprint.contributors.prefix(3).map {
            "\($0.ingredient.displayLine) (≈ \(CarbonComparison.format($0.kgCO2e)))"
        }
        var text = "réduis nettement son empreinte carbone, aujourd'hui d'environ "
            + "\(CarbonComparison.format(footprint.totalKgCO2e)) pour \(servings) "
            + "personne\(servings > 1 ? "s" : "")."
        if !heaviest.isEmpty {
            text += " Ce qui pèse le plus : \(heaviest.joined(separator: ", "))."
        }
        text += " Remplace ou réduis ces ingrédients par des alternatives moins émettrices "
            + "(légumineuses, œufs, volaille ou poisson plutôt que bœuf ou agneau, moins de fromage, "
            + "légumes de saison), en gardant l'esprit et la gourmandise du plat, "
            + "et dis dans le résumé ce qui a été remplacé"
        return text
    }
}
