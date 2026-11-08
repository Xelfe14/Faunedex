import Foundation

/// The camera's zoom as the observer reads it, 0,5×, 1×, 2×, against the
/// factor the capture device is actually set to.
///
/// The camera opens on the phone's multi-lens device, which changes lens by
/// itself as the zoom passes each lens's own factor (its switch-over). With an
/// ultra-wide lens, that device's factor 1 is the ultra-wide, and what the
/// Camera app calls 1× (the main lens) is at the first switch-over. Without
/// one, factor 1 is the main lens.
public struct CameraZoom: Sendable, Equatable {
    /// The device factor shown as 1×.
    public let mainFactor: Double
    public let minFactor: Double
    public let maxFactor: Double
    /// The zooms offered as buttons, as shown: each lens, and 2×.
    public let presets: [Double]

    /// How far digital zoom goes, as shown, when no lens reaches further:
    /// beyond, it only blurs what is to be identified.
    public static let digitalLimit: Double = 10

    /// - Parameters:
    ///   - minFactor, maxFactor: the device's available zoom factors.
    ///   - switchOverFactors: the factors where the device changes lens.
    ///   - hasUltraWide: whether the device's first lens is an ultra-wide.
    public init(minFactor: Double, maxFactor: Double, switchOverFactors: [Double], hasUltraWide: Bool) {
        let main = hasUltraWide ? (switchOverFactors.first ?? 1) : 1
        let telephotos = switchOverFactors.dropFirst(hasUltraWide ? 1 : 0).map { $0 / main }
        let limit = max(Self.digitalLimit, 2 * (telephotos.max() ?? 1))
        mainFactor = main
        self.minFactor = minFactor
        self.maxFactor = max(minFactor, min(maxFactor, limit * main))

        var presets: [Double] = (hasUltraWide ? [minFactor / main] : []) + [1, 2] + telephotos
        presets = presets.filter { $0 * main >= minFactor - 0.001 && $0 * main <= self.maxFactor + 0.001 }
        var unique: [Double] = []
        for preset in presets.sorted() where !unique.contains(where: { abs($0 - preset) < 0.05 }) {
            unique.append(preset)
        }
        self.presets = unique
    }

    /// The zoom shown for a device factor.
    public func displayed(_ factor: Double) -> Double { factor / mainFactor }

    /// The device factor for a zoom as shown, kept within what the device can do.
    public func factor(forDisplayed zoom: Double) -> Double {
        min(max(zoom * mainFactor, minFactor), maxFactor)
    }

    /// The button a zoom belongs to: the largest preset at or below it, which
    /// then shows the zoom itself ("1,4×").
    public func activePreset(for displayed: Double) -> Double? {
        presets.last { $0 <= displayed + 0.01 } ?? presets.first
    }

    /// "0,5", "1", "2", "3,4": a zoom to one decimal, the French way.
    public static func label(_ displayed: Double) -> String {
        let tenths = Int((displayed * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10),\(tenths % 10)"
    }
}
