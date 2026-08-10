import Foundation

/// The top-level biological kingdom bucket the app organizes species into.
/// Derived from GBIF `kingdom`, but kept deliberately small — the app only
/// splits its UI into Faune (animals) and Flore (plants); fungi are tolerated
/// so an accidental mushroom scan doesn't crash the pipeline.
public enum Realm: String, Codable, Sendable, CaseIterable {
    case plant
    case animal
    case fungus

    /// Maps a GBIF `kingdom` string to a realm. Returns nil for kingdoms the
    /// app doesn't model (Chromista, Bacteria, …) so callers can reject them.
    public init?(gbifKingdom kingdom: String) {
        switch kingdom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "plantae": self = .plant
        case "animalia": self = .animal
        case "fungi": self = .fungus
        default: return nil
        }
    }

    /// French display label used in the UI.
    public var frenchLabel: String {
        switch self {
        case .plant: return "Flore"
        case .animal: return "Faune"
        case .fungus: return "Champignons"
        }
    }
}
