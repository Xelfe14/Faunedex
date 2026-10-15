import SwiftUI
import SwiftData
import FlaunedexCore

/// One knowledge card: the picture, the explanation, what to remember, the
/// review question, and the learner's notes.
struct KnowledgeCardView: View {
    @Bindable var card: KnowledgeCard

    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showsAnswer = false
    @State private var noteDraft = ""
    @State private var editing = false
    @State private var askingChange = false
    @State private var confirmingDelete = false
    @State private var confirmingReset = false

    var body: some View {
        List {
            heroSection
            headerSection
            if !card.bodyFR.isEmpty { bodySection }
            if !card.keyPoints.isEmpty { keyPointsSection }
            flashcardSection
            if let fact = card.funFactFR { funFactSection(fact) }
            notesSection
            reviewSection
            provenanceSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(card.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.savoirs)
        .toolbar { toolbar }
        .onAppear { noteDraft = card.notes ?? "" }
        .onDisappear(perform: commitNotes)
        .sheet(isPresented: $editing, onDismiss: { noteDraft = card.notes ?? "" }) {
            KnowledgeEditorView(card: card)
        }
        .sheet(isPresented: $askingChange) {
            KnowledgeVariationSheet(card: card)
        }
        .confirmationDialog("Supprimer cette fiche ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                store.delete(card)
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Vos notes et l'historique de révision seront perdus.")
        }
        .confirmationDialog("Recommencer l'apprentissage de cette fiche ?", isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button("Recommencer", role: .destructive) { store.resetReview(of: card) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Elle redevient nouvelle et repasse dans les révisions dès aujourd'hui.")
        }
    }

    // MARK: Sections

    @ViewBuilder private var heroSection: some View {
        if card.imageURLString != nil || card.localImagePath != nil {
            Section {
                KnowledgeImage(card: card)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(card.title.isEmpty ? "Sans titre" : card.title)
                    .font(Theme.display(24))
                HStack(spacing: 6) {
                    Chip(text: card.theme.frenchLabel, systemImage: card.theme.symbolName, tint: Theme.savoirs)
                    Chip(text: card.source.frenchLabel, systemImage: card.source.symbolName, tint: .secondary)
                }
                if let summary = card.summaryFR {
                    Text(summary)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                }
                if !card.tags.isEmpty {
                    Text(card.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var bodySection: some View {
        Section("L'essentiel") {
            ForEach(Array(card.bodyFR.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var keyPointsSection: some View {
        Section("À retenir") {
            ForEach(Array(card.keyPoints.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.savoirs)
                    Text(point)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var flashcardSection: some View {
        Section {
            Text(card.reviewQuestion)
                .font(.subheadline.weight(.semibold))
            if showsAnswer {
                Text(card.reviewAnswer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                Button {
                    withAnimation { showsAnswer = true }
                } label: {
                    Label("Afficher la réponse", systemImage: "eye")
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Question de révision")
        }
    }

    private func funFactSection(_ fact: String) -> some View {
        Section {
            Label {
                Text(fact).font(.subheadline)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Theme.treasure)
            }
        } header: {
            Text("Le saviez-vous ?")
        }
    }

    private var notesSection: some View {
        Section {
            TextField("Ce que vous voulez ajouter, vos exemples, vos liens…", text: $noteDraft, axis: .vertical)
                .lineLimit(2...8)
                .font(.subheadline)
                .onSubmit(commitNotes)
        } header: {
            Text("Mes notes")
        }
    }

    private var reviewSection: some View {
        Section {
            HStack {
                ReviewStatusLabel(card: card)
                Spacer()
                ReviewBoxMeter(box: card.reviewBox)
            }
            if card.reviewCount > 0 {
                Text("Révisée \(card.reviewCount) fois\(card.lapseCount > 0 ? ", oubliée \(card.lapseCount) fois" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Recommencer l'apprentissage") { confirmingReset = true }
                    .font(.subheadline)
            }
        } header: {
            Text("Révision")
        }
    }

    private var provenanceSection: some View {
        Section {
            if let prompt = card.originalPrompt, card.source != .manual {
                LabeledContent("Demandé", value: prompt)
                    .font(.caption)
            }
            if let url = card.articleURL {
                Link(destination: url) {
                    Label("En savoir plus sur Wikipédia", systemImage: "book")
                        .font(.subheadline)
                }
            }
            if card.imageURLString != nil {
                AttributionLabel(prefix: "Image", artist: card.imageArtist,
                                 licenseShort: card.imageLicenseShort,
                                 licenseURLString: card.imageLicenseURL,
                                 sourcePageURLString: card.imageSourcePageURL)
            }
        } header: {
            Text("Source")
        } footer: {
            if card.source != .manual {
                Text("Les fiches écrites par un modèle peuvent contenir des erreurs. Vérifiez ce qui compte avant de l'apprendre par cœur.")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                store.toggleFavorite(card)
            } label: {
                Image(systemName: card.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(card.isFavorite ? Theme.treasure : Theme.savoirs)
            }
            .accessibilityLabel(card.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    commitNotes()
                    editing = true
                } label: {
                    Label("Modifier la fiche", systemImage: "square.and.pencil")
                }
                Button {
                    askingChange = true
                } label: {
                    Label("Demander une modification", systemImage: "sparkles")
                }
                .disabled(!store.hasGeminiKey)
                Button {
                    Task { await store.refreshPicture(for: card) }
                } label: {
                    Label("Chercher une image", systemImage: "photo")
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
    }

    private func commitNotes() {
        guard noteDraft != (card.notes ?? "") else { return }
        store.setNotes(noteDraft, on: card)
    }
}

/// Ask the model to change a card that already exists.
struct KnowledgeVariationSheet: View {
    let card: KnowledgeCard

    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var change = ""
    @State private var errorMessage: String?

    private let ideas = ["plus simple", "plus détaillée", "ajoute les dates clés",
                         "avec un exemple de la vie courante", "une autre question de révision"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ce que vous voulez changer", text: $change, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Votre demande")
                } footer: {
                    Text("La fiche actuelle est envoyée à Gemini, qui l'adapte plutôt que d'en écrire une autre. Vos notes et vos révisions ne sont pas touchées.")
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
            .navigationTitle("Modifier avec Gemini")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.savoirs)
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
                try await store.revise(card, change: change.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? KnowledgeStore.frenchMessage(for: error)
            }
        }
    }
}
