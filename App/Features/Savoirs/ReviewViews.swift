import SwiftUI
import SwiftData
import UIKit
import FlaunedexCore

/// A revision session in progress: the dealt cards and how far along it is.
/// Every verdict is saved the moment it is given, so closing a session halfway
/// loses nothing.
@MainActor
@Observable
final class ReviewSession: Identifiable {
    let id = UUID()
    let scope: KnowledgeFolder?
    let scopeLabel: String
    let firstSide: CardSide
    private(set) var mode: ReviewMode
    private(set) var requested: Int
    private(set) var cards: [KnowledgeCard]

    var index = 0
    var flipped = false
    var tally: [ReviewVerdict: Int] = [:]
    /// Bumped on each "Maîtrisée", which fires the confetti.
    var celebration = 0

    init(scope: KnowledgeFolder?, scopeLabel: String, firstSide: CardSide, mode: ReviewMode,
         requested: Int, cards: [KnowledgeCard]) {
        self.scope = scope
        self.scopeLabel = scopeLabel
        self.firstSide = firstSide
        self.mode = mode
        self.requested = requested
        self.cards = cards
    }

    var current: KnowledgeCard? { cards.indices.contains(index) ? cards[index] : nil }
    var progress: Double { cards.isEmpty ? 1 : Double(min(index, cards.count)) / Double(cards.count) }

    /// Start over in place with a new deal (after "Nouvelle session" or
    /// "Réviser quand même"), keeping the same scope and direction.
    func restart(mode: ReviewMode, requested: Int, cards: [KnowledgeCard]) {
        self.mode = mode
        self.requested = requested
        self.cards = cards
        index = 0
        flipped = false
        tally = [:]
    }
}

// MARK: - Setting a session up

/// Choose what to revise, how many cards, and which side comes first.
struct ReviewSetupView: View {
    enum InitialScope: Equatable {
        /// Whatever was chosen last time.
        case remembered
        case all
        case folder(UUID)
    }

    var initialScope: InitialScope = .remembered

    @Environment(KnowledgeStore.self) private var store
    @Query private var allFolders: [KnowledgeFolder]
    @Query private var allCards: [KnowledgeCard]

    @AppStorage("savoirs.review.folder") private var storedFolderID = ""
    @AppStorage("savoirs.review.count") private var storedCount = 10
    @AppStorage("savoirs.review.versoFirst") private var versoFirst = false

    @State private var session: ReviewSession?

    private var folder: KnowledgeFolder? {
        allFolders.first { $0.id.uuidString == storedFolderID }
    }

    private var folderBinding: Binding<KnowledgeFolder?> {
        Binding(get: { folder }, set: { storedFolderID = $0?.id.uuidString ?? "" })
    }

    var body: some View {
        let scope = KnowledgeIndex.cards(in: folder, cards: allCards, folders: allFolders)
        let status = KnowledgeIndex.status(of: scope)
        let count = min(max(1, storedCount), max(1, status.dealable))

        ScrollView {
            VStack(spacing: 16) {
                scopeCard(status: status)

                if status.total == 0 {
                    notice("🗂️", "Rien à réviser ici",
                           allCards.isEmpty
                           ? "Créez des cartes dans l'onglet Dossiers, puis revenez."
                           : "Ce dossier ne contient encore aucune carte.")
                } else if status.isMastered {
                    masteredCard(status: status, scope: scope)
                } else if status.dealable == 0 {
                    notice("📦", "Toutes les cartes sont retirées",
                           "Remettez-en en jeu depuis leur dossier, en balayant une carte vers la droite.")
                } else {
                    countCard(count: count, available: status.dealable)
                    directionCard
                    Button {
                        start(.ordinary, count: count, scope: scope)
                    } label: {
                        Label("Commencer", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.knowledge, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .canvasBackground()
        .navigationTitle("Réviser")
        .tint(Theme.knowledge)
        .fullScreenCover(item: $session) { session in
            ReviewSessionView(session: session)
        }
        .onAppear(perform: applyInitialScope)
    }

    private func applyInitialScope() {
        switch initialScope {
        case .remembered: break
        case .all: storedFolderID = ""
        case .folder(let id): storedFolderID = id.uuidString
        }
    }

    private func start(_ mode: ReviewMode, count: Int, scope: [KnowledgeCard]) {
        let dealt = store.deal(from: scope, count: count, mode: mode)
        guard !dealt.isEmpty else { return }
        session = ReviewSession(
            scope: folder,
            scopeLabel: KnowledgeIndex.pathLabel(of: folder, folders: allFolders),
            firstSide: versoFirst ? .verso : .recto,
            mode: mode, requested: count, cards: dealt
        )
    }

    // MARK: Cards of the setup screen

    private func scopeCard(status: DeckStatus) -> some View {
        NavigationLink {
            FolderPickerView(purpose: .revisionScope, selection: folderBinding)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    FolderBadge(emoji: folder?.emoji ?? "🗂️", color: folder?.color ?? .indigo, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Réviser").font(.caption).foregroundStyle(.secondary)
                        Text(KnowledgeIndex.pathLabel(of: folder, folders: allFolders))
                            .font(.headline).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                }
                if status.total > 0 { DeckStatusPills(status: status) }
                // Worth saying only when there is something below to include.
                if let folder, allFolders.contains(where: { $0.parent?.id == folder.id }) {
                    Text("Inclut tous ses sous-dossiers.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private func countCard(count: Int, available: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nombre de cartes").font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text("\(count)")
                    .font(Theme.display(44))
                    .monospacedDigit()
                    .foregroundStyle(Theme.knowledge)
                Text("sur \(available) disponible\(available > 1 ? "s" : "")")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Stepper("", value: Binding(get: { count }, set: { storedCount = $0 }), in: 1...max(1, available))
                    .labelsHidden()
            }
            HStack(spacing: 8) {
                // Only presets below what is available, then "Toutes": a 7-card
                // folder offers 5 and all 7, never a 10 that would deal 7 anyway.
                ForEach([5, 10, 20, 30].filter { $0 < available }, id: \.self) { preset in
                    presetButton("\(preset)", selected: storedCount == preset) { storedCount = preset }
                }
                presetButton("Toutes (\(available))", selected: storedCount >= available) { storedCount = available }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func presetButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Theme.knowledge.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
            .foregroundStyle(selected ? Theme.knowledge : .primary)
            .buttonStyle(.plain)
    }

    private var directionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $versoFirst) {
                Label("Commencer par le verso", systemImage: "arrow.left.arrow.right")
                    .font(.headline)
            }
            .tint(Theme.knowledge)
            Text(versoFirst
                 ? "Vous verrez le verso, et le recto en retournant la carte. Pratique pour réviser dans l'autre sens, par exemple de l'anglais vers le français."
                 : "Vous verrez le recto, et le verso en retournant la carte.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func masteredCard(status: DeckStatus, scope: [KnowledgeCard]) -> some View {
        VStack(spacing: 10) {
            Text("🏆").font(.system(size: 54))
            Text("Dossier maîtrisé !").font(Theme.display(24))
            if let next = status.nextReturn {
                Text("Prochaine carte le \(KnowledgeIndex.returnDate(next))")
                    .font(.headline).foregroundStyle(Theme.knowledge)
            }
            Text("Toutes les cartes en jeu sont au repos. Elles reviendront d'elles-mêmes, une par une.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                start(.resting, count: min(max(1, storedCount), status.resting), scope: scope)
            } label: {
                Label("Réviser quand même", systemImage: "moon.zzz.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.treasure.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.treasure)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func notice(_ emoji: String, _ title: String, _ message: String) -> some View {
        VStack(spacing: 8) {
            Text(emoji).font(.system(size: 44))
            Text(title).font(Theme.display(19))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

// MARK: - The session

/// A revision session: one card at a time, turned over by a tap, judged by
/// one of three buttons.
struct ReviewSessionView: View {
    @Bindable var session: ReviewSession

    @Environment(KnowledgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var allCards: [KnowledgeCard]
    @Query private var allFolders: [KnowledgeFolder]

    /// The last "Retirer", undoable for a few seconds.
    @State private var undo: (token: VerdictUndo, card: KnowledgeCard, id: UUID)?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 16) {
                topBar
                if let card = session.current {
                    stage(for: card)
                    verdicts(for: card)
                } else {
                    summary
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)

            ConfettiBurst(trigger: session.celebration)

            if let undo {
                VStack {
                    Spacer()
                    undoToast(undo.token, card: undo.card)
                        .padding(.bottom, 110)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: undo?.id)
        .tint(Theme.knowledge)
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(Color.primary.opacity(0.07), in: Circle())
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer la session")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.mode == .resting ? "\(session.scopeLabel) · au repos" : session.scopeLabel)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if !session.cards.isEmpty {
                        Text("\(min(session.index + 1, session.cards.count)) / \(session.cards.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: session.progress)
                    .tint(Theme.knowledge)
                    .animation(.easeInOut, value: session.progress)
            }
        }
    }

    private func stage(for card: KnowledgeCard) -> some View {
        VStack(spacing: 10) {
            FlipCard(flipped: session.flipped) {
                KnowledgeCardFace(card: card, side: session.firstSide, folder: card.folder) { turn() }
            } back: {
                KnowledgeCardFace(card: card, side: session.firstSide.other, folder: card.folder) { turn() }
            }
            .id(card.id)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .frame(maxHeight: .infinity)

            Label(session.flipped ? "Touchez pour revoir l'autre face" : "Touchez la carte pour la retourner",
                  systemImage: "hand.tap")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(session.index == 0 || !session.flipped ? 1 : 0)
        }
    }

    private func verdicts(for card: KnowledgeCard) -> some View {
        HStack(spacing: 10) {
            verdictButton("Retirer", "archivebox", .gray, filled: false) { judge(.retired, card) }
            verdictButton("Suivante", "arrow.right", Theme.knowledge, filled: false) { judge(.next, card) }
            verdictButton("Maîtrisée", "checkmark.seal.fill", .green, filled: true) { judge(.mastered, card) }
        }
    }

    private func verdictButton(_ title: String, _ symbol: String, _ tint: Color, filled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                // A fixed icon box keeps the three labels on one baseline,
                // whatever each symbol's own height.
                Image(systemName: symbol).font(.title3.weight(.semibold))
                    .frame(height: 26)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(filled ? tint : tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(filled ? .white : tint)
        }
        .buttonStyle(.plain)
    }

    private func undoToast(_ token: VerdictUndo, card: KnowledgeCard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill").foregroundStyle(.secondary)
            Text("Carte retirée").font(.subheadline.weight(.semibold))
            Spacer()
            Button("Annuler") { revert(token, card: card) }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.knowledge)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 24)
    }

    @ViewBuilder private var summary: some View {
        let scope = KnowledgeIndex.cards(in: session.scope, cards: allCards, folders: allFolders)
        let status = KnowledgeIndex.status(of: scope)
        SessionSummaryView(
            session: session,
            status: status,
            onAgain: { restart(.ordinary, count: min(session.requested, status.dealable), scope: scope) },
            onAnyway: { restart(.resting, count: min(max(1, session.requested), status.resting), scope: scope) },
            onClose: { dismiss() }
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: Actions

    private func turn() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        session.flipped.toggle()
    }

    private func judge(_ verdict: ReviewVerdict, _ card: KnowledgeCard) {
        let token = store.record(verdict, on: card)
        session.tally[verdict, default: 0] += 1
        switch verdict {
        case .mastered:
            session.celebration += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            undo = nil
        case .next:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            undo = nil
        case .retired:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            let id = UUID()
            undo = (token, card, id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if undo?.id == id { undo = nil }
            }
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            session.index += 1
            session.flipped = false
        }
    }

    /// Undo a "Retirer": restore the card exactly, and step back to it so the
    /// intended verdict can be given.
    private func revert(_ token: VerdictUndo, card: KnowledgeCard) {
        store.undo(token, on: card)
        session.tally[.retired, default: 1] -= 1
        undo = nil
        if session.index > 0, session.cards[session.index - 1].id == card.id {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                session.index -= 1
                session.flipped = false
            }
        }
    }

    private func restart(_ mode: ReviewMode, count: Int, scope: [KnowledgeCard]) {
        let dealt = store.deal(from: scope, count: count, mode: mode)
        guard !dealt.isEmpty else { return }
        withAnimation { session.restart(mode: mode, requested: count, cards: dealt) }
    }
}

/// The end of a session: what happened, and what next.
struct SessionSummaryView: View {
    let session: ReviewSession
    let status: DeckStatus
    let onAgain: () -> Void
    let onAnyway: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Text(status.isMastered ? "🏆" : "🎉").font(.system(size: 70))
            Text(status.isMastered ? "Dossier maîtrisé !" : "Session terminée")
                .font(Theme.display(28))
            if status.isMastered, let next = status.nextReturn {
                Text("Prochaine carte le \(KnowledgeIndex.returnDate(next))")
                    .font(.headline).foregroundStyle(Theme.knowledge)
            }

            HStack(spacing: 10) {
                tile(session.tally[.mastered, default: 0], ("maîtrisée", "maîtrisées"), "checkmark.seal.fill", .green)
                tile(session.tally[.next, default: 0], ("à revoir", "à revoir"), "arrow.right", Theme.knowledge)
                tile(session.tally[.retired, default: 0], ("retirée", "retirées"), "archivebox.fill", .gray)
            }

            if session.mode == .ordinary, session.cards.count < session.requested, !status.isMastered {
                Text("Ce dossier n'avait que \(session.cards.count) carte\(session.cards.count > 1 ? "s" : "") à réviser.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if status.dealable > 0 {
                    Button(action: onAgain) {
                        Label("Nouvelle session", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.knowledge, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                if status.isMastered {
                    Button(action: onAnyway) {
                        Label("Réviser quand même", systemImage: "moon.zzz.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.treasure.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(Theme.treasure)
                    }
                    .buttonStyle(.plain)
                }
                Button("Terminer", action: onClose)
                    .font(.headline)
                    .padding(.vertical, 10)
            }
        }
    }

    /// French agrees the word with the number, and "à revoir" never takes an s,
    /// so both forms are spelled out rather than built by appending a letter.
    private func tile(_ value: Int, _ label: (singular: String, plural: String), _ symbol: String,
                      _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text("\(value)").font(Theme.display(26)).monospacedDigit()
            Text(value > 1 ? label.plural : label.singular).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardSurface(radius: Theme.tileRadius)
    }
}
