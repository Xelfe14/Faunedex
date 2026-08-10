import SwiftUI
import UIKit
import FlaunedexCore

/// Async reference image with a themed placeholder.
struct RemoteImage: View {
    let urlString: String?
    var contentMode: ContentMode = .fill
    var symbol: String = "leaf"

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder
                case .empty:
                    ZStack { placeholderBase; ProgressView().tint(Theme.brand) }
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholderBase: some View {
        LinearGradient(colors: [Theme.brand.opacity(0.10), Theme.brand.opacity(0.04)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var placeholder: some View {
        ZStack {
            placeholderBase
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.brand.opacity(0.45))
        }
    }
}

/// A conservation-status chip. Threatened categories read as a "rare find".
struct ConservationBadge: View {
    let category: String
    var compact: Bool = false

    private var frenchLabel: String {
        switch category.uppercased() {
        case "LC": return "Préoccupation mineure"
        case "NT": return "Quasi menacée"
        case "VU": return "Vulnérable"
        case "EN": return "En danger"
        case "CR": return "En danger critique"
        case "EW": return "Éteinte à l'état sauvage"
        case "EX": return "Éteinte"
        case "DD": return "Données insuffisantes"
        default: return category.uppercased()
        }
    }

    private var color: Color {
        switch category.uppercased() {
        case "NT": return Theme.treasure
        case "VU": return .orange
        case "EN", "CR": return .red
        case "EW", "EX": return .purple
        default: return Theme.flora
        }
    }

    var body: some View {
        Label(compact ? category.uppercased() : frenchLabel, systemImage: "shield.lefthalf.filled")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

/// A small pill used for family / group / country facts.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(tint.opacity(0.13), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// Attribution line rendered under any reused media (license compliance).
struct AttributionLabel: View {
    let prefix: String
    let artist: String?
    let licenseShort: String?
    let licenseURLString: String?
    let sourcePageURLString: String?

    var body: some View {
        let parts = [artist, licenseShort].compactMap { $0 }.joined(separator: " · ")
        if !parts.isEmpty || sourcePageURLString != nil {
            HStack(spacing: 4) {
                Text("\(prefix) : \(parts)")
                    .font(.caption2).foregroundStyle(.secondary)
                if let s = sourcePageURLString, let url = URL(string: s) {
                    Link("source", destination: url).font(.caption2)
                }
            }
        }
    }
}

/// The "Nouvelle espèce !" celebration — the Pokédex payoff moment.
struct NewSpeciesCelebration: View {
    let species: Species
    let dismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Theme.treasure.opacity(0.35), lineWidth: 2)
                            .frame(width: appeared ? 190 + CGFloat(i) * 46 : 90)
                            .opacity(appeared ? 0 : 0.9)
                            .animation(.easeOut(duration: 1.4).delay(Double(i) * 0.16), value: appeared)
                    }
                    RemoteImage(urlString: species.referenceThumbURLString ?? species.referenceImageURLString,
                                symbol: species.realm == .plant ? "leaf.fill" : "pawprint.fill")
                        .frame(width: 168, height: 168)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.treasure, lineWidth: 4))
                        .shadow(color: Theme.treasure.opacity(0.5), radius: 22)
                        .scaleEffect(appeared ? 1 : 0.5)
                }
                .frame(height: 240)

                VStack(spacing: 6) {
                    Label("Nouvelle espèce !", systemImage: "sparkles")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.treasure)
                    Text(species.displayName)
                        .font(Theme.display(20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(species.scientificName)
                        .font(.subheadline).italic()
                        .foregroundStyle(.white.opacity(0.75))
                    DexNumber(number: species.dexNumber, tint: Theme.treasure)
                        .padding(.top, 4)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

                Button("Continuer") { dismiss() }
                    .font(.headline)
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(Theme.treasure, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 6)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// A friendlier empty state with the app's own voice.
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.brand.opacity(0.10)).frame(width: 108, height: 108)
                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Theme.brand)
            }
            Text(title).font(Theme.display(19))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
