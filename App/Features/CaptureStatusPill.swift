import SwiftUI
import UIKit
import FlaunedexCore

/// Follows the photo just taken, from "identification en cours" to its result,
/// floating above the tab bar of whichever app is on screen. The capture
/// screen hands over to it as soon as the photo is saved, so nobody waits on
/// the camera.
struct CaptureStatusPill: View {
    @Environment(ScanCoordinator.self) private var scan
    @Environment(Connectivity.self) private var connectivity
    @Environment(APIKeys.self) private var keys

    @State private var openedSpecies: Species?
    @State private var reviewing: Sighting?

    private let store = PhotoStore()

    var body: some View {
        // A VStack, not a Group: the sheets below must stay attached to
        // something once the pill itself has gone.
        VStack(spacing: 0) {
            if let sighting = scan.lastCapture, !scan.cameraOnScreen {
                pill(for: sighting)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // Once identified, it stays long enough to be read and tapped.
                    .task(id: sighting.statusRaw) {
                        guard sighting.status == .complete else { return }
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        guard !Task.isCancelled, scan.lastCapture === sighting else { return }
                        withAnimation { scan.lastCapture = nil }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: scan.lastCapture?.id)
        .sheet(item: $openedSpecies, onDismiss: { scan.lastCapture = nil }) { species in
            NavigationStack {
                SpeciesDetailView(species: species)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fermer") { openedSpecies = nil }
                        }
                    }
            }
        }
        .sheet(item: $reviewing, onDismiss: { scan.lastCapture = nil }) { ReviewSheet(sighting: $0) }
    }

    private func pill(for sighting: Sighting) -> some View {
        let state = PillState(sighting: sighting, online: connectivity.isOnline, hasKey: keys.hasGeminiKey)
        return HStack(spacing: 10) {
            thumbnail(sighting)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            switch state {
            case .identifying:
                ProgressView()
            case .identified(let species, _):
                Button("Voir") { openedSpecies = species }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent(for: species.realm))
            case .needsReview, .failed:
                Button(state.isFailure ? "Réessayer" : "Choisir") { reviewing = sighting }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            case .waiting:
                EmptyView()
            }
            Button {
                withAnimation { scan.lastCapture = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Masquer")
        }
        .controlSize(.small)
        .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 12)
    }

    private func thumbnail(_ sighting: Sighting) -> some View {
        Group {
            if let data = store.load(sighting.photoRelativePath), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Theme.brand.opacity(0.12)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// What the pill says about one sighting.
    private enum PillState {
        case identifying
        case waiting(String)
        case identified(Species, located: Bool)
        case needsReview
        case failed

        init(sighting: Sighting, online: Bool, hasKey: Bool) {
            switch sighting.status {
            case .complete:
                if let species = sighting.species {
                    self = .identified(species, located: sighting.hasCoordinate)
                } else {
                    self = .failed
                }
            case .needsReview: self = .needsReview
            case .failed: self = .failed
            case .pendingIdentification, .pendingGeocoding:
                if !hasKey {
                    self = .waiting("Ajoutez votre clé Gemini dans Réglages")
                } else if !online {
                    self = .waiting("Identifiée au retour du réseau")
                } else {
                    self = .identifying
                }
            }
        }

        var title: String {
            switch self {
            case .identifying: return "Identification en cours…"
            case .waiting: return "Photo enregistrée"
            case .identified(let species, _): return species.displayName
            case .needsReview: return "À vérifier"
            case .failed: return "Identification impossible"
            }
        }

        var detail: String {
            switch self {
            case .identifying: return "Vous pouvez continuer, le résultat s'affichera ici"
            case .waiting(let reason): return reason
            case .identified(_, let located):
                return located ? "Identifiée et placée sur la carte" : "Identifiée · position en attente"
            case .needsReview: return "Plusieurs espèces possibles"
            case .failed: return "Vérifiez la connexion, puis réessayez"
            }
        }

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }
}
