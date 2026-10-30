import SwiftUI
import SwiftData
import MapKit
import AVFoundation
import UIKit
import FlaunedexCore

/// The species card — reference image + the user's own photos, the French
/// "spécificité" and "fun fact", rarity/toxicity, season, the range countries
/// (with a "vu ici / vu ailleurs" distinction), a mini-map of sightings, a
/// Wikipedia link, and an optional bird song. All reused media shows attribution.
struct SpeciesDetailView: View {
    let species: Species
    @State private var audioPlayer: AVPlayer?
    @Environment(SpeciesChatStore.self) private var chat

    private var accent: Color { Theme.accent(for: species.realm) }
    private var sightings: [Sighting] {
        (species.sightings ?? []).sorted { $0.capturedAt > $1.capturedAt }
    }
    private var seenCountries: Set<String> {
        Set(sightings.compactMap { $0.countryISO?.uppercased() })
    }
    private var monthsLabel: String? {
        guard !species.seasonMonths.isEmpty else { return nil }
        let names = DateFormatter().standaloneMonthSymbols ?? []
        guard names.count == 12 else { return nil }
        let labels = species.seasonMonths.compactMap { (1...12).contains($0) ? names[$0 - 1] : nil }
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroImages
                header
                if let tox = species.toxicityDangerFR, !tox.isEmpty { toxicityWarning(tox) }
                if let spec = species.specificiteFR, !spec.isEmpty {
                    infoCard("Spécificité", systemImage: "info.circle.fill", text: spec)
                }
                if let fun = species.funFactFR, !fun.isEmpty {
                    infoCard("Le petit plus", systemImage: "sparkles", text: fun, tint: Theme.treasure)
                }
                highlightsSection
                discussionLink
                if let months = monthsLabel { seasonCard(months) }
                birdSong
                rangeSection
                sightingsSection
                externalLinks
                attribution
            }
            .padding()
        }
        .canvasBackground()
        .navigationTitle(species.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .tint(accent)
    }

    // MARK: The observer's own layer

    /// The passages highlighted in the conversation, kept on the card.
    @ViewBuilder private var highlightsSection: some View {
        if !species.highlights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Mes surlignages", systemImage: "highlighter")
                    .font(Theme.display(16))
                    .foregroundStyle(accent)
                ForEach(species.highlights) { highlight in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.yellow.opacity(0.8))
                            .frame(width: 4)
                        Text(highlight.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = highlight.text
                        } label: {
                            Label("Copier", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            chat.removeHighlight(highlight, from: species)
                        } label: {
                            Label("Retirer de la fiche", systemImage: "trash")
                        }
                    }
                }
                Text("Appui long sur un passage pour le copier ou le retirer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardSurface(radius: Theme.tileRadius)
        }
    }

    private var discussionSummary: String {
        let questions = species.chat.filter { $0.role == .user }.count
        if questions == 0 { return "Sur cette espèce ou sur votre photo, à Gemini" }
        return questions == 1 ? "1 question posée" : "\(questions) questions posées"
    }

    /// The conversation about this species, to pick up where it was left.
    private var discussionLink: some View {
        NavigationLink {
            SpeciesChatView(species: species)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(species.chat.isEmpty ? "Poser une question" : "Reprendre la discussion")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(discussionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .cardSurface(radius: Theme.tileRadius)
        }
        .buttonStyle(.plain)
    }

    // MARK: Hero

    private var heroImages: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                photoTile(label: "Photo de référence") {
                    RemoteImage(urlString: species.referenceImageURLString,
                                symbol: species.realm == .plant ? "leaf.fill" : "pawprint.fill")
                }
                ForEach(sightings) { sighting in
                    photoTile(label: "Votre photo — \(sighting.capturedAt.formatted(date: .abbreviated, time: .omitted))") {
                        SightingPhoto(relativePath: sighting.photoRelativePath)
                    }
                }
            }
        }
    }

    private func photoTile<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
                .frame(width: 268, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DexNumber(number: species.dexNumber, tint: accent)
                if species.isNotable {
                    Label("Rare", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.treasure.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.treasure)
                }
            }
            Text(species.displayName).font(Theme.display(26))
            if let en = species.englishName {
                Text(en).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(species.scientificName).italic().font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                if let family = species.family {
                    Chip(text: family, systemImage: "rectangle.3.group", tint: accent)
                }
                if let group = species.animalGroup {
                    Chip(text: group.frenchLabel, systemImage: "pawprint", tint: accent)
                }
            }
            if let badge = species.conservationBadge {
                ConservationBadge(category: badge)
            }
        }
    }

    private func toxicityWarning(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Prudence", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold()).foregroundStyle(.orange)
            Text(text).font(.subheadline)
            Text("Ne vous fiez jamais à cette seule identification pour manipuler ou consommer une espèce.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
    }

    private func infoCard(_ title: String, systemImage: String, text: String,
                          tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(Theme.display(16))
                .foregroundStyle(tint ?? accent)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(radius: Theme.tileRadius)
    }

    private func seasonCard(_ months: String) -> some View {
        HStack {
            Label("Saison", systemImage: "calendar").font(.subheadline.weight(.semibold))
            Spacer()
            Text(months).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
        .cardSurface(radius: Theme.tileRadius)
    }

    // MARK: Bird song

    @ViewBuilder private var birdSong: some View {
        if let audio = species.audioURLString, let url = URL(string: audio) {
            Button {
                let player = AVPlayer(url: url)
                audioPlayer = player
                player.play()
            } label: {
                Label("Écouter le chant", systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: Range

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Aire de répartition", systemImage: "globe.europe.africa.fill")
                .font(Theme.display(16)).foregroundStyle(accent)
            if species.rangeCountries.isEmpty {
                Text("Répartition en cours de chargement…")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6, alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(species.rangeCountries, id: \.self) { code in
                        CountryChip(
                            name: EuropeanCountries.frenchName(for: code),
                            seenHere: seenCountries.contains(code.uppercased()),
                            introduced: species.introducedCountries.contains(code.uppercased()),
                            accent: accent
                        )
                    }
                }
                Text("● vu ici    ○ présent, vu ailleurs")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(radius: Theme.tileRadius)
    }

    // MARK: Sightings + map

    @ViewBuilder private var sightingsSection: some View {
        if !sightings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Vos observations", systemImage: "mappin.and.ellipse")
                    .font(Theme.display(16)).foregroundStyle(accent)
                Map {
                    ForEach(sightings) { s in
                        Marker(s.capturedAt.formatted(date: .abbreviated, time: .omitted),
                               coordinate: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude))
                            .tint(accent)
                    }
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                .allowsHitTesting(false)
            }
            .padding(14)
            .cardSurface(radius: Theme.tileRadius)
        }
    }

    @ViewBuilder private var externalLinks: some View {
        if let url = species.wikipediaURL {
            Link(destination: url) {
                Label("En savoir plus sur Wikipédia", systemImage: "safari.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 4) {
            AttributionLabel(prefix: "Image", artist: species.imageArtist,
                             licenseShort: species.imageLicenseShort,
                             licenseURLString: species.imageLicenseURL,
                             sourcePageURLString: species.imageSourcePageURL)
            if species.audioURLString != nil {
                AttributionLabel(prefix: "Chant", artist: species.audioRecordist,
                                 licenseShort: species.audioCatalogNumber,
                                 licenseURLString: species.audioLicenseURL,
                                 sourcePageURLString: species.audioSourcePageURL)
            }
            Text("Taxonomie et répartition : GBIF · Noms : Wikidata")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

// MARK: - Small pieces

private struct CountryChip: View {
    let name: String
    let seenHere: Bool
    let introduced: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: seenHere ? "circle.fill" : "circle")
                .font(.system(size: 7))
            Text(name).lineLimit(1)
            if introduced {
                Image(systemName: "arrow.down.right.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(seenHere ? accent.opacity(0.20) : Color.primary.opacity(0.06), in: Capsule())
        .foregroundStyle(seenHere ? accent : Color.primary.opacity(0.7))
    }
}

/// Loads a captured photo from disk for display.
private struct SightingPhoto: View {
    let relativePath: String
    private let store = PhotoStore()

    var body: some View {
        if let data = store.load(relativePath), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Theme.brand.opacity(0.08)
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
    }
}
