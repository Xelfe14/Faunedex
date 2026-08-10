import SwiftUI
import SwiftData
import CoreLocation
import FlaunedexCore

/// "Découvertes" — species recorded around you, in this season, that you haven't
/// collected yet. A live scavenger hunt built from the same GBIF occurrence data
/// the dex already relies on.
struct DiscoverView: View {
    @Query private var collected: [Species]

    @State private var location = LocationProvider()
    @State private var suggestions: [NearbySuggestion] = []
    @State private var state: LoadState = .idle
    @State private var radiusKm: Double = 25
    @State private var realmFilter: Realm?

    private enum LoadState: Equatable {
        case idle, locating, loading, loaded, noLocation, failed(String)
    }

    private let service = NearbyService()

    var body: some View {
        List {
            Section {
                Picker("Règne", selection: $realmFilter) {
                    Text("Tout").tag(Realm?.none)
                    Text("Faune").tag(Realm?.some(.animal))
                    Text("Flore").tag(Realm?.some(.plant))
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Rayon")
                    Spacer()
                    Text("\(Int(radiusKm)) km").foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $radiusKm, in: 5...100, step: 5)
            }

            switch state {
            case .idle, .locating, .loading:
                Section { loadingRow }
            case .noLocation:
                Section { Label("Position indisponible. Activez la localisation pour voir les espèces autour de vous.",
                                systemImage: "location.slash") }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                    Button("Réessayer") { Task { await load() } }
                }
            case .loaded:
                if suggestions.isEmpty {
                    Section {
                        Text("Rien de nouveau dans ce rayon pour cette saison — élargissez la recherche.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(suggestions) { s in SuggestionRow(suggestion: s) }
                    } header: {
                        Text("\(suggestions.count) espèces à découvrir près d'ici")
                    } footer: {
                        Text("D'après les observations GBIF dans un rayon de \(Int(radiusKm)) km, à cette période de l'année. À vous de les trouver !")
                    }
                }
            }
        }
        .navigationTitle("Découvertes")
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: realmFilter) { _, _ in Task { await load() } }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(state == .locating ? "Recherche de votre position…" : "Consultation des observations…")
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        state = .locating
        location.requestAuthorization()
        guard let fix = await location.currentLocation() else {
            state = .noLocation
            return
        }
        state = .loading
        let month = Calendar.current.component(.month, from: Date())
        let collectedKeys = Set(collected.map(\.gbifKey))
        do {
            suggestions = try await service.suggestions(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                radiusKm: radiusKm,
                month: month,
                realm: realmFilter,
                excluding: collectedKeys,
                limit: 15
            )
            state = .loaded
        } catch {
            state = .failed("Impossible de charger les suggestions.")
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: NearbySuggestion

    private var accent: Color {
        Theme.accent(for: suggestion.realm ?? .animal)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.14)).frame(width: 42, height: 42)
                Image(systemName: icon).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.displayName).font(.subheadline.weight(.semibold))
                Text(suggestion.scientificName).font(.caption).italic().foregroundStyle(.secondary)
                if let family = suggestion.family {
                    Text(family).font(.caption2).foregroundStyle(accent)
                }
            }
            Spacer()
            VStack(spacing: 1) {
                Text("\(suggestion.occurrenceCount)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                Text("obs.").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch suggestion.animalGroup {
        case .bird: return "bird.fill"
        case .mammal: return "hare.fill"
        case .insect: return "ant.fill"
        case .fish: return "fish.fill"
        case .amphibian, .reptile: return "lizard.fill"
        case .mollusk: return "tortoise.fill"
        case .arachnid: return "ladybug.fill"
        default: return suggestion.realm == .plant ? "leaf.fill" : "pawprint.fill"
        }
    }
}
