import Testing
@testable import FlaunedexCore

/// The subgroup classifier is the highest-risk mapping in the app (GBIF's
/// backbone quirks), so every group and every documented edge case is pinned.
struct AnimalGroupClassifierTests {

    @Test func straightforwardClasses() {
        #expect(AnimalGroupClassifier.classify(taxonClass: "Aves", phylum: "Chordata") == .bird)
        #expect(AnimalGroupClassifier.classify(taxonClass: "Mammalia", phylum: "Chordata") == .mammal)
        #expect(AnimalGroupClassifier.classify(taxonClass: "Amphibia", phylum: "Chordata") == .amphibian)
        #expect(AnimalGroupClassifier.classify(taxonClass: "Insecta", phylum: "Arthropoda") == .insect)
        #expect(AnimalGroupClassifier.classify(taxonClass: "Arachnida", phylum: "Arthropoda") == .arachnid)
    }

    @Test func reptilesArriveAsOrders() {
        // GBIF has no Reptilia — reptiles show up as these.
        #expect(AnimalGroupClassifier.classify(taxonClass: "Squamata", phylum: "Chordata") == .reptile)
        #expect(AnimalGroupClassifier.classify(taxonClass: "Testudines", phylum: "Chordata") == .reptile)
        #expect(AnimalGroupClassifier.classify(taxonClass: "Crocodylia", phylum: "Chordata") == .reptile)
    }

    @Test func namedFishClasses() {
        #expect(AnimalGroupClassifier.classify(taxonClass: "Actinopterygii", phylum: "Chordata") == .fish)
        #expect(AnimalGroupClassifier.classify(taxonClass: "Elasmobranchii", phylum: "Chordata") == .fish)
    }

    @Test func fishFallbackWhenClassIsNull() {
        // Salmo trutta: GBIF returns a null class — the Chordata fallback catches it.
        #expect(AnimalGroupClassifier.classify(taxonClass: nil, phylum: "Chordata") == .fish)
        #expect(AnimalGroupClassifier.classify(taxonClass: "", phylum: "Chordata") == .fish)
    }

    @Test func molluskByPhylum() {
        #expect(AnimalGroupClassifier.classify(taxonClass: "Gastropoda", phylum: "Mollusca") == .mollusk)
    }

    @Test func unknownArthropodIsOther() {
        #expect(AnimalGroupClassifier.classify(taxonClass: "Malacostraca", phylum: "Arthropoda") == .other)
    }

    @Test func caseInsensitivity() {
        #expect(AnimalGroupClassifier.classify(taxonClass: "aves", phylum: "chordata") == .bird)
    }

    @Test func unknownIsOther() {
        #expect(AnimalGroupClassifier.classify(taxonClass: nil, phylum: nil) == .other)
        #expect(AnimalGroupClassifier.classify(taxonClass: "Foobar", phylum: "Bazium") == .other)
    }

    @Test func classifyFromTaxonMatch() {
        let salmo = TaxonMatch(speciesKey: 1, canonicalName: "Salmo trutta", phylum: "Chordata", taxonClass: nil)
        #expect(AnimalGroupClassifier.classify(salmo) == .fish)
    }
}
