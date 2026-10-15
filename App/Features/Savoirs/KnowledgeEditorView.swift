import SwiftUI
import FlaunedexCore

/// Write a card from scratch, or rewrite one, field by field.
///
/// Whatever the model wrote, what is stored after saving is what the learner
/// typed, and a card that came from Gemini is marked as edited.
struct KnowledgeEditorView: View {
    /// Nil to write a new card.
    let card: KnowledgeCard?

    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var theme: KnowledgeTheme = .divers
    @State private var summary = ""
    @State private var bodyText = ""
    @State private var keyPoints = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var funFact = ""
    @State private var tags = ""
    @State private var notes = ""
    @State private var loaded = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title)
                        .font(.headline)
                    Picker("Rubrique", selection: $theme) {
                        ForEach(KnowledgeTheme.allCases, id: \.self) { theme in
                            Label(theme.frenchLabel, systemImage: theme.symbolName).tag(theme)
                        }
                    }
                    TextField("La phrase à retenir", text: $summary, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    TextField("L'explication", text: $bodyText, axis: .vertical)
                        .lineLimit(4...20)
                } header: {
                    Text("L'essentiel")
                } footer: {
                    Text("Laissez une ligne vide entre deux paragraphes.")
                }

                Section {
                    TextField("Un point par ligne", text: $keyPoints, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("À retenir")
                }

                Section {
                    TextField("Question", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Réponse", text: $answer, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Question de révision")
                } footer: {
                    Text("C'est le recto et le verso de la fiche dans Réviser. Sans question, la fiche se révise sur son titre.")
                }

                Section("Le saviez-vous ?") {
                    TextField("Une anecdote (facultatif)", text: $funFact, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    TextField("Mots-clés, séparés par des virgules", text: $tags)
                        .textInputAutocapitalization(.never)
                    TextField("Mes notes", text: $notes, axis: .vertical)
                        .lineLimit(2...8)
                }
            }
            .navigationTitle(card == nil ? "Nouvelle fiche" : "Modifier la fiche")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.savoirs)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let card else { return }
        title = card.title
        theme = card.theme
        summary = card.summaryFR ?? ""
        bodyText = card.bodyFR
        keyPoints = card.keyPoints.joined(separator: "\n")
        question = card.question ?? ""
        answer = card.answer ?? ""
        funFact = card.funFactFR ?? ""
        tags = card.tags.joined(separator: ", ")
        notes = card.notes ?? ""
    }

    private func save() {
        let draft = KnowledgeDraft(
            title: title,
            theme: theme,
            summaryFR: summary,
            bodyFR: bodyText,
            keyPointsFR: KnowledgeDraft.keyPoints(fromLines: keyPoints),
            questionFR: question,
            answerFR: answer,
            funFactFR: funFact,
            wikipediaQuery: card?.wikipediaQuery,
            tags: tags.components(separatedBy: ",")
        )
        if let card {
            store.applyEdit(draft, notes: notes, to: card)
        } else {
            let created = store.create(draft, notes: notes)
            // A card written by hand gets a picture too, if Wikipedia has one.
            Task { await store.attachPicture(to: created, query: created.title) }
        }
        dismiss()
    }
}
