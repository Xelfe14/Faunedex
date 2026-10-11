import SwiftUI
import UIKit
import FlaunedexCore

// MARK: - Turning a card over

/// A card with two faces that turns over in 3D.
///
/// Each face reads the rotation angle frame by frame (see `FlipFace`) and hides
/// itself once past 90°, so the viewer never sees a mirrored face through the
/// card: exactly what a real card does.
struct FlipCard<Front: View, Back: View>: View {
    let flipped: Bool
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back

    var body: some View {
        ZStack {
            front().modifier(FlipFace(angle: flipped ? 180 : 0, isBack: false))
            back().modifier(FlipFace(angle: flipped ? 180 : 0, isBack: true))
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: flipped)
    }
}

/// One face of a turning card. Being `Animatable`, it receives every
/// intermediate angle of the animation, not just the start and the end.
struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let showingBack = angle >= 90
        let visible = isBack ? showingBack : !showingBack
        content
            .rotation3DEffect(.degrees(isBack ? angle - 180 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

// MARK: - One face of a knowledge card

/// A card face: a small header naming the side, then the content.
struct KnowledgeCardFace: View {
    let card: KnowledgeCard
    let side: CardSide
    var folder: KnowledgeFolder?
    var onTap: (() -> Void)?

    @Environment(KnowledgeStore.self) private var store

    private var tint: Color { folder.map { Theme.folder($0.color) } ?? Theme.knowledge }

    var body: some View {
        let document = card.document(for: side)
        VStack(spacing: 0) {
            HStack {
                Text(side.frenchLabel.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())
                Spacer()
                if let folder {
                    Text(folder.emoji).font(.system(size: 18))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
            // Taps on the text are handled inside the text view (so links can
            // open); this covers only the header strip. One handler per area,
            // or a single tap would turn the card twice.
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }

            ZStack {
                if document.isBlank {
                    Text("Face vide")
                        .font(.subheadline).foregroundStyle(.tertiary)
                }
                RichTextDisplay(document: document, style: displayStyle(for: document), onTap: onTap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    // The back is faintly tinted, so a glance tells the sides apart.
                    if side == .verso {
                        RoundedRectangle(cornerRadius: 26, style: .continuous).fill(tint.opacity(0.06))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        }
    }

    private func displayStyle(for document: RichDocument) -> RichTextStyle {
        let short = document.isShort && !document.hasImages
        return RichTextStyle(
            baseSize: short ? 26 : 18,
            centered: short,
            accent: UIColor(tint),
            availableWidth: 300,
            maxImageHeight: 260,
            imageProvider: { [weak store] id in store?.image(for: id, in: card) }
        )
    }
}

// MARK: - Celebration

/// A short burst of confetti, fired each time `trigger` changes.
struct ConfettiBurst: View {
    let trigger: Int
    @State private var pieces: [Piece] = []

    struct Piece: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: CGFloat
        let symbol: String
        let color: Color
        let spin: Double
        let size: CGFloat
    }

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                ConfettiPiece(piece: piece)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        let colors: [Color] = [Theme.treasure, Theme.knowledge, .pink, .green, .orange, .purple, .teal]
        let symbols = ["circle.fill", "star.fill", "sparkle", "rectangle.fill", "diamond.fill", "triangle.fill"]
        let burst = (0..<30).map { _ in
            Piece(angle: .random(in: 0..<(2 * .pi)), distance: .random(in: 80...210),
                  symbol: symbols.randomElement()!, color: colors.randomElement()!,
                  spin: .random(in: -540...540), size: .random(in: 7...13))
        }
        pieces.append(contentsOf: burst)
        let ids = Set(burst.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            pieces.removeAll { ids.contains($0.id) }
        }
    }
}

private struct ConfettiPiece: View {
    let piece: ConfettiBurst.Piece
    @State private var launched = false

    var body: some View {
        Image(systemName: piece.symbol)
            .font(.system(size: piece.size, weight: .bold))
            .foregroundStyle(piece.color)
            .rotationEffect(.degrees(launched ? piece.spin : 0))
            // Out along the angle, then a little further down: a hint of gravity.
            .offset(x: launched ? cos(piece.angle) * piece.distance : 0,
                    y: launched ? sin(piece.angle) * piece.distance + 70 : 0)
            .opacity(launched ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) { launched = true }
            }
    }
}

// MARK: - Small pieces

/// A folder's emoji on a tile of its colour.
struct FolderBadge: View {
    let emoji: String
    let color: FolderColor
    var size: CGFloat = 40

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(Theme.folder(color).opacity(0.18),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// "38 à réviser · 6 au repos · 2 retirées", as little capsules.
struct DeckStatusPills: View {
    let status: DeckStatus

    var body: some View {
        FlowRow(spacing: 6) {
            pill("\(status.dealable) à réviser", "rectangle.stack.fill", Theme.knowledge)
            if status.resting > 0 {
                pill("\(status.resting) au repos", "moon.zzz.fill", Theme.treasure)
            }
            if status.retired > 0 {
                pill("\(status.retired) retirée\(status.retired > 1 ? "s" : "")", "archivebox.fill", .gray)
            }
        }
    }

    /// An HStack rather than a Label: inside a List, SwiftUI gives every Label
    /// icon a fixed-width column for alignment, which opens a wide gap here.
    private func pill(_ text: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Where a card stands, in a word: resting, retired, back for confirmation.
struct CardStateBadge: View {
    let card: KnowledgeCard

    var body: some View {
        if card.isRetired {
            badge("Retirée", "archivebox.fill", .gray)
        } else if card.isResting(), let until = card.restUntil {
            badge("Au repos · \(until.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))",
                  "moon.zzz.fill", Theme.treasure)
        } else if card.masteryLevel > 0 {
            badge("À confirmer", "checkmark.seal", .green)
        }
    }

    private func badge(_ text: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
        }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// One card in a list: the start of each side, and its state.
struct KnowledgeCardRow: View {
    let card: KnowledgeCard
    var folderPath: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                let recto = card.previewText(for: .recto)
                let verso = card.previewText(for: .verso)
                Text(recto.isEmpty ? (card.hasImages ? "Image" : "Recto vide") : recto)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(recto.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                Text(verso.isEmpty ? "Verso vide" : verso)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let folderPath {
                    Label(folderPath, systemImage: "folder")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                CardStateBadge(card: card)
                if card.hasImages {
                    Image(systemName: "photo").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(card.isRetired ? 0.55 : 1)
    }
}
