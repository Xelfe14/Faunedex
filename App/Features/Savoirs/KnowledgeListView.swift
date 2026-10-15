import SwiftUI
import SwiftData
import FlaunedexCore

/// The collection of knowledge cards, shelved by theme.
struct KnowledgeListView: View {
    @Query(sort: \KnowledgeCard.createdAt, order: .reverse) private var cards: [KnowledgeCard]
    @Environment(KnowledgeStore.self) private var store

    @State private var search = ""
    @State private var theme: KnowledgeTheme?
    @State private var favoritesOnly = false
    @State private var writing = false
    @State private var pendingDeletion: KnowledgeCard?

    private var filtered: [KnowledgeCard] {
        cards.filter { card in
            (!favoritesOnly || card.isFavorite)
            && (theme == nil || card.theme == theme)
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

    private var shelves: [(theme: KnowledgeTheme, cards: [KnowledgeCard])] {
        let current = filtered
        return KnowledgeTheme.allCases.compactMap { theme in
            let onShelf = current.filter { $0.theme == theme }
            return onShelf.isEmpty ? nil : (theme: theme, cards: onShelf)
        }
    }

    private var usedThemes: [KnowledgeTheme] {
        KnowledgeTheme.allCases.filter { theme in cards.contains { $0.theme == theme } }
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
            KnowledgeEditorView(card: nil)
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
            ForEach(shelves, id: \.theme) { shelf in
                Section {
                    ForEach(shelf.cards) { card in
                        NavigationLink {
                            KnowledgeCardView(card: card)
                        } label: {
                            KnowledgeRow(card: card)
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
                    Label(shelf.theme.frenchLabel, systemImage: shelf.theme.symbolName)
                }
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
                Picker("Rubrique", selection: $theme) {
                    Text("Toutes les rubriques").tag(KnowledgeTheme?.none)
                    ForEach(usedThemes, id: \.self) { theme in
                        Label(theme.frenchLabel, systemImage: theme.symbolName)
                            .tag(KnowledgeTheme?.some(theme))
                    }
                }
            } label: {
                Image(systemName: favoritesOnly || theme != nil
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
