import SwiftUI
import UIKit
import FlaunedexCore

/// The dish photograph, preferring the copy cached on disk so a recipe still
/// shows its picture in a kitchen with no signal, and falling back to the
/// network only when there is no local copy yet.
struct RecipeImage: View {
    let recipe: Recipe
    var symbol: String = "fork.knife"

    @Environment(RecipeStore.self) private var store
    @State private var local: UIImage?

    var body: some View {
        Group {
            if let local {
                Image(uiImage: local).resizable().aspectRatio(contentMode: .fill)
            } else {
                RemoteImage(urlString: recipe.thumbURLString ?? recipe.imageURLString,
                            symbol: symbol, tint: Theme.cuisine)
            }
        }
        .task(id: recipe.localImagePath) {
            guard recipe.localImagePath != nil, let data = store.localImageData(for: recipe) else {
                local = nil
                return
            }
            local = UIImage(data: data)
        }
    }
}

/// A small fact about a recipe: time, servings, difficulty.
struct RecipeFact: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

/// Where the recipe came from. Shown on every card, because a recipe written by
/// a language model and a recipe the cook rewrote are not the same thing and
/// the card should never blur the two.
struct RecipeSourceBadge: View {
    let source: Recipe.Source

    var body: some View {
        Label(source.frenchLabel, systemImage: source.symbolName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.cuisine.opacity(0.14), in: Capsule())
            .foregroundStyle(Theme.cuisine)
    }
}

/// Free-form tags, which are how the cook organises the bank. Existing tags
/// from other recipes are offered so the vocabulary stays consistent instead of
/// drifting into "rapide", "Rapide" and "rapides".
struct TagEditor: View {
    @Binding var tags: [String]
    let suggestions: [String]

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var available: [String] {
        let existing = Set(tags.map(Self.key))
        return suggestions.filter { !existing.contains(Self.key($0)) }
    }

    private static func key(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tags.isEmpty {
                Text("Aucune étiquette. Ajoutez les vôtres pour ranger vos recettes comme vous voulez.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                FlowRow(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Theme.cuisine.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.cuisine)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("Nouvelle étiquette", text: $draft)
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .onSubmit(add)
                Button("Ajouter", action: add)
                    .font(.caption.weight(.semibold))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.subheadline)

            if !available.isEmpty {
                Text("Déjà utilisées").font(.caption2).foregroundStyle(.secondary)
                FlowRow(spacing: 6) {
                    ForEach(available.prefix(12), id: \.self) { tag in
                        Button(tag) { tags = RecipeDraft.uniqueTrimmed(tags + [tag]) }
                            .font(.caption)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                            .foregroundStyle(.primary)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func add() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tags = RecipeDraft.uniqueTrimmed(tags + [trimmed])
        draft = ""
        focused = true
    }
}

/// Lays its children out left to right, wrapping onto new lines. SwiftUI has no
/// built-in flow layout, and tag lists need one.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
