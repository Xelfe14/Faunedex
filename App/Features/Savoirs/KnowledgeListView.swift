import SwiftUI
import SwiftData
import FlaunedexCore

/// The collection of knowledge cards, shelved by the learner's categories.
struct KnowledgeListView: View {
    @Query(sort: \KnowledgeCard.createdAt, order: .reverse) private var cards: [KnowledgeCard]
    @Query private var categories: [KnowledgeCategory]
    @Environment(KnowledgeStore.self) private var store

    @State private var search = ""
    @State private var categoryKey: String?
    @State private var favoritesOnly = false
    @State private var writing = false
    @State private var managingCategories = false
    @State private var pendingDeletion: KnowledgeCard?

    private var index: CategoryIndex { CategoryIndex(categories) }

    private var filtered: [KnowledgeCard] {
        let index = self.index
        return cards.filter { card in
            (!favoritesOnly || card.isFavorite)
            && (categoryKey == nil || index.shelfKey(for: card.categoryKey) == categoryKey)
            && (search.isEmpty || matches(card, search))
        }
    }

    /// Search covers everything written on the card, the learner's notes
    /// included.
    private func matches(_ card: KnowledgeCard, _ query: String) -> Bool {
        [card.title, card.summaryFR, card.bodyFR, card.notes, card.question, card.answer]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
        || card.keyPoints.contains { $0.localizedCaseInsensitiveContains(query) }
        || card.tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private var shelves: [(category: KnowledgeCategory, cards: [KnowledgeCard])] {
        let index = self.index
        let current = filtered
        return index.ordered.compactMap { category in
            let onShelf = current.filter { index.shelfKey(for: $0.categoryKey) == category.key }
            return onShelf.isEmpty ? nil : (category: category, cards: onShelf)
        }
    }

    private var usedCategories: [KnowledgeCategory] {
        let index = self.index
        let used = Set(cards.map { index.shelfKey(for: $0.categoryKey) })
        return index.ordered.filter { used.contains($0.key) }
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                EmptyStateView(
                    title: "Aucune fiche",
                    message: "Demandez une fiche sur n'importe quel sujet, ou écrivez la vôtre. Elles s'ajouteront ici.",
                    systemImage: "lightbulb"
                )
                .canvasBackground()
            } else {
                list
            }
        }
        .navigationTitle("Fiches")
        .searchable(text: $search, prompt: "Rechercher dans vos fiches")
        .toolbar { toolbar }
        .tint(Theme.savoirs)
        .sheet(isPresented: $writing) {
            KnowledgeEditorView(card: nil, defaultCategoryKey: categoryKey)
        }
        .sheet(isPresented: $managingCategories) {
            KnowledgeCategoriesView()
        }
        .confirmationDialog(
            "Supprimer « \(pendingDeletion?.title ?? "") » ?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let card = pendingDeletion { store.delete(card) }
                pendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Vos notes et l'historique de révision de cette fiche seront perdus.")
        }
    }

    private var list: some View {
        List {
            if shelves.isEmpty {
                ContentUnavailableView("Rien ne correspond", systemImage: "magnifyingglass",
                                       description: Text("Changez de recherche ou de filtre."))
            }
            ForEach(shelves, id: \.category.key) { shelf in
                Section {
                    ForEach(shelf.cards) { card in
                        NavigationLink {
                            KnowledgeCardView(card: card)
                        } label: {
                            KnowledgeRow(card: card, symbol: shelf.category.symbolName)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = card
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.toggleFavorite(card)
                            } label: {
                                Label("Favori", systemImage: card.isFavorite ? "star.slash" : "star")
                            }
                            .tint(Theme.treasure)
                        }
                    }
                } header: {
                    Label(shelf.category.name, systemImage: shelf.category.symbolName)
                }
            }
            Section {
                Button {
                    managingCategories = true
                } label: {
                    Label("Gérer les rubriques", systemImage: "folder.badge.gearshape")
                }
            } footer: {
                Text("Créez vos propres rubriques, renommez-les, changez leur icône ou leur ordre.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: $favoritesOnly) {
                    Label("Favoris seulement", systemImage: "star")
                }
                Picker("Rubrique", selection: $categoryKey) {
                    Text("Toutes les rubriques").tag(String?.none)
                    ForEach(usedCategories) { category in
                        Label(category.name, systemImage: category.symbolName)
                            .tag(String?.some(category.key))
                    }
                }
                Divider()
                Button {
                    managingCategories = true
                } label: {
                    Label("Gérer les rubriques", systemImage: "folder.badge.gearshape")
                }
            } label: {
                Image(systemName: favoritesOnly || categoryKey != nil
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filtrer")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                writing = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("Écrire une fiche")
        }
    }
}
