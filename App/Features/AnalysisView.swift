import SwiftUI
import UIKit
import FlaunedexCore

/// What the shutter opens: the photo just taken, its identification as it
/// happens, then the species and a conversation to ask more about it.
///
/// Also where an uncertain identification is settled, by choosing among the
/// candidates or asking for a deeper look, and where a failed one is retried.
struct AnalysisView: View {
    let sighting: Sighting

    @Environment(ScanCoordinator.self) private var scan
    @Environment(SpeciesChatStore.self) private var chat
    @Environment(Connectivity.self) private var connectivity
    @Environment(APIKeys.self) private var keys
    @Environment(\.dismiss) private var dismiss

    @State private var working = false
    @State private var photo: UIImage?

    private let store = PhotoStore()

    private var identified: Species? {
        sighting.status == .complete ? sighting.species : nil
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        photoHeader
                        if let species = identified {
                            summary(species)
                            ConversationMessages(species: species, sighting: sighting)
                        } else {
                            statusCard
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: identified?.chat.count) { _, _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
                .onChange(of: identified.flatMap { chat.pending[$0.gbifKey] }) { _, _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            .canvasBackground()
            .safeAreaInset(edge: .bottom) {
                if let species = identified {
                    ChatComposer(species: species, sighting: sighting)
                }
            }
            .navigationTitle("Analyse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task(id: sighting.photoRelativePath) {
                photo = store.load(sighting.photoRelativePath).flatMap(UIImage.init(data:))
            }
        }
        .tint(identified.map { Theme.accent(for: $0.realm) } ?? Theme.brand)
    }

    // MARK: Photo

    @ViewBuilder private var photoHeader: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        } else if let species = sighting.species {
            RemoteImage(urlString: species.referenceThumbURLString ?? species.referenceImageURLString,
                        symbol: species.realm == .plant ? "leaf.fill" : "pawprint.fill")
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    // MARK: Before the result

    @ViewBuilder private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch sighting.status {
            case .pendingIdentification, .pendingGeocoding:
                pending
            case .needsReview:
                candidates
            case .failed:
                failed
            case .complete:
                // Complete without a species shouldn't happen; offer a retry.
                failed
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    @ViewBuilder private var pending: some View {
        if !keys.hasGeminiKey {
            Label("Ajoutez votre clé Gemini dans Réglages (la roue dentée en haut à droite) : la photo sera identifiée ensuite.",
                  systemImage: "key.fill")
                .foregroundStyle(.orange)
        } else if !connectivity.isOnline {
            Label("Hors ligne : la photo est enregistrée et sera identifiée au retour du réseau.",
                  systemImage: "wifi.slash")
        } else {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Identification en cours…").font(.headline)
                    Text("Gemini examine la photo, puis l'espèce est complétée (nom, statut, répartition).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var candidates: some View {
        Label("À vérifier", systemImage: "questionmark.circle.fill")
            .font(.headline)
            .foregroundStyle(.orange)
        Text("L'identification n'est pas certaine. Choisissez l'espèce qui correspond, ou demandez une analyse plus poussée.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        let options = scan.candidates(for: sighting)
        ForEach(Array(options.enumerated()), id: \.offset) { _, candidate in
            Button {
                retry(choosing: candidate.scientificName)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.commonNameFR ?? candidate.scientificName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(candidate.scientificName)
                            .font(.caption).italic()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let p = candidate.probability {
                        Text("\(Int(p * 100)) %")
                            .font(.caption.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
        deeperLookButton
    }

    @ViewBuilder private var failed: some View {
        Label("Identification impossible", systemImage: "exclamationmark.triangle.fill")
            .font(.headline)
            .foregroundStyle(.orange)
        Text("Vérifiez la connexion, puis relancez l'analyse.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        deeperLookButton
    }

    private var deeperLookButton: some View {
        Button {
            retry(choosing: nil)
        } label: {
            HStack {
                if working { ProgressView() }
                Label(working ? "Analyse en cours…" : "Analyser à nouveau, plus en profondeur",
                      systemImage: "sparkle.magnifyingglass")
            }
            .font(.subheadline.weight(.semibold))
        }
        .disabled(working || !keys.hasGeminiKey)
    }

    private func retry(choosing scientificName: String?) {
        working = true
        Task {
            await scan.retryIdentification(for: sighting, choosing: scientificName)
            working = false
        }
    }

    // MARK: The result

    private func summary(_ species: Species) -> some View {
        let accent = Theme.accent(for: species.realm)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    DexNumber(number: species.dexNumber, tint: accent)
                    if let badge = species.conservationBadge {
                        ConservationBadge(category: badge, compact: true)
                    }
                }
                Text(species.displayName).font(Theme.display(24))
                Text(species.scientificName).italic().font(.subheadline).foregroundStyle(.secondary)
                if let family = species.family {
                    Chip(text: family, systemImage: "rectangle.3.group", tint: accent)
                        .padding(.top, 2)
                }
            }
            if let danger = species.toxicityDangerFR, !danger.isEmpty {
                Label(danger, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if let text = species.specificiteFR, !text.isEmpty {
                fact("Spécificité", systemImage: "info.circle.fill", text: text, tint: accent)
            }
            if let text = species.funFactFR, !text.isEmpty {
                fact("Le petit plus", systemImage: "sparkles", text: text, tint: Theme.treasure)
            }
            NavigationLink {
                SpeciesDetailView(species: species)
            } label: {
                Label("Voir la fiche complète", systemImage: "book.closed")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    private func fact(_ title: String, systemImage: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
