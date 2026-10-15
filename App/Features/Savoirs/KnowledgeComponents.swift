import SwiftUI
import UIKit
import FlaunedexCore

/// The card's picture, preferring the copy cached on disk, as recipes do.
struct KnowledgeImage: View {
    let card: KnowledgeCard

    @Environment(KnowledgeStore.self) private var store
    @State private var local: UIImage?

    var body: some View {
        Group {
            if let local {
                Image(uiImage: local).resizable().aspectRatio(contentMode: .fill)
            } else {
                RemoteImage(urlString: card.thumbURLString ?? card.imageURLString,
                            symbol: card.theme.symbolName, tint: Theme.savoirs)
            }
        }
        .task(id: card.localImagePath) {
            guard card.localImagePath != nil, let data = store.localImageData(for: card) else {
                local = nil
                return
            }
            local = UIImage(data: data)
        }
    }
}

/// One row of the collection: picture, title, the sentence to remember, and
/// where the card stands in the review cycle.
struct KnowledgeRow: View {
    let card: KnowledgeCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KnowledgeImage(card: card)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(card.title.isEmpty ? "Sans titre" : card.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if card.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.treasure)
                    }
                }
                if let summary = card.summaryFR {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                ReviewStatusLabel(card: card)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// "À réviser", "Nouvelle", or "Révision dans 3 jours".
struct ReviewStatusLabel: View {
    let card: KnowledgeCard
    var now: Date = .now

    var body: some View {
        let state = card.review
        Group {
            if state.isNew {
                Label("Nouvelle", systemImage: "sparkle")
                    .foregroundStyle(Theme.savoirs)
            } else if state.isDue(at: now) {
                Label("À réviser", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.orange)
            } else if let due = state.dueAt {
                Label("Révision \(ReviewScheduler.frenchDelay(days: ReviewScheduler.daysUntil(due, from: now)))",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.weight(.medium))
        .labelStyle(.titleAndIcon)
    }
}

/// How well a card is known, as a row of dots: one per box reached.
struct ReviewBoxMeter: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...ReviewScheduler.maxBox, id: \.self) { level in
                Circle()
                    .fill(level <= box ? Theme.savoirs : Color.primary.opacity(0.12))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Niveau \(box) sur \(ReviewScheduler.maxBox)")
    }
}
