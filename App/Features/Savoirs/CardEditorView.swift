import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import FlaunedexCore

/// Write a card: recto and verso, each a small rich-text document with links
/// and pictures, like an email.
///
/// Both editors stay alive side by side and the segmented control only shows
/// one, so switching faces keeps each side's text, cursor and undo history.
struct CardEditorView: View {
    let card: KnowledgeCard?
    let store: KnowledgeStore

    @Environment(\.dismiss) private var dismiss

    @State private var folder: KnowledgeFolder?
    @State private var side: CardSide = .recto
    @StateObject private var recto: RichTextEditorModel
    @StateObject private var verso: RichTextEditorModel

    @State private var photoTarget: CardSide = .recto
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var preparingPhoto = false

    @State private var linkTarget: CardSide?
    @State private var linkAddress = ""
    @State private var linkLabel = ""
    @State private var linkRejected = false

    @State private var confirmingDiscard = false
    @State private var savedCount = 0

    init(card: KnowledgeCard?, folder: KnowledgeFolder?, store: KnowledgeStore) {
        self.card = card
        self.store = store
        _folder = State(initialValue: card?.folder ?? folder)
        let provider: (UUID) -> UIImage? = { [weak store] id in
            MainActor.assumeIsolated { store?.image(for: id, in: card) }
        }
        let style = RichTextStyle(imageProvider: provider)
        _recto = StateObject(wrappedValue: RichTextEditorModel(document: card?.recto ?? .empty, style: style))
        _verso = StateObject(wrappedValue: RichTextEditorModel(document: card?.verso ?? .empty, style: style))
    }

    private var isNew: Bool { card == nil }
    private var canSave: Bool { folder != nil && !(recto.isEmpty && verso.isEmpty) }
    private var hasChanges: Bool {
        recto.hasChanges || verso.hasChanges || folder?.id != card?.folder?.id
    }

    private func model(_ side: CardSide) -> RichTextEditorModel {
        side == .recto ? recto : verso
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                folderRow
                Picker("Face", selection: $side) {
                    ForEach(CardSide.allCases) { Text($0.frenchLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                ZStack {
                    editorLayer(.recto)
                    editorLayer(.verso)
                    if preparingPhoto {
                        ProgressView("Préparation de l'image…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, isNew ? 4 : 12)

                if isNew { saveAndContinueBar }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(isNew ? "Nouvelle carte" : "Modifier la carte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save(andContinue: false) }
                        .disabled(!canSave)
                }
            }
        }
        // On the stack itself, not on its content: a tint set inside the stack
        // does not reach the buttons of the navigation bar.
        .tint(Theme.knowledge)
        .interactiveDismissDisabled(hasChanges)
        .photosPicker(isPresented: $showingLibrary, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in loadPicked(item) }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in insert(image) }
                .ignoresSafeArea()
        }
        .alert("Lien", isPresented: Binding(get: { linkTarget != nil }, set: { if !$0 { linkTarget = nil } })) {
            TextField("Adresse, ex. fr.wikipedia.org/wiki/…", text: $linkAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            if model(linkTarget ?? .recto).selectedText.isEmpty {
                TextField("Texte affiché (facultatif)", text: $linkLabel)
            }
            Button("Appliquer") { applyLink() }
            if model(linkTarget ?? .recto).linkAtSelection != nil {
                Button("Retirer le lien", role: .destructive) {
                    model(linkTarget ?? .recto).removeLink()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Pendant les révisions, le lien s'ouvre d'une simple touche.")
        }
        .alert("Adresse non valide", isPresented: $linkRejected) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Entrez une adresse web (https://…, www.…) ou une adresse mail (mailto:…).")
        }
        .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer à écrire", role: .cancel) {}
        }
        .onAppear {
            wireModels()
            if isNew { recto.focus() }
        }
        .onChange(of: side) { old, new in
            if model(old).textView?.isFirstResponder == true { model(new).focus() }
        }
    }

    // MARK: Pieces

    private var folderRow: some View {
        NavigationLink {
            FolderPickerView(purpose: .cardFolder, selection: $folder)
        } label: {
            HStack(spacing: 10) {
                if let folder {
                    FolderBadge(emoji: folder.emoji, color: folder.color, size: 30)
                    Text(folder.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                } else {
                    Image(systemName: "folder.badge.plus").foregroundStyle(.orange)
                    Text("Choisir un dossier").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func editorLayer(_ layer: CardSide) -> some View {
        let editor = model(layer)
        return ZStack(alignment: .topLeading) {
            RichTextEditor(model: editor)
            if editor.isEmpty {
                Text(layer == .recto
                     ? "Recto : le mot, la question, l'événement…"
                     : "Verso : la réponse, la traduction, la date…")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 19)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
            }
        }
        .opacity(side == layer ? 1 : 0)
        .allowsHitTesting(side == layer)
        .accessibilityHidden(side != layer)
    }

    /// Adding many cards in a row (a vocabulary list, say) should not mean
    /// closing and reopening the editor each time.
    private var saveAndContinueBar: some View {
        HStack {
            if savedCount > 0 {
                Label("\(savedCount) carte\(savedCount > 1 ? "s" : "") ajoutée\(savedCount > 1 ? "s" : "")",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Spacer()
            Button {
                save(andContinue: true)
            } label: {
                Label("Enregistrer et en créer une autre", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func wireModels() {
        for layer in CardSide.allCases {
            let editor = model(layer)
            editor.onRequestPhoto = { source in
                photoTarget = layer
                if source == .camera { showingCamera = true } else { showingLibrary = true }
            }
            editor.onRequestLink = {
                linkAddress = editor.linkAtSelection ?? ""
                linkLabel = ""
                linkTarget = layer
            }
        }
    }

    private func applyLink() {
        let target = model(linkTarget ?? .recto)
        if !target.applyLink(linkAddress, label: linkLabel) {
            linkRejected = true
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        preparingPhoto = true
        let target = photoTarget
        Task { @MainActor in
            defer {
                preparingPhoto = false
                pickedItem = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let pending = await Task.detached(priority: .userInitiated) { PendingImage.prepare(from: data) }.value
            if let pending { model(target).insertImage(pending) }
        }
    }

    private func insert(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return }
        preparingPhoto = true
        let target = photoTarget
        Task { @MainActor in
            defer { preparingPhoto = false }
            let pending = await Task.detached(priority: .userInitiated) { PendingImage.prepare(from: data) }.value
            if let pending { model(target).insertImage(pending) }
        }
    }

    private func save(andContinue: Bool) {
        guard let folder else { return }
        let pending = recto.pendingImages.merging(verso.pendingImages) { first, _ in first }
        store.saveCard(card, recto: recto.currentDocument, verso: verso.currentDocument,
                       pendingImages: pending, folder: folder)
        if andContinue {
            savedCount += 1
            recto.load(.empty)
            verso.load(.empty)
            side = .recto
            recto.focus()
        } else {
            dismiss()
        }
    }
}

/// The system camera, for photographing a page or a diagram straight onto a
/// card. Only offered where a camera exists (never in the simulator).
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
