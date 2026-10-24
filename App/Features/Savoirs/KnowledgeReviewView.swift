import SwiftUI
import SwiftData
import FlaunedexCore

/// Flashcard review: the question, then the answer, then how it went.
///
/// A session takes the cards that are due, oldest first. A card marked "À
/// revoir" comes back at the end of the same session, so a session ends with
/// every card answered correctly once. Free practice goes through the whole
/// collection without touching the schedule.
struct KnowledgeReviewView: View {
    @Query(sort: \KnowledgeCard.createdAt) private var cards: [KnowledgeCard]
    @Query private var categories: [KnowledgeCategory]
    @Environment(KnowledgeStore.self) private var store

    /// Card ids still to show, in order. Empty and not started: the overview.
    @State private var queue: [UUID] = []
    @State private var started = false
    @State private var practice = false
    @State private var revealed = false
    @State private var answered = 0
    @State private var missed = 0

    /// Longest a session gets, so a backlog after a holiday stays manageable.
    private let sessionSize = 20

    private var dueCards: [KnowledgeCard] {
        let now = Date.now
        return cards
            .filter { $0.isDue(at: now) }
            .sorted { ($0.reviewDueAt ?? $0.createdAt) < ($1.reviewDueAt ?? $1.createdAt) }
    }

    private var current: KnowledgeCard? {
        guard let id = queue.first else { return nil }
        return cards.first { $0.id == id }
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                EmptyStateView(
                    title: "Rien à réviser",
                    message: "Créez vos premières fiches dans Apprendre : elles arriveront ici pour être révisées.",
                    systemImage: "rectangle.on.rectangle.angled"
                )
            } else if started, let card = current {
                session(card)
            } else if started {
                finished
            } else {
                overview
            }
        }
        .canvasBackground()
        .navigationTitle("Réviser")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.savoirs)
        .toolbar {
            if started {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Terminer") { reset() }
                }
            }
        }
    }

    // MARK: Overview

    private var overview: some View {
        ScrollView {
            VStack(spacing: 18) {
                let due = dueCards
                ZStack {
                    Circle().fill(Theme.savoirs.opacity(0.12)).frame(width: 128, height: 128)
                    VStack(spacing: 0) {
                        Text("\(due.count)")
                            .font(Theme.display(44))
                            .foregroundStyle(Theme.savoirs)
                        Text(due.count > 1 ? "fiches" : "fiche")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 24)

                Text(due.isEmpty ? "Tout est à jour" : "À réviser aujourd'hui")
                    .font(Theme.display(22))

                if due.isEmpty {
                    Text(nextDueSentence)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    let newCount = due.filter { $0.review.isNew }.count
                    if newCount > 0 {
                        Text("dont \(newCount) nouvelle\(newCount > 1 ? "s" : "")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        start(practice: false)
                    } label: {
                        Label(due.count > sessionSize ? "Commencer (\(sessionSize) fiches)" : "Commencer",
                              systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 32)
                }

                Button {
                    start(practice: true)
                } label: {
                    Label("S'entraîner sur toutes les fiches", systemImage: "shuffle")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.top, 4)
                Text("L'entraînement libre ne change pas le calendrier de révision.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
    }

    private var nextDueSentence: String {
        let upcoming = cards.compactMap(\.reviewDueAt).filter { $0 > .now }.min()
        guard let upcoming else { return "Aucune révision prévue." }
        let days = ReviewScheduler.daysUntil(upcoming, from: .now)
        return "Prochaine révision \(ReviewScheduler.frenchDelay(days: days))."
    }

    // MARK: Session

    private func session(_ card: KnowledgeCard) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(practice ? "Entraînement" : "Révision")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(queue.count) restante\(queue.count > 1 ? "s" : "")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: CategoryIndex(categories).symbol(for: card.categoryKey))
                        Text(CategoryIndex(categories).name(for: card.categoryKey))
                        Spacer()
                        ReviewBoxMeter(box: card.reviewBox)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.savoirs)

                    Text(card.reviewQuestion)
                        .font(Theme.display(21, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if revealed {
                        Divider()
                        Text(card.reviewAnswer)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        if let etymology = card.etymologyFR {
                            Label {
                                Text(etymology)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "text.book.closed")
                                    .foregroundStyle(Theme.savoirs)
                            }
                        }
                        if !card.keyPoints.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(card.keyPoints.enumerated()), id: \.offset) { _, point in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.savoirs)
                                        Text(point).font(.subheadline)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        NavigationLink {
                            KnowledgeCardView(card: card)
                        } label: {
                            Label("Ouvrir la fiche", systemImage: "doc.text")
                                .font(.subheadline)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
                .padding(.horizontal)
            }

            if revealed {
                ratingButtons(for: card)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { revealed = true }
                } label: {
                    Text("Afficher la réponse")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }

    private func ratingButtons(for card: KnowledgeCard) -> some View {
        HStack(spacing: 10) {
            ForEach(ReviewRating.allCases, id: \.self) { rating in
                Button {
                    rate(card, rating)
                } label: {
                    VStack(spacing: 2) {
                        Text(rating.frenchLabel).font(.subheadline.weight(.semibold))
                        if !practice {
                            Text(ReviewScheduler.preview(card.review, rating: rating))
                                .font(.caption2)
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(color(for: rating))
            }
        }
        .padding(.horizontal)
    }

    private func color(for rating: ReviewRating) -> Color {
        switch rating {
        case .again: return .orange
        case .good: return Theme.savoirs
        case .easy: return Theme.flora
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.flora)
            Text("Session terminée")
                .font(Theme.display(22))
            Text("\(answered) réponse\(answered > 1 ? "s" : "")\(missed > 0 ? ", dont \(missed) à revoir" : "").")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Revenir aux révisions") { reset() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func start(practice: Bool) {
        self.practice = practice
        let picked = practice ? cards.shuffled() : Array(dueCards.prefix(sessionSize))
        queue = picked.map(\.id)
        answered = 0
        missed = 0
        revealed = false
        started = true
    }

    private func rate(_ card: KnowledgeCard, _ rating: ReviewRating) {
        if !practice { store.record(rating, for: card) }
        answered += 1
        withAnimation(.easeInOut(duration: 0.2)) {
            queue.removeFirst()
            if rating == .again {
                missed += 1
                queue.append(card.id)
            }
            revealed = false
        }
    }

    private func reset() {
        started = false
        queue = []
        revealed = false
    }
}
