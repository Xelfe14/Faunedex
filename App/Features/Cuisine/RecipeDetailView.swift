import SwiftUI
import SwiftData
import UIKit
import FlaunedexCore

/// One recipe card: the photograph, the ingredients, the steps, and everything
/// the cook has added on top.
///
/// Built as a List rather than a scrolling stack so the two things the cook
/// asked for come for free and behave the way iOS users expect: swipe an
/// ingredient or a step away, and drag either into a different order.
struct RecipeDetailView: View {
    @Bindable var recipe: Recipe

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecipes: [Recipe]

    /// Steps ticked off during this cooking session. Deliberately not stored:
    /// it is a scratchpad for tonight's dinner, not part of the recipe.
    @State private var doneSteps: Set<UUID> = []
    @State private var draftServings: Int?
    @State private var noteDraft = ""
    @FocusState private var notesFocused: Bool

    @State private var showingTextEditor = false
    @State private var showingVariation = false
    @State private var showingTags = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private var tagSuggestions: [String] {
        RecipeDraft.uniqueTrimmed(allRecipes.flatMap(\.tags))
    }

    var body: some View {
        List {
            heroSection
            headerSection
            if !recipe.ingredients.isEmpty || recipe.source == .manual { ingredientsSection }
            if !recipe.steps.isEmpty || recipe.source == .manual { stepsSection }
            if let tip = recipe.chefTipFR, !tip.isEmpty { tipSection(tip) }
            if !recipe.allergens.isEmpty { allergensSection }
            notesSection
            tagsSection
            cookedSection
            provenanceSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.cuisine)
        .toolbar { toolbar }
        .onAppear { noteDraft = recipe.notes ?? "" }
        .onDisappear { commitNotes() }
        .sheet(isPresented: $showingTextEditor) {
            RecipeTextEditorView(recipe: recipe)
        }
        .sheet(isPresented: $showingVariation) {
            RecipeVariationSheet(recipe: recipe)
        }
        .sheet(isPresented: $showingTags) {
            NavigationStack {
                Form {
                    Section {
                        TagEditor(
                            tags: Binding(
                                get: { recipe.tags },
                                set: { store.setTags($0, on: recipe) }
                            ),
                            suggestions: tagSuggestions
                        )
                    } footer: {
                        Text("Les étiquettes servent à filtrer votre banque de recettes.")
                    }
                }
                .navigationTitle("Étiquettes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Terminé") { showingTags = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Supprimer cette recette ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                store.delete(recipe)
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Vos notes sur cette recette seront perdues.")
        }
        .alert("Impossible", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    @ViewBuilder private var heroSection: some View {
        if recipe.imageURLString != nil || recipe.localImagePath != nil {
            Section {
                RecipeImage(recipe: recipe)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title).font(Theme.display(23))
                if let summary = recipe.summaryFR {
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // A flow layout rather than stacked HStacks: a fixed row squeezes
                // "Cuisson 45 min" until it breaks across three lines, whereas
                // these wrap whole chips onto the next line.
                FlowRow(spacing: 6) {
                    if recipe.prepMinutes > 0 {
                        Chip(text: "Prép. \(Formatting.duration(minutes: recipe.prepMinutes))",
                             systemImage: "hands.sparkles", tint: Theme.cuisine)
                    }
                    if recipe.cookMinutes > 0 {
                        Chip(text: "Cuisson \(Formatting.duration(minutes: recipe.cookMinutes))",
                             systemImage: "flame", tint: Theme.cuisine)
                    }
                    if let difficulty = recipe.difficulty {
                        Chip(text: difficulty.frenchLabel, systemImage: "chart.bar", tint: Theme.cuisine)
                    }
                    if let course = recipe.course {
                        Chip(text: course.frenchLabel, systemImage: course.symbolName, tint: Theme.cuisine)
                    }
                    if let cuisine = recipe.cuisine {
                        Chip(text: "Cuisine \(cuisine)", systemImage: "globe", tint: Theme.cuisine)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var ingredientsSection: some View {
        Section {
            if let target = draftServings, target != recipe.servings {
                Button {
                    store.rescale(recipe, toServings: target)
                    draftServings = nil
                } label: {
                    Label("Recalculer pour \(target) personne\(target > 1 ? "s" : "")",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
            }
            ForEach(recipe.ingredients) { ingredient in
                Text(ingredient.displayLine)
                    .font(.subheadline)
            }
            .onDelete { store.removeIngredient(at: $0, from: recipe) }
            .onMove { store.moveIngredient(from: $0, to: $1, in: recipe) }
        } header: {
            HStack {
                Text("Ingrédients")
                Spacer()
                servingsControl
            }
        } footer: {
            Text("Balayez un ingrédient pour le supprimer. Changez le nombre de personnes pour recalculer toutes les quantités.")
        }
    }

    /// Rescaling is applied once, when the cook stops adjusting, rather than on
    /// every tap. Four separate scalings would round four times and drift; one
    /// scaling from the current count to the target does not.
    private var servingsControl: some View {
        HStack(spacing: 6) {
            Text("\(draftServings ?? recipe.servings) pers.")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(draftServings == nil ? Color.secondary : Theme.cuisine)
            Stepper("Nombre de personnes") {
                draftServings = min(24, (draftServings ?? recipe.servings) + 1)
            } onDecrement: {
                draftServings = max(1, (draftServings ?? recipe.servings) - 1)
            }
            .labelsHidden()
            .fixedSize()
        }
        .textCase(nil)
    }

    private var stepsSection: some View {
        Section {
            ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                Button {
                    if doneSteps.contains(step.id) { doneSteps.remove(step.id) }
                    else { doneSteps.insert(step.id) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(doneSteps.contains(step.id) ? .secondary : Theme.cuisine)
                            .frame(width: 20, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.text)
                                .font(.subheadline)
                                .strikethrough(doneSteps.contains(step.id))
                                .foregroundStyle(doneSteps.contains(step.id) ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let minutes = step.minutes {
                                RecipeFact(systemImage: "timer", text: Formatting.duration(minutes: minutes))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { store.removeStep(at: $0, from: recipe) }
            .onMove { store.moveStep(from: $0, to: $1, in: recipe) }
        } header: {
            Text("Préparation")
        } footer: {
            Text("Touchez une étape pour la cocher pendant que vous cuisinez.")
        }
    }

    private func tipSection(_ tip: String) -> some View {
        Section {
            Label {
                Text(tip).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb.fill").foregroundStyle(Theme.treasure)
            }
        } header: {
            Text("Astuce du chef")
        }
    }

    private var allergensSection: some View {
        Section {
            Text(recipe.allergens.joined(separator: ", "))
                .font(.subheadline)
        } header: {
            Text("Allergènes")
        } footer: {
            Text("Liste indicative, écrite par un modèle. Vérifiez toujours les étiquettes en cas d'allergie.")
        }
    }

    private var notesSection: some View {
        Section {
            TextEditor(text: $noteDraft)
                .frame(minHeight: 90)
                .focused($notesFocused)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if noteDraft.isEmpty {
                        Text("Ce que vous avez changé, ce qui a marché, ce qu'il faut faire autrement…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            if notesFocused {
                Button("Enregistrer mes notes") {
                    commitNotes()
                    notesFocused = false
                }
                .font(.subheadline.weight(.semibold))
            }
        } header: {
            Text("Mes notes")
        } footer: {
            Text("Vos notes vous appartiennent : elles ne sont jamais réécrites quand vous demandez une variante.")
        }
    }

    private var tagsSection: some View {
        Section {
            Button {
                showingTags = true
            } label: {
                HStack {
                    Label("Étiquettes", systemImage: "tag")
                    Spacer()
                    Text(recipe.tags.isEmpty ? "Aucune" : recipe.tags.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                // A plain button only hit-tests what it draws, so without this
                // the gap between the label and the value swallows taps.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var cookedSection: some View {
        Section {
            Button {
                store.recordCooked(recipe)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Je l'ai cuisinée", systemImage: "checkmark.seal")
            }
            if recipe.timesCooked > 0 {
                HStack {
                    Text("Cuisinée")
                    Spacer()
                    Text("\(recipe.timesCooked) fois").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }

    private var provenanceSection: some View {
        Section {
            HStack {
                RecipeSourceBadge(source: recipe.source)
                Spacer()
            }
            if let prompt = recipe.originalPrompt {
                Text("Demandé : « \(prompt) »")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let url = recipe.articleURL {
                Link(destination: url) {
                    Label("La photo vient de cet article", systemImage: "safari")
                        .font(.caption)
                }
            }
            AttributionLabel(prefix: "Photo", artist: recipe.imageArtist,
                             licenseShort: recipe.imageLicenseShort,
                             licenseURLString: recipe.imageLicenseURL,
                             sourcePageURLString: recipe.imageSourcePageURL)
        } footer: {
            Text("Les recettes écrites par un modèle peuvent contenir des erreurs. Goûtez, ajustez, et fiez-vous à votre jugement.")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                store.toggleFavorite(recipe)
            } label: {
                Image(systemName: recipe.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(recipe.isFavorite ? Theme.treasure : Theme.cuisine)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showingTextEditor = true
                } label: {
                    Label("Modifier le texte", systemImage: "square.and.pencil")
                }
                Button {
                    showingVariation = true
                } label: {
                    Label("Demander une variante", systemImage: "sparkles")
                }
                .disabled(!store.hasGeminiKey)
                Button {
                    Task { await store.refreshPhoto(for: recipe) }
                } label: {
                    Label("Chercher une photo", systemImage: "photo")
                }
                Divider()
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } label: {
                Label("Modifier", systemImage: "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) { EditButton() }
    }

    private func commitNotes() {
        guard noteDraft != (recipe.notes ?? "") else { return }
        store.setNotes(noteDraft, on: recipe)
    }
}

/// Ask the model to change a recipe that already exists.
struct RecipeVariationSheet: View {
    let recipe: Recipe

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var change = ""
    @State private var errorMessage: String?

    private let ideas = ["sans lactose", "végétarien", "plus rapide", "moins sucré",
                         "avec ce que j'ai : ", "version plus légère"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ce que vous voulez changer", text: $change, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Votre demande")
                } footer: {
                    Text("La recette actuelle est envoyée au chef, qui l'adapte plutôt que d'en inventer une autre. Vos notes ne sont pas touchées.")
                }

                Section("Suggestions") {
                    ForEach(ideas, id: \.self) { idea in
                        Button(idea) { change = idea }
                            .font(.subheadline)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Variante")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.cuisine)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isWorking {
                        ProgressView()
                    } else {
                        Button("Demander", action: submit)
                            .disabled(change.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func submit() {
        errorMessage = nil
        Task {
            do {
                try await store.revise(recipe, change: change.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? RecipeStore.frenchMessage(for: error)
            }
        }
    }
}
