import SwiftUI
import SwiftData
import MapKit
import FlaunedexCore

/// A map of every sighting. Tapping a pin opens the species. Isolated behind
/// this view so an `MKMapView` clustering wrapper can drop in later if pin
/// counts grow (SwiftUI `Map` has no native clustering).
///
/// Sightings saved without a position can't be pinned, so they are counted
/// above the map with a way to place them by hand, rather than silently left
/// out.
struct SightingsMapView: View {
    @Query private var sightings: [Sighting]
    @State private var selected: Sighting?
    @State private var placing = false

    private var located: [Sighting] {
        sightings.filter(\.hasCoordinate)
    }

    private var unlocatedCount: Int {
        sightings.count - located.count
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
                        UserAnnotation()
                    }
                    .mapControls { MapUserLocationButton() }
                }
            }
            .safeAreaInset(edge: .top) {
                if unlocatedCount > 0 {
                    Button {
                        placing = true
                    } label: {
                        Label(unlocatedCount > 1
                              ? "\(unlocatedCount) observations sans position : les placer"
                              : "1 observation sans position : la placer",
                              systemImage: "mappin.slash")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.brand)
                    .padding(.top, 6)
                }
            }
            .navigationTitle("Carte")
            .navigationDestination(item: Binding(
                get: { selected?.species },
                set: { _ in selected = nil }
            )) { species in
                SpeciesDetailView(species: species)
            }
            .sheet(isPresented: $placing) {
                UnlocatedSightingsView()
            }
        }
    }
}
