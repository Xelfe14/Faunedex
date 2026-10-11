import SwiftUI
import SwiftData
import FlaunedexCore

/// Pick a folder from the whole tree, drawn as an indented outline.
struct FolderPickerView: View {
    enum Purpose {
        /// Choosing what a revision session covers: "Tous les dossiers" is allowed.
        case revisionScope
        /// Choosing where a card lives: a folder is required.
        case cardFolder
        /// Choosing a folder's parent: the top level is allowed, and the folder
        /// itself and everything below it are refused (it cannot go inside itself).
        case parent(of: UUID?)
    }

    let purpose: Purpose
    @Binding var selection: KnowledgeFolder?

    @Environment(\.dismiss) private var dismiss
    @Query private var folders: [KnowledgeFolder]
    @Query private var cards: [KnowledgeCard]

    private var excluded: Set<UUID> {
        guard case .parent(let moving?) = purpose else { return [] }
        return FolderTree.subtree(of: moving, in: KnowledgeIndex.nodes(folders))
    }

    var body: some View {
        let counts = KnowledgeIndex.subtreeCounts(cards: cards, folders: folders)
        List {
            switch purpose {
            case .revisionScope:
                row(nil, name: "Tous les dossiers", emoji: "🗂️", color: .indigo, depth: 0, count: cards.count)
            case .parent:
                row(nil, name: "Premier niveau", emoji: "🏠", color: .slate, depth: 0, count: nil)
            case .cardFolder:
                EmptyView()
            }
            ForEach(KnowledgeIndex.outline(folders), id: \.folder.id) { entry in
                row(entry.folder, name: entry.folder.name, emoji: entry.folder.emoji, color: entry.folder.color,
                    depth: entry.depth, count: counts[entry.folder.id] ?? 0)
                    .disabled(excluded.contains(entry.folder.id))
            }
            if folders.isEmpty {
                Text("Aucun dossier pour l'instant.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch purpose {
        case .revisionScope: return "Réviser quoi ?"
        case .cardFolder: return "Ranger dans"
        case .parent: return "Placer dans"
        }
    }

    private func row(_ folder: KnowledgeFolder?, name: String, emoji: String, color: FolderColor,
                     depth: Int, count: Int?) -> some View {
        let chosen = selection?.id == folder?.id
        return Button {
            selection = folder
            dismiss()
        } label: {
            HStack(spacing: 10) {
                FolderBadge(emoji: emoji, color: color, size: 30)
                Text(name).foregroundStyle(.primary).lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if chosen {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.knowledge)
                }
            }
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Create or edit a folder: its name, emoji, colour and place in the tree.
struct FolderEditorSheet: View {
    let folder: KnowledgeFolder?

    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var emoji: String
    @State private var color: FolderColor
    @State private var parent: KnowledgeFolder?
    @State private var moveRefused = false
    @FocusState private var nameFocused: Bool

    static let emojis = [
        "📚", "🧠", "💡", "🗣️", "🇬🇧", "🇮🇹", "🇪🇸", "🇩🇪", "🇫🇷", "📜",
        "✍️", "🕰️", "📅", "🏛️", "🌍", "🗺️", "🚩", "🧪", "🧬", "🔢",
        "📐", "🎨", "🎵", "🎬", "⚖️", "🌿", "🐾", "⭐️", "🍷", "⚽️",
    ]

    init(folder: KnowledgeFolder?, parent: KnowledgeFolder?) {
        self.folder = folder
        _name = State(initialValue: folder?.name ?? "")
        _emoji = State(initialValue: folder?.emoji ?? "📚")
        _color = State(initialValue: folder?.color ?? .indigo)
        _parent = State(initialValue: folder == nil ? parent : folder?.parent)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        FolderBadge(emoji: emoji, color: color, size: 54)
                        TextField("Nom du dossier", text: $name)
                            .font(.title3.weight(.semibold))
                            .focused($nameFocused)
                            .submitLabel(.done)
                    }
                    .padding(.vertical, 4)
                }

                Section("Icône") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                        ForEach(Self.emojis, id: \.self) { candidate in
                            Button { emoji = candidate } label: {
                                Text(candidate)
                                    .font(.system(size: 26))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(candidate == emoji ? Theme.folder(color).opacity(0.22) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Couleur") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(FolderColor.allCases) { candidate in
                            Button { color = candidate } label: {
                                Circle()
                                    .fill(Theme.folder(candidate))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if candidate == color {
                                            Circle().strokeBorder(.white, lineWidth: 3).padding(3)
                                            Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    NavigationLink {
                        FolderPickerView(purpose: .parent(of: folder?.id), selection: $parent)
                    } label: {
                        LabeledContent("Dans", value: parent?.name ?? "Premier niveau")
                    }
                } header: {
                    Text("Emplacement")
                } footer: {
                    Text("Un dossier peut contenir des cartes et d'autres dossiers, sans limite de profondeur.")
                }
            }
            .navigationTitle(folder == nil ? "Nouveau dossier" : "Modifier le dossier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Déplacement impossible", isPresented: $moveRefused) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Un dossier ne peut pas être rangé dans lui-même ni dans l'un de ses sous-dossiers.")
            }
            .onAppear { if folder == nil { nameFocused = true } }
        }
        // On the stack itself, so the bar's buttons get it too.
        .tint(Theme.knowledge)
    }

    private func save() {
        if let folder {
            store.update(folder, name: name, emoji: emoji, color: color)
            if folder.parent?.id != parent?.id, !store.move(folder, to: parent) {
                moveRefused = true
                return
            }
        } else {
            store.createFolder(name: name, emoji: emoji, color: color, parent: parent)
        }
        dismiss()
    }
}
