import Foundation

/// The animal sub-group used for the "Faune" filters (Oiseaux, Mammifères, …).
///
/// This is assigned from GBIF taxonomy, never from the raw `class` string alone.
/// GBIF's backbone has quirks the naive mapping gets wrong:
///   - There is **no `Reptilia`** class — reptiles arrive as `Squamata`,
///     `Testudines`, `Crocodylia`, `Rhynchocephalia`.
///   - Many bony fish have a **null `class`** (e.g. *Salmo trutta*), so a
///     `phylum == Chordata` + non-tetrapod fallback is required to catch them.
/// See `AnimalGroupClassifier` for the resolution logic and its tests.
public enum AnimalGroup: String, Codable, Sendable, CaseIterable {
    case mammal
    case bird
    case reptile
    case amphibian
    case fish
    case insect
    case arachnid
    case mollusk
    case other

    /// French plural label used for the sub-group filter chips.
    public var frenchLabel: String {
        switch self {
        case .mammal: return "Mammifères"
        case .bird: return "Oiseaux"
        case .reptile: return "Reptiles"
        case .amphibian: return "Amphibiens"
        case .fish: return "Poissons"
        case .insect: return "Insectes"
        case .arachnid: return "Arachnides"
        case .mollusk: return "Mollusques"
        case .other: return "Autres"
        }
    }
}

/// Confidence buckets returned by the identifier. Kept as an enum so the UI can
/// branch (a `.low` result routes to the candidate-review flow, never a
/// confidently-wrong single answer).
public enum IdentificationConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}
