import SwiftUI
import SwiftData
import FlaunedexCore

/// The learner's categories: rename one or change its icon with a tap, add one,
/// drag them into another order, or swipe one away (its cards go to Divers).
struct KnowledgeCategoriesView: View {
    @Query private var categories: [KnowledgeCategory]
    @Query private var cards: [KnowledgeCard]
    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editing: KnowledgeCategory?
    @State private var creating = false
    @State private var pendingDeletion: KnowledgeCategory?

    private var ordered: [KnowledgeCategory] { CategoryIndex(categories).ordered }

    private func count(_ category: KnowledgeCategory) -> Int {
        cards.filter { $0.categoryKey == category.key }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ordered) { category in
                        Button {
                            editing = category
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(symbol: category.symbolName)
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(count(category))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .deleteDisabled(category.key == KnowledgeStore.fallbackKey)
                    }
                    .onDelete { offsets in
                        pendingDeletion = offsets.first.map { ordered[$0] }
                    }
                    .onMove { from, to in
                        var list = ordered
                        list.move(fromOffsets: from, toOffset: to)
                        store.persistCategoryOrder(list)
                    }
                } footer: {
                    Text("Touchez une rubrique pour la renommer ou changer son icône. Balayez-la vers la gauche pour la supprimer : ses fiches passent dans Divers. Gemini range chaque nouvelle fiche dans l'une de vos rubriques.")
                }

                Section {
                    Button {
                        creating = true
                    } label: {
                        Label("Nouvelle rubrique", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Rubriques")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(item: $editing) { CategoryEditorView(category: $0) }
            .sheet(isPresented: $creating) { CategoryEditorView(category: nil) }
            .confirmationDialog(
                "Supprimer la rubrique « \(pendingDeletion?.name ?? "") » ?",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if let category = pendingDeletion { store.deleteCategory(category) }
                    pendingDeletion = nil
                }
                Button("Annuler", role: .cancel) { pendingDeletion = nil }
            } message: {
                let n = pendingDeletion.map(count) ?? 0
                Text(n == 0 ? "Elle ne contient aucune fiche."
                            : "Ses \(n) fiche\(n > 1 ? "s" : "") passeront dans Divers.")
            }
        }
        .tint(Theme.savoirs)
    }
}

/// Create a category, or rename one and change its icon.
struct CategoryEditorView: View {
    /// Nil to create a new one.
    let category: KnowledgeCategory?
    /// Called with the category just created, so the screen that asked for it
    /// can select it.
    var onCreate: (KnowledgeCategory) -> Void = { _ in }

    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = "lightbulb"
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    /// A choice wide enough for most subjects, small enough to scan at once.
    static let symbols = [
        "lightbulb", "atom", "building.columns", "leaf", "fork.knife", "character.bubble",
        "text.book.closed", "book", "paintpalette", "theatermasks", "music.note", "film",
        "globe.europe.africa", "mountain.2", "airplane", "person.3", "heart.text.square", "brain.head.profile",
        "function", "chart.line.uptrend.xyaxis", "banknote", "briefcase", "gearshape.2", "laptopcomputer",
        "hammer", "house", "pawprint", "sportscourt", "star", "flag",
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: symbol, size: 44, filled: true)
                        TextField("Nom de la rubrique", text: $name)
                            .font(.headline)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { if canSave { save() } }
                    }
                }

                Section("Icône") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                        ForEach(Self.symbols, id: \.self) { candidate in
                            Button {
                                symbol = candidate
                            } label: {
                                CategoryIcon(symbol: candidate, size: 40, filled: candidate == symbol)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(candidate == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(category == nil ? "Nouvelle rubrique" : "Modifier la rubrique")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.savoirs)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(category == nil ? "Créer" : "Enregistrer", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let category {
            name = category.name
            symbol = category.symbolName
        } else {
            nameFocused = true
        }
    }

    private func save() {
        if let category {
            store.updateCategory(category, name: name, symbolName: symbol)
        } else if let created = store.createCategory(name: name, symbolName: symbol) {
            onCreate(created)
        }
        dismiss()
    }
}

/// A category's icon on a rounded square, filled when it is the one chosen.
struct CategoryIcon: View {
    let symbol: String
    var size: CGFloat = 30
    var filled = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(filled ? Color.white : Theme.savoirs)
            .frame(width: size, height: size)
            .background(filled ? Theme.savoirs : Theme.savoirs.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// Pick a category, with "Nouvelle rubrique…" at hand, for the editor and for
/// Apprendre. `allowsAutomatic` adds a first choice that leaves it to Gemini.
struct CategoryPicker: View {
    @Binding var selection: String?
    var allowsAutomatic = false

    @Query private var categories: [KnowledgeCategory]
    @State private var creating = false

    var body: some View {
        let index = CategoryIndex(categories)
        Picker("Rubrique", selection: $selection) {
            if allowsAutomatic {
                Text("Choisie par Gemini").tag(String?.none)
            }
            ForEach(index.ordered) { category in
                Label(category.name, systemImage: category.symbolName)
                    .tag(String?.some(category.key))
            }
        }
        Button {
            creating = true
        } label: {
            Label("Nouvelle rubrique…", systemImage: "plus")
                .font(.subheadline)
        }
        .sheet(isPresented: $creating) {
            CategoryEditorView(category: nil) { created in
                selection = created.key
            }
        }
    }
}
