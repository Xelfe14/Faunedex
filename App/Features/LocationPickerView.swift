import SwiftUI
import SwiftData
import MapKit
import UIKit
import FlaunedexCore

/// The sightings that have no position, each one a tap away from being placed.
struct UnlocatedSightingsView: View {
    @Query(sort: \Sighting.capturedAt, order: .reverse) private var sightings: [Sighting]
    @Environment(\.dismiss) private var dismiss
    private let store = PhotoStore()

    private var unlocated: [Sighting] { sightings.filter { !$0.hasCoordinate } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(unlocated) { sighting in
                        NavigationLink {
                            LocationPickerView(sighting: sighting)
                        } label: {
                            HStack(spacing: 12) {
                                thumbnail(sighting)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sighting.species?.displayName ?? "Observation")
                                        .font(.subheadline.weight(.semibold))
                                    Text(sighting.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Le GPS n'avait pas trouvé la position au moment de ces photos. Placez-les à l'endroit où vous les avez prises.")
                }
            }
            .navigationTitle("Sans position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
            .onChange(of: unlocated.isEmpty) { _, empty in
                if empty { dismiss() }
            }
        }
        .tint(Theme.brand)
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
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Place one sighting by moving the map under a fixed pin, the way a delivery
/// address is picked: no precise tap needed on a small screen.
struct LocationPickerView: View {
    let sighting: Sighting

    @Environment(ScanCoordinator.self) private var scan
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .userLocation(fallback: .region(LocationPickerView.france))
    @State private var center: CLLocationCoordinate2D?
    @State private var saving = false

    private static let france = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.6, longitude: 2.4),
        span: MKCoordinateSpan(latitudeDelta: 9, longitudeDelta: 9)
    )

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            center = context.region.center
        }
        .overlay {
            // The pin's point sits on the centre of the map.
            Image(systemName: "mappin")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.brand)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .offset(y: -18)
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: place) {
                Group {
                    if saving {
                        ProgressView()
                    } else {
                        Label("Placer l'observation ici", systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
            .disabled(center == nil || saving)
            .padding()
            .background(.bar)
        }
        .navigationTitle(sighting.species?.displayName ?? "Observation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func place() {
        guard let center else { return }
        saving = true
        Task {
            // A position picked by hand has no measured accuracy.
            await scan.setLocation(latitude: center.latitude, longitude: center.longitude,
                                   accuracy: -1, for: sighting)
            dismiss()
        }
    }
}
