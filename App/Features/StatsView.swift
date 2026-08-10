import SwiftUI
import SwiftData
import FlaunedexCore

/// Collection progress: totals, breakdowns, and achievement badges.
struct StatsView: View {
    @Query private var species: [Species]
    @Query private var sightings: [Sighting]

    private var animalCount: Int { species.filter { $0.realm == .animal }.count }
    private var plantCount: Int { species.filter { $0.realm == .plant }.count }
    private var familyCount: Int { Set(species.compactMap { $0.family }).count }
    private var seenCountryCount: Int { Set(sightings.compactMap { $0.countryISO }).count }
    private var rangeCountryCount: Int { Set(species.flatMap { $0.rangeCountries }).count }

    /// Species per family, biggest first — the shape of the collection.
    private var topFamilies: [(name: String, count: Int)] {
        Dictionary(grouping: species.compactMap { $0.family }, by: { $0 })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(6).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headline
                tiles
                if !topFamilies.isEmpty { familyBreakdown }
                achievementsSection
            }
            .padding()
        }
        .canvasBackground()
        .navigationTitle("Statistiques")
    }

    private var headline: some View {
        VStack(spacing: 4) {
            Text("\(species.count)")
                .font(Theme.display(52))
                .foregroundStyle(Theme.brand)
                .monospacedDigit()
            Text(species.count == 1 ? "espèce découverte" : "espèces découvertes")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .cardSurface()
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(title: "Faune", value: animalCount, icon: "pawprint.fill", tint: Theme.fauna)
            StatTile(title: "Flore", value: plantCount, icon: "leaf.fill", tint: Theme.flora)
            StatTile(title: "Familles", value: familyCount, icon: "rectangle.3.group", tint: Theme.brand)
            StatTile(title: "Observations", value: sightings.count, icon: "camera.fill", tint: Theme.brand)
            StatTile(title: "Pays visités", value: seenCountryCount, icon: "mappin.and.ellipse", tint: Theme.fauna)
            StatTile(title: "Pays couverts", value: rangeCountryCount, icon: "globe.europe.africa.fill", tint: Theme.flora)
        }
    }

    private var familyBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Familles les mieux représentées").font(Theme.display(16))
            let maxCount = topFamilies.first?.count ?? 1
            ForEach(topFamilies, id: \.name) { family in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(family.name).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text("\(family.count)").font(.caption.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule()
                            .fill(Theme.brand.opacity(0.75))
                            .frame(width: max(6, geo.size.width * CGFloat(family.count) / CGFloat(maxCount)))
                    }
                    .frame(height: 7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Succès").font(Theme.display(16))
            ForEach(achievements, id: \.title) { badge in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(badge.unlocked ? Theme.treasure.opacity(0.18) : Color.primary.opacity(0.06))
                            .frame(width: 40, height: 40)
                        Image(systemName: badge.unlocked ? "seal.fill" : "lock.fill")
                            .foregroundStyle(badge.unlocked ? Theme.treasure : .secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.title).font(.subheadline.weight(.semibold))
                        Text(badge.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .opacity(badge.unlocked ? 1 : 0.55)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    private struct Badge { let title: String; let detail: String; let unlocked: Bool }

    private var achievements: [Badge] {
        [
            Badge(title: "Premier pas", detail: "Découvrir une première espèce", unlocked: species.count >= 1),
            Badge(title: "Premier oiseau", detail: "Photographier un oiseau",
                  unlocked: species.contains { $0.animalGroup == .bird }),
            Badge(title: "Botaniste", detail: "10 plantes découvertes", unlocked: plantCount >= 10),
            Badge(title: "Naturaliste", detail: "5 familles différentes", unlocked: familyCount >= 5),
            Badge(title: "Grand voyageur", detail: "Observer dans 3 pays", unlocked: seenCountryCount >= 3),
            Badge(title: "Rareté", detail: "Découvrir une espèce menacée",
                  unlocked: species.contains { $0.isNotable }),
            Badge(title: "Collectionneur", detail: "25 espèces au total", unlocked: species.count >= 25),
        ]
    }
}

private struct StatTile: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text("\(value)").font(Theme.display(26)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(radius: Theme.tileRadius)
    }
}
