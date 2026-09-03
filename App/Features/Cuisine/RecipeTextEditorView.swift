import SwiftUI
import FlaunedexCore

/// Edit the whole recipe as plain text.
///
/// This is what makes a recipe that arrived from a chatbot the cook's own. The
/// entire thing, including everything the model wrote, is just text here:
/// rewrite a step, delete an ingredient, add three of your own, rename the
/// dish. On save it is parsed straight back into the structured recipe the app
/// stores, searches and rescales, and the card stops crediting the model.
///
/// The live counter under the editor is there so the cook can see the format
/// was understood before committing, rather than saving and discovering that a
/// heading typo swallowed the ingredients.
struct RecipeTextEditorView: View {
    let recipe: Recipe

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var showingHelp = false

    private var preview: ParsedRecipeText { RecipeTextFormat.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .autocorrectionDisabled(false)
                    .padding(.horizontal, 12)

                Divider()
                summaryBar
            }
            .navigationTitle("Modifier le texte")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.cuisine)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.applyFreeText(text, to: recipe)
                        dismiss()
                    }
                    .disabled(preview.draft.title.isEmpty)
                }
            }
            .sheet(isPresented: $showingHelp) { FormatHelpView() }
        }
        .onAppear {
            text = RecipeTextFormat.render(recipe.draft, notes: recipe.notes)
        }
    }

    /// What the app will actually store if the cook saves right now.
    private var summaryBar: some View {
        let parsed = preview.draft
        return HStack(spacing: 14) {
            Label("\(parsed.ingredients.count)", systemImage: "list.bullet")
            Label("\(parsed.steps.count)", systemImage: "list.number")
            if let servings = parsed.servings {
                Label("\(servings)", systemImage: "person.2")
            }
            if preview.notes != nil {
                Image(systemName: "note.text")
            }
            Spacer()
            if parsed.title.isEmpty {
                Text("Il manque un titre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

/// The format, explained in the app rather than assumed.
private struct FormatHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Écrivez comme vous voulez. L'application reconnaît quelques repères simples et se débrouille avec le reste.")
                        .font(.subheadline)
                }
                Section("Les repères") {
                    help("# Titre du plat", "La première ligne, précédée d'un dièse.")
                    help("Pour 4 personnes · Préparation 20 min · Cuisson 35 min",
                         "Une ligne de repères, séparés par des points médians.")
                    help("## Ingrédients", "Puis une ligne par ingrédient, commençant par un tiret.")
                    help("## Préparation", "Puis les étapes numérotées, une par ligne.")
                    help("## Mes notes", "Vos remarques. Elles restent les vôtres.")
                }
                Section {
                    help("150 g de sucre", "Quantité, unité, ingrédient.")
                    help("6 pommes (Reine des reinettes)", "Sans unité pour ce qui se compte. La parenthèse est une précision.")
                    help("2 c. à soupe d'huile d'olive", "Les cuillères s'écrivent comme ça.")
                    help("3. Laisser reposer. (20 min)", "Une durée entre parenthèses à la fin d'une étape.")
                } header: {
                    Text("Écrire une quantité")
                } footer: {
                    Text("Si vous collez une recette en tasses, en onces ou en Fahrenheit, elle est convertie en grammes, millilitres et degrés Celsius à l'enregistrement.")
                }
            }
            .navigationTitle("Comment écrire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    private func help(_ example: String, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(example)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.cuisine)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
