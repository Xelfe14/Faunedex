import SwiftUI
import FlaunedexCore

/// Ask for a card on any subject. The one Savoirs screen where the model is
/// visible, built like the recipe request screen.
struct KnowledgeAskView: View {
    @Environment(KnowledgeStore.self) private var store
    @Environment(APIKeys.self) private var keys

    @State private var subject: String
    @State private var depth: KnowledgeDepth = .essentiel
    @State private var focus = ""
    /// Nil leaves the choice to Gemini, among the learner's categories.
    @State private var categoryKey: String?
    @State private var created: KnowledgeCard?
    @State private var writing = false
    @State private var errorMessage: String?

    @FocusState private var subjectFocused: Bool

    /// Starting points, so the screen is never a blank box.
    private let ideas = [
        "sérendipité",
        "pourquoi le ciel est bleu",
        "la photosynthèse",
        "la bataille de Marignan",
        "les taux d'intérêt",
        "le subjonctif en français",
        "comment fonctionne un vaccin",
    ]

    /// `initialSubject` pre-fills the request.
    init(initialSubject: String = "") {
        _subject = State(initialValue: initialSubject)
    }

    private var canAsk: Bool {
        keys.hasGeminiKey && !subject.trimmingCharacters(in: .whitespaces).isEmpty && !store.isWorking
    }

    var body: some View {
        Form {
            if !keys.hasGeminiKey {
                Section {
                    Label("Ajoutez votre clé Gemini dans Réglages (la roue dentée en haut à droite) pour créer une fiche.",
                          systemImage: "key.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                TextField("Ce que vous voulez comprendre", text: $subject, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($subjectFocused)
            } header: {
                Text("Le sujet")
            } footer: {
                Text("Un mot, une notion, une question : tout ce qui mérite une fiche.")
            }

            if subject.isEmpty {
                Section("Quelques idées") {
                    ForEach(ideas, id: \.self) { idea in
                        Button {
                            subject = idea
                            subjectFocused = true
                        } label: {
                            Label(idea, systemImage: "lightbulb")
                                .font(.subheadline)
                        }
                    }
                }
            }

            Section {
                Picker("Niveau", selection: $depth) {
                    ForEach(KnowledgeDepth.allCases, id: \.self) { depth in
                        Text(depth.frenchLabel).tag(depth)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Un angle particulier (facultatif)", text: $focus, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("La fiche")
            } footer: {
                Text((depth == .essentiel
                      ? "Deux paragraphes courts, les points à retenir et une question de révision."
                      : "Quatre ou cinq paragraphes avec les nuances, les points à retenir et une question de révision.")
                     + " Pour un mot, sa définition et toujours son étymologie.")
            }

            Section {
                CategoryPicker(selection: $categoryKey, allowsAutomatic: true)
            } footer: {
                Text(categoryKey == nil
                     ? "Gemini range la fiche dans celle de vos rubriques qui convient le mieux."
                     : "La fiche sera rangée dans cette rubrique.")
            }

            Section {
                Button(action: ask) {
                    HStack {
                        if store.isWorking {
                            ProgressView().tint(Theme.savoirs)
                            Text("Rédaction de la fiche…")
                        } else {
                            Label("Créer la fiche", systemImage: "sparkles")
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
                    writing = true
                } label: {
                    Label("Écrire une fiche moi-même", systemImage: "square.and.pencil")
                }
            } footer: {
                Text("Une fiche vide, à remplir vous-même.")
            }
        }
        .navigationTitle("Apprendre")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.savoirs)
        .navigationDestination(item: $created) { card in
            KnowledgeCardView(card: card)
        }
        .sheet(isPresented: $writing) {
            KnowledgeEditorView(card: nil)
        }
    }

    private func ask() {
        errorMessage = nil
        let request = KnowledgeRequest(
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            depth: depth,
            focus: focus
        )
        Task {
            do {
                created = try await store.generate(request: request, categoryKey: categoryKey)
                subject = ""
                focus = ""
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? KnowledgeStore.frenchMessage(for: error)
            }
        }
    }
}
