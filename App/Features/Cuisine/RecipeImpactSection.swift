import SwiftUI
import FlaunedexCore

/// The carbon footprint on a recipe card: the total, what a portion compares
/// with, the ingredients that weigh the most, and what couldn't be counted.
struct RecipeImpactSection: View {
    let footprint: RecipeFootprint
    let servings: Int
    let canAskLighter: Bool
    let isWorking: Bool
    let askLighter: () -> Void

    private var perServing: Double { footprint.perServing(servings) }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(CarbonComparison.format(footprint.totalKgCO2e))
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.impact(.perServing(perServing)))
                    Text("pour \(servings) pers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text("Soit \(CarbonComparison.format(perServing)) par personne, \(CarbonComparison.mealComparison(perServing: perServing)).")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Le plat entier pèse autant que \(Formatting.number(max(1, CarbonComparison.carKilometers(footprint.totalKgCO2e).rounded()))) km en voiture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            ForEach(footprint.contributors.prefix(4)) { line in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(line.ingredient.name).font(.subheadline)
                        Spacer()
                        Text(CarbonComparison.format(line.kgCO2e))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: line.kgCO2e, total: max(footprint.totalKgCO2e, line.kgCO2e))
                        .tint(Theme.impact(.perKilo(line.food?.kgCO2ePerKg ?? 0)))
                }
            }

            if !footprint.notEvaluated.isEmpty {
                Text("Non évalué\(footprint.notEvaluated.count > 1 ? "s" : "") : \(footprint.notEvaluated.map(\.ingredient.name).joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: askLighter) {
                HStack {
                    if isWorking {
                        ProgressView().tint(Theme.cuisine)
                        Text("Le chef cherche des substitutions…")
                    } else {
                        Label("Proposer une version moins émettrice", systemImage: "leaf.arrow.triangle.circlepath")
                    }
                    Spacer()
                }
            }
            .disabled(!canAskLighter || isWorking)
        } header: {
            Text("Impact carbone")
        } footer: {
            Text("De la production au magasin, d'après l'ADEME (Agribalyse 3.2, Impact CO2). La cuisson à la maison n'est pas comptée. La version moins émettrice est enregistrée comme une nouvelle recette.")
        }
    }
}
