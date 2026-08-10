import SwiftUI
import SwiftData
import MapKit
import FlaunedexCore

/// A map of every sighting. Tapping a pin opens the species. Isolated behind
/// this view so an `MKMapView` clustering wrapper can drop in later if pin
/// counts grow (SwiftUI `Map` has no native clustering).
struct SightingsMapView: View {
    @Query private var sightings: [Sighting]
    @State private var selected: Sighting?

    private var located: [Sighting] {
        sightings.filter { !($0.latitude == 0 && $0.longitude == 0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if located.isEmpty {
                    EmptyStateView(
                        title: "Aucune observation localisée",
                        message: "Vos photos apparaîtront ici, à l'endroit exact où vous les avez prises.",
                        systemImage: "map"
                    )
                    .canvasBackground()
                } else {
                    Map(selection: $selected) {
                        ForEach(located) { s in
                            Marker(s.species?.displayName ?? "Observation",
                                   systemImage: s.species?.realm == .plant ? "leaf.fill" : "pawprint.fill",
                                   coordinate: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude))
                                .tint(Theme.accent(for: s.species?.realm ?? .animal))
                                .tag(s)
                        }
                    }
                }
            }
            .navigationTitle("Carte")
            .navigationDestination(item: Binding(
                get: { selected?.species },
                set: { _ in selected = nil }
            )) { species in
                SpeciesDetailView(species: species)
            }
        }
    }
}
