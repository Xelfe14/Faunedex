import SwiftUI
import SwiftData
import FlaunedexCore

/// A folder's content: its sub-folders, then its cards. With no folder, the top
/// level of the whole collection.
struct FolderContentView: View {
    let folder: KnowledgeFolder?

    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var allFolders: [KnowledgeFolder]
    @Query(sort: \KnowledgeCard.createdAt, order: .reverse) private var allCards: [KnowledgeCard]

    @State private var search = ""
    @State private var cardSheet: CardSheet?
    @State private var folderSheet: FolderSheet?
    @State private var folderToDelete: KnowledgeFolder?
    @State private var cardToDelete: KnowledgeCard?
    @State private var revising = false

    struct CardSheet: Identifiable {
        let id = UUID()
        let folder: KnowledgeFolder?
    }

    struct FolderSheet: Identifiable {
        let id = UUID()
        let folder: KnowledgeFolder?
        let parent: KnowledgeFolder?
    }

    private var subfolders: [KnowledgeFolder] {
        allFolders.filter { $0.parent?.id == folder?.id }.sorted(by: KnowledgeFolder.displayOrder)
    }

    private var directCards: [KnowledgeCard] {
        guard let folder else { return [] }
        return allCards.filter { $0.folder?.id == folder.id }
    }

    var body: some View {
        Group {
            if folder == nil && allFolders.isEmpty {
                firstFolderInvitation
            } else {
                list
            }
        }
        .navigationTitle(folder?.name ?? "Savoirs")
        .toolbar { toolbar }
        .sheet(item: $cardSheet) { sheet in
            CardEditorView(card: nil, folder: sheet.folder, store: store)
        }
        .sheet(item: $folderSheet) { sheet in
            FolderEditorSheet(folder: sheet.folder, parent: sheet.parent)
        }
        .sheet(isPresented: $revising) {
            NavigationStack {
                ReviewSetupView(initialScope: folder.map { .folder($0.id) } ?? .all)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer") { revising = false }
                        }
                    }
            }
        }
        .confirmationDialog(deleteFolderTitle, isPresented: Binding(
            get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                guard let target = folderToDelete else { return }
                let wasCurrent = target.id == folder?.id
                store.delete(target)
                folderToDelete = nil
                if wasCurrent { dismiss() }
            }
            Button("Annuler", role: .cancel) { folderToDelete = nil }
        } message: {
            Text(deleteFolderMessage)
        }
        .confirmationDialog("Supprimer cette carte ?", isPresented: Binding(
            get: { cardToDelete != nil }, set: { if !$0 { cardToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) {
                if let card = cardToDelete { store.delete(card) }
                cardToDelete = nil
            }
            Button("Annuler", role: .cancel) { cardToDelete = nil }
        } message: {
            Text("Pour seulement la sortir des révisions, balayez vers la droite et touchez « Retirer ».")
        }
    }

    // MARK: The list

    private var list: some View {
        let counts = KnowledgeIndex.subtreeCounts(cards: allCards, folders: allFolders)
        let scope = KnowledgeIndex.cards(in: folder, cards: allCards, folders: allFolders)
        return List {
            if search.isEmpty {
                header(scope: scope)
                if !subfolders.isEmpty {
                    Section(folder == nil ? "Dossiers" : "Sous-dossiers") {
                        ForEach(subfolders) { sub in
                            NavigationLink {
                                FolderContentView(folder: sub)
                            } label: {
                                FolderRow(folder: sub, count: counts[sub.id] ?? 0,
                                          subfolderCount: allFolders.filter { $0.parent?.id == sub.id }.count)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { folderToDelete = sub } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                                Button { folderSheet = FolderSheet(folder: sub, parent: nil) } label: {
                                    Label("Modifier", systemImage: "pencil")
                                }
                                .tint(Theme.knowledge)
                            }
                        }
                    }
                }
                if let folder { cardsSection(folder) }
            } else {
                searchResults(in: scope)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: folder == nil ? "Rechercher dans toutes les cartes" : "Rechercher dans ce dossier")
    }

    @ViewBuilder private func header(scope: [KnowledgeCard]) -> some View {
        let status = KnowledgeIndex.status(of: scope)
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    if let folder {
                        FolderBadge(emoji: folder.emoji, color: folder.color, size: 56)
                    } else {
                        FolderBadge(emoji: "🧠", color: .indigo, size: 56)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(folder?.name ?? "Toutes vos cartes")
                            .font(Theme.display(21))
                        Text(scope.count == 0 ? "Aucune carte" : "\(scope.count) carte\(scope.count > 1 ? "s" : "")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if status.total > 0 { DeckStatusPills(status: status) }
                Button { revising = true } label: {
                    Label(folder == nil ? "Tout réviser" : "Réviser ce dossier", systemImage: "rectangle.stack.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.knowledge, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(scope.isEmpty)
                .opacity(scope.isEmpty ? 0.45 : 1)
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private func cardsSection(_ folder: KnowledgeFolder) -> some View {
        Section {
            ForEach(directCards) { card in
                NavigationLink {
                    CardDetailView(card: card)
                } label: {
                    KnowledgeCardRow(card: card)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        if card.isRetired { store.restore(card) } else { store.retire(card) }
                    } label: {
                        Label(card.isRetired ? "Remettre" : "Retirer",
                              systemImage: card.isRetired ? "arrow.uturn.backward" : "archivebox")
                    }
                    .tint(card.isRetired ? .green : .gray)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { cardToDelete = card } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
            Button {
                cardSheet = CardSheet(folder: folder)
            } label: {
                Label("Nouvelle carte", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.knowledge)
            }
        } header: {
            Text(directCards.isEmpty ? "Cartes" : "Cartes (\(directCards.count))")
        } footer: {
            if directCards.isEmpty && subfolders.isEmpty {
                Text("Ce dossier est vide. Ajoutez une carte, ou un sous-dossier avec le bouton en haut à droite.")
            }
        }
    }

    @ViewBuilder private func searchResults(in scope: [KnowledgeCard]) -> some View {
        let matches = scope.filter {
            $0.rectoText.localizedStandardContains(search) || $0.versoText.localizedStandardContains(search)
        }
        Section {
            if matches.isEmpty {
                Text("Aucune carte ne contient « \(search) ».").foregroundStyle(.secondary)
            }
            ForEach(matches) { card in
                NavigationLink {
                    CardDetailView(card: card)
                } label: {
                    KnowledgeCardRow(card: card, folderPath: KnowledgeIndex.pathLabel(of: card.folder, folders: allFolders))
                }
            }
        } header: {
            Text("\(matches.count) résultat\(matches.count > 1 ? "s" : "")")
        }
    }

    private var firstFolderInvitation: some View {
        VStack(spacing: 18) {
            EmptyStateView(
                title: "Vos savoirs commencent ici",
                message: "Créez un dossier (Langues, Citations, Dates…), puis remplissez-le de cartes recto verso.",
                systemImage: "brain.head.profile",
                tint: Theme.knowledge
            )
            .frame(height: 320)
            Button {
                folderSheet = FolderSheet(folder: nil, parent: nil)
            } label: {
                Label("Créer un dossier", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Theme.knowledge, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .canvasBackground()
    }

    // MARK: Toolbar and dialogs

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let folder {
                    Button { cardSheet = CardSheet(folder: folder) } label: {
                        Label("Nouvelle carte", systemImage: "rectangle.badge.plus")
                    }
                }
                Button { folderSheet = FolderSheet(folder: nil, parent: folder) } label: {
                    Label(folder == nil ? "Nouveau dossier" : "Nouveau sous-dossier", systemImage: "folder.badge.plus")
                }
                if let folder {
                    Divider()
                    Button { folderSheet = FolderSheet(folder: folder, parent: nil) } label: {
                        Label("Modifier le dossier", systemImage: "pencil")
                    }
                    Button(role: .destructive) { folderToDelete = folder } label: {
                        Label("Supprimer le dossier", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.knowledge)
            }
            .accessibilityLabel("Ajouter")
        }
    }

    private var deleteFolderTitle: String {
        "Supprimer « \(folderToDelete?.name ?? "") » ?"
    }

    private var deleteFolderMessage: String {
        guard let target = folderToDelete else { return "" }
        let cards = KnowledgeIndex.cards(in: target, cards: allCards, folders: allFolders).count
        let subs = FolderTree.subtree(of: target.id, in: KnowledgeIndex.nodes(allFolders)).count - 1
        var parts: [String] = []
        if cards > 0 { parts.append("\(cards) carte\(cards > 1 ? "s" : "")") }
        if subs > 0 { parts.append("\(subs) sous-dossier\(subs > 1 ? "s" : "")") }
        return parts.isEmpty
            ? "Le dossier est vide."
            : "Tout son contenu sera supprimé : \(parts.joined(separator: " et ")). C'est définitif."
    }
}

/// One folder in a list.
struct FolderRow: View {
    let folder: KnowledgeFolder
    let count: Int
    var subfolderCount = 0

    var body: some View {
        HStack(spacing: 12) {
            FolderBadge(emoji: folder.emoji, color: folder.color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = ["\(count) carte\(count > 1 ? "s" : "")"]
        if subfolderCount > 0 { parts.append("\(subfolderCount) sous-dossier\(subfolderCount > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }
}
