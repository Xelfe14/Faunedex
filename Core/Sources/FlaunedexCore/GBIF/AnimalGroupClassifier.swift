import Foundation

/// Resolves an `AnimalGroup` from a GBIF taxon, encoding the backbone's quirks
/// explicitly rather than trusting the raw `class` string.
///
/// Two quirks drive the design (both covered by tests):
///   1. **No `Reptilia`.** GBIF splits reptiles into `Squamata`, `Testudines`,
///      `Crocodylia`, `Rhynchocephalia` — these live at the *class* rank in the
///      match response, so they're matched here.
///   2. **Null `class` for many fish.** Bony fish such as *Salmo trutta* come
///      back with no `class`. When `phylum == Chordata` and the animal is not a
///      recognized tetrapod, we fall back to `.fish`.
public enum AnimalGroupClassifier {

    private static let birdClasses: Set<String> = ["aves"]
    private static let mammalClasses: Set<String> = ["mammalia"]
    private static let amphibianClasses: Set<String> = ["amphibia"]
    private static let insectClasses: Set<String> = ["insecta"]
    private static let arachnidClasses: Set<String> = ["arachnida"]

    /// Reptile "classes" as GBIF actually exposes them (there is no Reptilia).
    private static let reptileClasses: Set<String> = [
        "reptilia", "squamata", "testudines", "crocodylia", "rhynchocephalia", "sphenodontia",
    ]

    /// The many class strings GBIF uses for fishes across its backbone.
    private static let fishClasses: Set<String> = [
        "actinopterygii", "teleostei", "elasmobranchii", "chondrichthyes", "holocephali",
        "myxini", "petromyzonti", "hyperoartia", "coelacanthi", "dipneusti", "cladistia",
        "leptocardii", "sarcopterygii", "actinopteri", "cephalaspidomorphi",
    ]

    private static let molluskPhyla: Set<String> = ["mollusca"]
    private static let arthropodPhyla: Set<String> = ["arthropoda"]

    /// Tetrapod class tokens used by the fish fallback to avoid mislabeling a
    /// land vertebrate whose `class` we simply didn't recognize.
    private static let tetrapodClasses: Set<String> =
        birdClasses.union(mammalClasses).union(amphibianClasses).union(reptileClasses)

    /// Classify from the taxon's `class` and `phylum` (both optional).
    public static func classify(taxonClass: String?, phylum: String?) -> AnimalGroup {
        let cls = taxonClass?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let phy = phylum?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let cls, !cls.isEmpty {
            if birdClasses.contains(cls) { return .bird }
            if mammalClasses.contains(cls) { return .mammal }
            if reptileClasses.contains(cls) { return .reptile }
            if amphibianClasses.contains(cls) { return .amphibian }
            if fishClasses.contains(cls) { return .fish }
            if insectClasses.contains(cls) { return .insect }
            if arachnidClasses.contains(cls) { return .arachnid }
        }

        // Phylum-level fallbacks for when `class` is null/unrecognized.
        if let phy, !phy.isEmpty {
            if molluskPhyla.contains(phy) { return .mollusk }
            // Chordata + not a known tetrapod ⇒ almost certainly a fish
            // (GBIF routinely leaves `class` null for bony fish).
            if phy == "chordata" {
                if let cls, tetrapodClasses.contains(cls) {
                    // handled above; unreachable, but keeps intent explicit
                    return .other
                }
                return .fish
            }
            // Arthropoda without insect/arachnid class → other arthropod.
            if arthropodPhyla.contains(phy) { return .other }
        }

        return .other
    }

    /// Convenience overload taking a `TaxonMatch`.
    public static func classify(_ taxon: TaxonMatch) -> AnimalGroup {
        classify(taxonClass: taxon.taxonClass, phylum: taxon.phylum)
    }
}
