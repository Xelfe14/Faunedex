import SwiftUI
import SwiftData
import FlaunedexCore

/// The collection grid for one realm (Faune or Flore), with filters by family,
/// by country (natural-range unlock), and — for animals — by sub-group.
struct DexView: View {
    let realm: Realm

    @Query(sort: \Species.dexNumber) private var allSpecies: [Species]
    @State private var search = ""
    @State private var family: String?
    @State private var country: String?
    @State private var group: AnimalGroup?

    private var accent: Color { Theme.accent(for: realm) }
    private var speciesInRealm: [Species] { allSpecies.filter { $0.realm == realm } }

    private var filtered: [Species] {
        speciesInRealm.filter { s in
            (family == nil || s.family == family)
            && (country == nil || s.rangeCountries.contains(country!))
            && (group == nil || s.animalGroup == group)
            && (search.isEmpty || s.displayName.localizedCaseInsensitiveContains(search)
                || s.scientificName.localizedCaseInsensitiveContains(search))
        }
    }

    private var families: [String] { Array(Set(speciesInRealm.compactMap { $0.family })).sorted() }
    private var countries: [String] { Array(Set(speciesInRealm.flatMap { $0.rangeCountries })).sorted() }
    private var groups: [AnimalGroup] {
        Array(Set(speciesInRealm.compactMap { $0.animalGroup })).sorted { $0.frenchLabel < $1.frenchLabel }
    }
    private var hasFilter: Bool { family != nil || country != nil || group != nil }

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if speciesInRealm.isEmpty {
                    EmptyStateView(
                        title: realm == .animal ? "Aucun animal" : "Aucune plante",
                        message: realm == .animal
                            ? "Photographiez un animal pour ouvrir votre collection."
                            : "Photographiez une plante pour ouvrir votre collection.",
                        systemImage: realm == .animal ? "pawprint" : "leaf"
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            countRow
                            filterBar
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(filtered) { species in
                                    NavigationLink { SpeciesDetailView(species: species) } label: {
                                        DexCard(species: species, accent: accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            if filtered.isEmpty { noMatches }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .canvasBackground()
            .navigationTitle(realm == .animal ? "Faune" : "Flore")
            .searchable(text: $search, prompt: "Rechercher une espèce")
        }
        .tint(accent)
    }

    private var countRow: some View {
        HStack {
            Text("\(speciesInRealm.count) espèce\(speciesInRealm.count > 1 ? "s" : "") découverte\(speciesInRealm.count > 1 ? "s" : "")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if hasFilter {
                Button("Réinitialiser") { family = nil; country = nil; group = nil }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if realm == .animal, !groups.isEmpty {
                    FilterMenu(title: "Groupe", selection: group?.frenchLabel, accent: accent) {
                        Button("Tous") { group = nil }
                        ForEach(groups, id: \.self) { g in Button(g.frenchLabel) { group = g } }
                    }
                }
                if !families.isEmpty {
                    FilterMenu(title: "Famille", selection: family, accent: accent) {
                        Button("Toutes") { family = nil }
                        ForEach(families, id: \.self) { f in Button(f) { family = f } }
                    }
                }
                if !countries.isEmpty {
                    FilterMenu(title: "Pays", selection: country.map(EuropeanCountries.frenchName(for:)), accent: accent) {
                        Button("Tous") { country = nil }
                        ForEach(countries, id: \.self) { c in
                            Button(EuropeanCountries.frenchName(for: c)) { country = c }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var noMatches: some View {
        Text("Aucune espèce ne correspond à ces filtres.")
            .font(.subheadline).foregroundStyle(.secondary)
            .padding(.top, 40)
    }
}

private struct FilterMenu<Content: View>: View {
    let title: String
    let selection: String?
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 4) {
                Text(selection ?? title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(selection == nil ? Color.primary.opacity(0.07) : accent.opacity(0.18), in: Capsule())
            .foregroundStyle(selection == nil ? Color.primary.opacity(0.75) : accent)
        }
    }
}

/// One collection card: reference photo, catalogue number, names.
private struct DexCard: View {
    let species: Species
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(urlString: species.referenceThumbURLString ?? species.referenceImageURLString,
                            symbol: species.realm == .plant ? "leaf.fill" : "pawprint.fill")
                    .frame(height: 124)
                    .frame(maxWidth: .infinity)
                    .clipped()

                DexNumber(number: species.dexNumber, tint: accent, onPhoto: true)
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if species.isNotable {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.treasure)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(7)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(species.displayName)
                    .font(Theme.display(15, weight: .semibold))
                    .lineLimit(1)
                Text(species.scientificName)
                    .font(.caption2).italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let family = species.family {
                    Text(family)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .cardSurface()
    }
}
