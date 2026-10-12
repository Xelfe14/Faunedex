import SwiftUI
import SwiftData
import FlaunedexCore

/// One fruit or vegetable from the calendar: when to eat it, what a kilo costs
/// the climate, the cook's recipes that use it, and a way to ask for one.
struct ProduceDetailView: View {
    let produce: Produce

    @Query(sort: \Recipe.sortIndex) private var recipes: [Recipe]
    @State private var askingForRecipe = false

    private let month = SeasonCalendar.currentMonth()

    /// The cook's recipes with this produce in their ingredients, matched the
    /// same way the footprint is computed.
    private var usingRecipes: [Recipe] {
        recipes.filter { recipe in
            recipe.ingredients.contains { FoodCatalog.match($0.name)?.produceID == produce.id }
        }
    }

    private var farMonths: Set<Int> {
        produce.availableMonths.subtracting(produce.franceMonths).subtracting(produce.europeMonths)
    }

    var body: some View {
        List {
            headerSection
            seasonSection
            impactSection
            recipesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(produce.plainName)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.cuisine)
        .navigationDestination(isPresented: $askingForRecipe) {
            RecipeAskView(initialQuery: "une recette avec \(produce.plainName.lowercased())")
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(produce.name).font(Theme.display(24))
                HStack(spacing: 10) {
                    Text(produce.category.frenchLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SeasonBadge(status: produce.status(in: month), showsLabel: true)
                }
                SeasonBar(produce: produce, highlight: month, height: 24)
                HStack(spacing: SeasonGrid.spacing) {
                    ForEach(1...12, id: \.self) { m in
                        Text(SeasonCalendar.monthInitials[m - 1])
                            .font(.caption2.weight(m == month ? .heavy : .regular))
                            .foregroundStyle(m == month ? Theme.cuisine : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                SeasonLegend()
            }
            .padding(.vertical, 4)
        }
    }

    private var seasonSection: some View {
        Section {
            let france = SeasonCalendar.describe(produce.franceMonths)
            if !france.isEmpty {
                LabeledContent("En France", value: france)
            }
            let europe = SeasonCalendar.describe(produce.europeMonths.subtracting(produce.franceMonths))
            if !europe.isEmpty {
                LabeledContent("Europe du Sud", value: europe)
            }
            if let origins = produce.origins {
                LabeledContent("D'où", value: origins)
            }
            if produce.farImport {
                let far = SeasonCalendar.describe(farMonths)
                LabeledContent("Importé de loin", value: far.isEmpty ? "le reste de l'année" : far)
            }
            if let note = produce.note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Quand en manger")
        } footer: {
            Text("France : calendrier de l'ADEME. Europe du Sud, origines et imports : estimation indicative.")
        }
    }

    private var impactSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(CarbonComparison.formatPerKilo(produce.kgCO2ePerKg))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.impact(.perKilo(produce.kgCO2ePerKg)))
                Spacer()
            }
            let kilometres = CarbonComparison.carKilometers(produce.kgCO2ePerKg)
            Text("Un kilo pèse autant que \(Formatting.number(max(1, kilometres.rounded()))) km en voiture.")
                .font(.subheadline)
        } header: {
            Text("Impact carbone")
        } footer: {
            Text("Par kilo acheté en France, de la culture au magasin. Source : Impact CO2 (ADEME), Agribalyse 3.2.")
        }
    }

    private var recipesSection: some View {
        Section {
            if usingRecipes.isEmpty {
                Text("Aucune de vos recettes ne l'utilise encore.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(usingRecipes) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        Text(recipe.title).font(.subheadline)
                    }
                }
            }
            Button {
                askingForRecipe = true
            } label: {
                Label("Demander une recette avec ce produit", systemImage: "sparkles")
            }
        } header: {
            Text("Dans vos recettes")
        }
    }
}
