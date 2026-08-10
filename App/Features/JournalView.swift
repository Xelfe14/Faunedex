import SwiftUI
import SwiftData
import UIKit
import FlaunedexCore

/// A chronological diary of every observation — photo, species, place, date.
struct JournalView: View {
    @Query(sort: \Sighting.capturedAt, order: .reverse) private var sightings: [Sighting]
    @State private var reviewing: Sighting?
    private let store = PhotoStore()

    /// Group sightings by day so the journal reads like a field notebook.
    private var days: [(date: Date, items: [Sighting])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sightings) { calendar.startOfDay(for: $0.capturedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        Group {
            if sightings.isEmpty {
                EmptyStateView(
                    title: "Journal vide",
                    message: "Chaque observation s'ajoutera ici, jour après jour.",
                    systemImage: "book.closed"
                )
            } else {
                List {
                    ForEach(days, id: \.date) { day in
                        Section {
                            ForEach(day.items) { sighting in row(for: sighting) }
                        } header: {
                            Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Journal")
        .sheet(item: $reviewing) { ReviewSheet(sighting: $0) }
    }

    @ViewBuilder private func row(for sighting: Sighting) -> some View {
        let content = HStack(spacing: 12) {
            thumbnail(sighting)
            VStack(alignment: .leading, spacing: 3) {
                Text(sighting.species?.displayName ?? statusLabel(sighting))
                    .font(.subheadline.weight(.semibold))
                if let scientific = sighting.species?.scientificName {
                    Text(scientific).font(.caption).italic().foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(sighting.capturedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let iso = sighting.countryISO {
                        Label(EuropeanCountries.frenchName(for: iso), systemImage: "mappin")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if sighting.status == .needsReview {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
            }
        }

        if let species = sighting.species {
            NavigationLink { SpeciesDetailView(species: species) } label: { content }
        } else if sighting.status == .needsReview || sighting.status == .failed {
            Button { reviewing = sighting } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func thumbnail(_ sighting: Sighting) -> some View {
        Group {
            if let data = store.load(sighting.photoRelativePath), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.brand.opacity(0.08)
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusLabel(_ sighting: Sighting) -> String {
        switch sighting.status {
        case .pendingIdentification, .pendingGeocoding: return "Identification en attente…"
        case .needsReview: return "À vérifier"
        case .failed: return "Échec de l'identification"
        case .complete: return "Observation"
        }
    }
}
