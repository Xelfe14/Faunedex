import SwiftUI
import UIKit
import FlaunedexCore

/// The questions asked about a species and Gemini's answers. An answer's
/// passages can be highlighted (select, then "Surligner" in the menu that
/// appears) and go on the species card.
struct ConversationMessages: View {
    let species: Species
    var sighting: Sighting? = nil

    @Environment(SpeciesChatStore.self) private var chat

    private let suggestions = [
        "Comment le reconnaître à coup sûr ?",
        "Où et quand peut-on l'observer ?",
        "Est-il dangereux ou protégé ?",
        "Que voit-on exactement sur ma photo ?",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Discussion", systemImage: "bubble.left.and.text.bubble.right")
                    .font(Theme.display(16))
                    .foregroundStyle(Theme.accent(for: species.realm))
                Spacer()
            }
            if species.chat.isEmpty && chat.pending[species.gbifKey] == nil {
                Text("Posez vos questions sur cette espèce ou sur votre photo. Dans une réponse, sélectionnez un passage puis touchez « Surligner » : il s'ajoute à la fiche.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                FlowRow(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            Task { await chat.ask(suggestion, about: species, photo: sighting) }
                        } label: {
                            Text(suggestion)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(Theme.accent(for: species.realm).opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent(for: species.realm))
                        .disabled(!chat.hasGeminiKey)
                    }
                }
            }

            ForEach(species.chat) { turn in
                if turn.role == .user {
                    UserBubble(text: turn.text, tint: Theme.accent(for: species.realm))
                } else {
                    AnswerBubble(turn: turn, species: species)
                }
            }

            if let question = chat.pending[species.gbifKey] {
                UserBubble(text: question, tint: Theme.accent(for: species.realm))
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Gemini rédige sa réponse…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
            }

            if let error = chat.errors[species.gbifKey] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                if let question = chat.failed[species.gbifKey] {
                    Button {
                        Task { await chat.ask(question, about: species, photo: sighting) }
                    } label: {
                        Label("Renvoyer « \(question) »", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Theme.accent(for: species.realm))
                }
            }
        }
    }
}

private struct UserBubble: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// An answer, selectable, with its highlighted passages marked, and a button
/// that keeps the whole answer at once.
private struct AnswerBubble: View {
    let turn: ChatTurn
    let species: Species

    @Environment(SpeciesChatStore.self) private var chat

    private var passages: [String] {
        species.highlights.filter { $0.messageID == turn.id }.map(\.text)
    }
    private var wholeAnswerKept: Bool {
        species.highlights.contains { $0.text == turn.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HighlightableText(text: turn.text, highlights: passages) { passage in
                chat.highlight(passage, from: turn, on: species)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            if !wholeAnswerKept {
                Button {
                    chat.highlight(turn.text, from: turn, on: species)
                } label: {
                    Label("Ajouter toute la réponse à la fiche", systemImage: "highlighter")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            }
        }
        .padding(.trailing, 24)
    }
}

/// The field where questions are typed, pinned under the conversation.
struct ChatComposer: View {
    let species: Species
    var sighting: Sighting? = nil

    @Environment(SpeciesChatStore.self) private var chat
    @State private var question = ""
    @FocusState private var focused: Bool

    private var busy: Bool { chat.pending[species.gbifKey] != nil }
    private var canSend: Bool {
        chat.hasGeminiKey && !busy && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var placeholder: String {
        chat.hasGeminiKey ? "Une question sur \(species.displayName)…" : "Ajoutez votre clé Gemini dans Réglages"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .disabled(!chat.hasGeminiKey)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(!canSend)
            .accessibilityLabel("Envoyer")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .tint(Theme.accent(for: species.realm))
    }

    private func send() {
        let text = question
        question = ""
        Task { await chat.ask(text, about: species, photo: sighting) }
    }
}

/// The conversation on its own screen, from the species card.
struct SpeciesChatView: View {
    let species: Species

    @Environment(SpeciesChatStore.self) private var chat
    @State private var confirmingClear = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ConversationMessages(species: species)
                    .padding()
                Color.clear.frame(height: 1).id("end")
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: species.chat.count) { _, _ in
                withAnimation { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: chat.pending[species.gbifKey]) { _, _ in
                withAnimation { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .canvasBackground()
        .safeAreaInset(edge: .bottom) { ChatComposer(species: species) }
        .navigationTitle(species.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent(for: species.realm))
        .toolbar {
            if !species.chat.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            confirmingClear = true
                        } label: {
                            Label("Effacer la discussion", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Effacer la discussion ?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { chat.clearConversation(of: species) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les passages surlignés restent sur la fiche.")
        }
    }
}

/// Selectable text whose edit menu offers "Surligner". SwiftUI's own selectable
/// text can't add an action to that menu, so this is a read-only UITextView.
struct HighlightableText: UIViewRepresentable {
    let text: String
    let highlights: [String]
    let onHighlight: (String) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onHighlight = onHighlight
        let attributed = Self.attributed(text, highlights: highlights)
        if view.attributedText != attributed {
            view.attributedText = attributed
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onHighlight: onHighlight) }

    static func attributed(_ text: String, highlights: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: UIColor.label,
        ])
        for range in HighlightRanges.ranges(of: highlights, in: text) {
            result.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.4),
                                range: NSRange(range, in: text))
        }
        return result
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onHighlight: (String) -> Void

        init(onHighlight: @escaping (String) -> Void) {
            self.onHighlight = onHighlight
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let swiftRange = Range(range, in: textView.text) else {
                return UIMenu(children: suggestedActions)
            }
            let passage = String(textView.text[swiftRange])
            let highlight = UIAction(title: "Surligner", image: UIImage(systemName: "highlighter")) { [weak self, weak textView] _ in
                self?.onHighlight(passage)
                textView?.selectedRange = NSRange(location: 0, length: 0)
            }
            return UIMenu(children: [highlight] + suggestedActions)
        }
    }
}
