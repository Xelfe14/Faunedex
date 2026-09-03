import SwiftUI
import FlaunedexCore

/// Ask for a recipe. The one screen where the chatbot is visible.
///
/// The number of eaters and the constraints are separate fields rather than
/// left to the sentence, because they are the two things that must reach the
/// model exactly: quantities are computed for that count, and a dietary
/// constraint buried in prose is a constraint that gets forgotten.
struct RecipeAskView: View {
    @Environment(RecipeStore.self) private var store
    @Environment(APIKeys.self) private var keys

    @State private var query = ""
    @State private var servings = 4
    @State private var constraints = ""
    @State private var maxMinutes: Int?
    @State private var created: Recipe?
    @State private var errorMessage: String?

    @FocusState private var queryFocused: Bool

    /// Starting points, so the screen is never a blank box.
    private let ideas = [
        "une tarte aux poireaux",
        "un curry thaï vert au poulet",
        "des pâtes aux fruits de mer",
        "un gâteau au chocolat sans gluten",
        "une soupe d'automne au potiron",
        "un plat végétarien avec ce qui traîne au frigo",
    ]

    private var canAsk: Bool {
        keys.hasGeminiKey && !query.trimmingCharacters(in: .whitespaces).isEmpty && !store.isWorking
    }

    var body: some View {
        Form {
            if !keys.hasGeminiKey {
                Section {
                    Label("Ajoutez votre clé Gemini dans Réglages pour demander une recette.",
                          systemImage: "key.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                TextField("Ce que vous avez envie de cuisiner", text: $query, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($queryFocused)
            } header: {
                Text("Votre envie")
            } footer: {
                Text("Décrivez le plat, ou juste les ingrédients que vous avez sous la main.")
            }

            if query.isEmpty {
                Section("Quelques idées") {
                    ForEach(ideas, id: \.self) { idea in
                        Button {
                            query = idea
                            queryFocused = true
                        } label: {
                            Label(idea, systemImage: "lightbulb")
                                .font(.subheadline)
                        }
                    }
                }
            }

            Section("Pour combien de personnes") {
                Stepper {
                    HStack {
                        Text("\(servings) personne\(servings > 1 ? "s" : "")")
                        Spacer()
                    }
                } onIncrement: {
                    servings = min(24, servings + 1)
                } onDecrement: {
                    servings = max(1, servings - 1)
                }
            }

            Section {
                TextField("Végétarien, sans lactose, peu épicé…", text: $constraints, axis: .vertical)
                    .lineLimit(1...3)
                Picker("Temps maximum", selection: $maxMinutes) {
                    Text("Peu importe").tag(Int?.none)
                    ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                        Text(Formatting.duration(minutes: minutes)).tag(Int?.some(minutes))
                    }
                }
            } header: {
                Text("Contraintes")
            } footer: {
                Text("Les quantités seront toujours en grammes, millilitres et degrés Celsius.")
            }

            Section {
                Button(action: ask) {
                    HStack {
                        if store.isWorking {
                            ProgressView().tint(Theme.cuisine)
                            Text("Le chef réfléchit…")
                        } else {
                            Label("Demander la recette", systemImage: "sparkles")
                        }
                        Spacer()
                    }
                    .font(.headline)
                }
                .disabled(!canAsk)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    created = store.createBlank()
                } label: {
                    Label("Écrire une recette moi-même", systemImage: "square.and.pencil")
                }
            } footer: {
                Text("Une recette vide, à remplir en texte libre.")
            }
        }
        .navigationTitle("Nouvelle recette")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.cuisine)
        .navigationDestination(item: $created) { recipe in
            RecipeDetailView(recipe: recipe)
        }
    }

    private func ask() {
        errorMessage = nil
        let request = RecipeRequest(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            servings: servings,
            constraints: constraints.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : constraints,
            maxMinutes: maxMinutes
        )
        Task {
            do {
                created = try await store.generate(request: request)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? RecipeStore.frenchMessage(for: error)
            }
        }
    }
}
