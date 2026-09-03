import SwiftUI
import FlaunedexCore

/// The app's visual identity — a warm, natural, field-guide palette rather than
/// stock system chrome. Faune leans amber/ochre, Flore leans leaf-green, and
/// both sit on a soft parchment (or deep forest, in dark mode) background.
enum Theme {

    // MARK: Palette

    /// Deep forest green — the brand colour.
    static let brand = Color(light: .init(r: 0.18, g: 0.35, b: 0.20),
                             dark:  .init(r: 0.55, g: 0.78, b: 0.53))
    /// Faune accent (warm ochre).
    static let fauna = Color(light: .init(r: 0.71, g: 0.42, b: 0.20),
                             dark:  .init(r: 0.92, g: 0.66, b: 0.38))
    /// Flore accent (leaf green).
    static let flora = Color(light: .init(r: 0.25, g: 0.49, b: 0.23),
                             dark:  .init(r: 0.55, g: 0.80, b: 0.48))
    /// Page background — warm parchment / deep forest.
    static let canvas = Color(light: .init(r: 0.976, g: 0.969, b: 0.949),
                              dark:  .init(r: 0.055, g: 0.075, b: 0.055))
    /// Raised card surface.
    static let surface = Color(light: .init(r: 1, g: 1, b: 1),
                               dark:  .init(r: 0.11, g: 0.14, b: 0.11))
    /// Rare / notable highlight.
    static let treasure = Color(light: .init(r: 0.80, g: 0.60, b: 0.12),
                                dark:  .init(r: 0.95, g: 0.78, b: 0.30))
    /// Cuisine accent (warm paprika). The cooking section is a different world
    /// inside the same app, so it gets its own colour rather than borrowing
    /// Faune's ochre or Flore's green.
    static let cuisine = Color(light: .init(r: 0.72, g: 0.28, b: 0.18),
                               dark:  .init(r: 0.93, g: 0.52, b: 0.40))

    /// The accent for a realm.
    static func accent(for realm: Realm) -> Color {
        switch realm {
        case .animal: return fauna
        case .plant: return flora
        case .fungus: return Color.brown
        }
    }

    // MARK: Metrics

    static let cardRadius: CGFloat = 18
    static let tileRadius: CGFloat = 14

    // MARK: Type

    /// Display face for titles — rounded gives the friendly field-guide feel.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Helpers

extension Color {
    struct RGB { let r, g, b: Double }

    /// Build a colour that adapts to light/dark mode.
    init(light: RGB, dark: RGB) {
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }
}

// MARK: - Reusable styling

/// A raised card surface used across the dex and detail screens.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
    }
}

extension View {
    func cardSurface(radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardSurface(radius: radius))
    }

    /// Paint the warm page background behind a scrolling screen.
    func canvasBackground() -> some View {
        background(Theme.canvas.ignoresSafeArea())
    }
}

/// The dex catalogue number badge ("N° 007") that gives the collection its
/// Pokédex character.
struct DexNumber: View {
    let number: Int
    var tint: Color = Theme.brand
    /// Use a blurred material backing when the badge sits on top of a photo,
    /// so it stays legible without stacking two visible capsules.
    var onPhoto: Bool = false

    var body: some View {
        Text(String(format: "N° %03d", number))
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(tint)
            .background {
                if onPhoto {
                    Capsule().fill(.ultraThinMaterial)
                } else {
                    Capsule().fill(tint.opacity(0.15))
                }
            }
    }
}
