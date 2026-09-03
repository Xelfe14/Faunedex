import SwiftUI
import SwiftData
import FlaunedexCore

/// The recipe bank: everything the cook has saved, arranged however they want.
///
/// A list rather than a grid on purpose. The organisation the cook asked for
/// (drag to reorder, swipe to delete, filter by their own tags) all lands
/// naturally in a list, and each row still carries the photograph.
struct RecipesView: View {
    @Query private var recipes: [Recipe]
    @Environment(RecipeStore.self) private var store

    @State private var search = ""
    @State private var sort: SortOrder = .recent
    @State private var favoritesOnly = false
    @State private var course: RecipeCourse?
    @State private var tag: String?
    @State private var pendingDeletion: Recipe?

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent, manual, title, quickest

        var id: String { rawValue }
        var frenchLabel: String {
            switch self {
            case .recent: return "Les plus récentes"
            case .manual: return "Mon classement"
            case .title: return "Ordre alphabétique"
            case .quickest: return "Les plus rapides"
            }
        }
        var symbolName: String {
            switch self {
            case .recent: return "clock.arrow.circlepath"
            case .manual: return "hand.draw"
            case .title: return "textformat.abc"
            case .quickest: return "bolt"
            }
        }
    }

    // MARK: Filtering

    private var filtered: [Recipe] {
        let matching = recipes.filter { recipe in
            (!favoritesOnly || recipe.isFavorite)
            && (course == nil || recipe.course == course)
            && (tag == nil || recipe.tags.contains(tag!))
            && (search.isEmpty || matches(recipe, search))
        }
        return sorted(matching)
    }

    /// Search covers the title, the summary, the cook's own notes and every
    /// ingredient, so "il me reste des poireaux" is answerable.
    private func matches(_ recipe: Recipe, _ query: String) -> Bool {
        if recipe.title.localizedCaseInsensitiveContains(query) { return true }
        if recipe.summaryFR?.localizedCaseInsensitiveContains(query) == true { return true }
        if recipe.notes?.localizedCaseInsensitiveContains(query) == true { return true }
        if recipe.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
        return recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func sorted(_ list: [Recipe]) -> [Recipe] {
        switch sort {
        case .recent: return list.sorted { $0.createdAt > $1.createdAt }
        case .manual: return list.sorted { $0.sortIndex < $1.sortIndex }
        case .title: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .quickest:
            // Recipes with no stated time sink to the bottom rather than
            // pretending to take zero minutes.
            return list.sorted { lhs, rhs in
                let a = lhs.totalMinutes == 0 ? Int.max : lhs.totalMinutes
                let b = rhs.totalMinutes == 0 ? Int.max : rhs.totalMinutes
                return a < b
            }
        }
    }

    private var allCourses: [RecipeCourse] {
        RecipeCourse.allCases.filter { candidate in recipes.contains { $0.course == candidate } }
    }
    private var allTags: [String] {
        RecipeDraft.uniqueTrimmed(recipes.flatMap(\.tags)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
    private var hasFilter: Bool { favoritesOnly || course != nil || tag != nil }

    var body: some View {
        Group {
            if recipes.isEmpty {
                EmptyStateView(
                    title: "Aucune recette",
                    message: "Demandez une recette à Gemini, ou écrivez la vôtre. Elles s'ajouteront ici.",
                    systemImage: "fork.knife"
                )
                .canvasBackground()
            } else {
                list
            }
        }
        .navigationTitle("Recettes")
        .searchable(text: $search, prompt: "Rechercher un plat ou un ingrédient")
        .toolbar { toolbar }
        .confirmationDialog(
            "Supprimer « \(pendingDeletion?.title ?? "") » ?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let recipe = pendingDeletion { store.delete(recipe) }
                pendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Vos notes sur cette recette seront perdues.")
        }
    }

    private var list: some View {
        List {
            if !allCourses.isEmpty || !allTags.isEmpty {
                Section {
                    filterBar
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(filtered) { recipe in
                    NavigationLink { RecipeDetailView(recipe: recipe) } label: { RecipeRow(recipe: recipe) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDeletion = recipe } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { store.toggleFavorite(recipe) } label: {
                                Label(recipe.isFavorite ? "Retirer" : "Favori",
                                      systemImage: recipe.isFavorite ? "star.slash" : "star")
                            }
                            .tint(Theme.treasure)
                        }
                }
                .onMove(perform: sort == .manual ? move : nil)
            } header: {
                Text(countLabel)
            } footer: {
                if sort == .manual {
                    Text("Glissez une recette pour la déplacer dans votre classement.")
                } else if filtered.isEmpty {
                    Text("Aucune recette ne correspond.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var countLabel: String {
        let count = filtered.count
        let total = recipes.count
        if count == total { return "\(total) recette\(total > 1 ? "s" : "")" }
        return "\(count) sur \(total)"
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var ordered = filtered
        ordered.move(fromOffsets: offsets, toOffset: destination)
        store.persistOrder(ordered)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "Favoris", systemImage: "star.fill", isOn: favoritesOnly) {
                    favoritesOnly.toggle()
                }
                ForEach(allCourses, id: \.self) { candidate in
                    FilterChip(title: candidate.frenchLabel, systemImage: candidate.symbolName,
                               isOn: course == candidate) {
                        course = course == candidate ? nil : candidate
                    }
                }
                ForEach(allTags, id: \.self) { candidate in
                    FilterChip(title: candidate, systemImage: "tag", isOn: tag == candidate) {
                        tag = tag == candidate ? nil : candidate
                    }
                }
                if hasFilter {
                    Button("Tout afficher") {
                        favoritesOnly = false; course = nil; tag = nil
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Classement", selection: $sort) {
                    ForEach(SortOrder.allCases) { order in
                        Label(order.frenchLabel, systemImage: order.symbolName).tag(order)
                    }
                }
            } label: {
                Label("Classement", systemImage: "arrow.up.arrow.down")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { RecipeAskView() } label: {
                Label("Nouvelle recette", systemImage: "plus")
            }
        }
        // Reordering by hand only makes sense while the hand-made order is the
        // one on screen, so the button appears with that sort and not otherwise.
        if sort == .manual, !recipes.isEmpty {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
    }
}

/// One row of the bank.
private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(recipe: recipe)
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(recipe.title)
                        .font(Theme.display(16, weight: .semibold))
                        .lineLimit(1)
                    if recipe.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2).foregroundStyle(Theme.treasure)
                    }
                }
                if let summary = recipe.summaryFR {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    if recipe.totalMinutes > 0 {
                        RecipeFact(systemImage: "clock", text: Formatting.duration(minutes: recipe.totalMinutes))
                    }
                    RecipeFact(systemImage: "person.2", text: "\(recipe.servings)")
                    if recipe.hasNotes {
                        Image(systemName: "note.text").font(.caption2).foregroundStyle(Theme.cuisine)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

/// A toggleable filter pill.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title).lineLimit(1)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isOn ? Theme.cuisine.opacity(0.18) : Color.primary.opacity(0.07), in: Capsule())
            .foregroundStyle(isOn ? Theme.cuisine : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
    }
}
