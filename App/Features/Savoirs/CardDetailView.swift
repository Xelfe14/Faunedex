import SwiftUI
import SwiftData
import FlaunedexCore

/// One card on its own: turn it over, see where it stands, and manage it.
struct CardDetailView: View {
    let card: KnowledgeCard

    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var allFolders: [KnowledgeFolder]

    @State private var flipped = false
    @State private var editing = false
    @State private var confirmingDelete = false

    private let french = Locale(identifier: "fr_FR")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlipCard(flipped: flipped) {
                    KnowledgeCardFace(card: card, side: .recto, folder: card.folder) { flipped.toggle() }
                } back: {
                    KnowledgeCardFace(card: card, side: .verso, folder: card.folder) { flipped.toggle() }
                }
                .frame(height: 390)

                Label("Touchez la carte pour la retourner", systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                facts
                actions
            }
            .padding()
        }
        .canvasBackground()
        .navigationTitle(card.previewText(for: .recto).isEmpty ? "Carte" : card.previewText(for: .recto))
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.knowledge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            CardEditorView(card: card, folder: card.folder, store: store)
        }
        .confirmationDialog("Supprimer cette carte ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) {
                store.delete(card)
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Pour seulement la sortir des révisions, utilisez plutôt « Retirer ».")
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            fact("Dossier", KnowledgeIndex.pathLabel(of: card.folder, folders: allFolders), "folder")
            fact("État", stateText, stateSymbol)
            if card.masteryLevel > 0 {
                fact("Maîtrisée", "\(card.masteryLevel) fois de suite", "checkmark.seal")
            }
            fact("Tirée", card.timesDealt == 0 ? "jamais encore" : "\(card.timesDealt) fois", "rectangle.stack")
            if let last = card.lastDealtAt {
                fact("Dernière révision", last.formatted(.dateTime.day().month(.wide).year().locale(french)), "clock")
            }
            fact("Créée le", card.createdAt.formatted(.dateTime.day().month(.wide).year().locale(french)), "calendar")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Theme.tileRadius)
    }

    private var stateText: String {
        if let retired = card.retiredAt {
            return "Retirée depuis le \(retired.formatted(.dateTime.day().month(.wide).locale(french)))"
        }
        if card.isResting(), let until = card.restUntil {
            return "Au repos jusqu'au \(KnowledgeIndex.returnDate(until))"
        }
        if card.masteryLevel > 0 {
            return "De retour : à confirmer"
        }
        return "En jeu"
    }

    private var stateSymbol: String {
        if card.isRetired { return "archivebox" }
        if card.isResting() { return "moon.zzz" }
        return "rectangle.stack"
    }

    private func fact(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.knowledge).frame(width: 20)
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if card.isRetired {
                actionButton("Remettre en jeu", "arrow.uturn.backward", .green) { store.restore(card) }
            } else {
                actionButton("Retirer des révisions", "archivebox", .gray) { store.retire(card) }
            }
            if card.masteryLevel > 0 || card.restUntil != nil {
                actionButton("Oublier la maîtrise", "arrow.counterclockwise", Theme.treasure) { store.resetMastery(card) }
            }
            actionButton("Supprimer la carte", "trash", .red) { confirmingDelete = true }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
