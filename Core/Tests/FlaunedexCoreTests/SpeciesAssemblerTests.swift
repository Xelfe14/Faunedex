import Testing
import Foundation
@testable import FlaunedexCore

struct SpeciesAssemblerTests {

    private func gemini(
        scientific: String = "Vanessa atalanta",
        french: String? = "Vulcain (Gemini)",
        english: String? = "Red Admiral (Gemini)",
        family: String? = "Nymphalidae (Gemini)",
        realm: String? = "animal",
        animalGroup: String? = "insect",
        months: [Int]? = [5, 6, 7],
        toxicity: String? = nil
    ) -> GeminiIdentification {
        GeminiIdentification(
            identified: true, confidenceRaw: "high", scientificName: scientific,
            frenchName: french, englishName: english, family: family,
            realmRaw: realm, animalGroupRaw: animalGroup,
            specificiteFR: "Papillon commun des jardins.",
            funFactFR: "Migre depuis l'Afrique du Nord.",
            seasonMonths: months, toxicityDangerFR: toxicity,
            similarSpecies: nil, candidates: nil, reasoning: nil
        )
    }

    @Test func namePrecedenceWikidataWins() {
        let taxon = TaxonMatch(speciesKey: 1898286, canonicalName: "Vanessa atalanta",
                               kingdom: "Animalia", phylum: "Arthropoda", taxonClass: "Insecta",
                               family: "Nymphalidae")
        let wikidata = WikidataClient.Result(
            names: VernacularNames(french: "Vulcain", english: "Red Admiral"),
            iucnCategory: "LC"
        )
        let record = SpeciesAssembler.assemble(
            taxon: taxon, gemini: gemini(), distribution: DistributionResult(rangeCountries: ["FR", "IT"]),
            wikidata: wikidata
        )
        #expect(record.frenchName == "Vulcain", "Wikidata name beats Gemini")
        #expect(record.englishName == "Red Admiral")
        #expect(record.family == "Nymphalidae", "GBIF family is authoritative")
        #expect(record.realm == .animal)
        #expect(record.animalGroup == .insect)
        #expect(record.rangeCountries == ["FR", "IT"])
        #expect(record.conservation?.displayCategory == "LC")
    }

    @Test func fallsBackToGeminiNamesWhenNoWikidata() {
        let taxon = TaxonMatch(speciesKey: 1, canonicalName: "Vanessa atalanta",
                               kingdom: "Animalia", phylum: "Arthropoda", taxonClass: "Insecta")
        let record = SpeciesAssembler.assemble(
            taxon: taxon, gemini: gemini(), distribution: DistributionResult(rangeCountries: [])
        )
        #expect(record.frenchName == "Vulcain (Gemini)")
    }

    @Test func fishTaxonWithNullClassClassifiesAsFish() {
        let salmo = TaxonMatch(speciesKey: 2, canonicalName: "Salmo trutta",
                               kingdom: "Animalia", phylum: "Chordata", taxonClass: nil)
        let record = SpeciesAssembler.assemble(
            taxon: salmo, gemini: gemini(scientific: "Salmo trutta", animalGroup: "fish"),
            distribution: DistributionResult(rangeCountries: ["FR"])
        )
        #expect(record.animalGroup == .fish)
    }

    @Test func geminiHintUsedWhenTaxonomyIsOther() {
        // Malacostraca (a crustacean) isn't a named group → classifier says .other.
        let crab = TaxonMatch(speciesKey: 3, canonicalName: "Some crab",
                              kingdom: "Animalia", phylum: "Arthropoda", taxonClass: "Malacostraca")
        let record = SpeciesAssembler.assemble(
            taxon: crab, gemini: gemini(scientific: "Some crab", animalGroup: "other"),
            distribution: DistributionResult(rangeCountries: [])
        )
        #expect(record.animalGroup == .other)
    }

    @Test func wikipediaLinkAndImageCaptured() {
        let taxon = TaxonMatch(speciesKey: 4, canonicalName: "Petasites albus", kingdom: "Plantae")
        let wiki = WikipediaResult(
            title: "Petasites albus",
            englishPageURL: URL(string: "https://en.wikipedia.org/wiki/Petasites_albus"),
            frenchTitle: "Pétasite blanc",
            frenchPageURL: URL(string: "https://fr.wikipedia.org/wiki/P%C3%A9tasite_blanc"),
            imageURL: URL(string: "https://upload/orig.jpg"),
            thumbnailURL: URL(string: "https://upload/thumb.jpg"),
            commonsFileTitle: "File:Petasites.jpg"
        )
        let record = SpeciesAssembler.assemble(
            taxon: taxon, gemini: gemini(realm: "plant", animalGroup: nil),
            distribution: DistributionResult(rangeCountries: ["FR"]), wikipedia: wiki
        )
        #expect(record.wikipediaURLString == "https://fr.wikipedia.org/wiki/P%C3%A9tasite_blanc")
        #expect(record.wikipediaTitle == "Pétasite blanc")
        #expect(record.referenceImageURLString == "https://upload/orig.jpg")
        #expect(record.animalGroup == nil, "plants have no animal group")
    }

    @Test func monthsSanitized() {
        let taxon = TaxonMatch(speciesKey: 5, canonicalName: "X", kingdom: "Plantae")
        let record = SpeciesAssembler.assemble(
            taxon: taxon, gemini: gemini(realm: "plant", animalGroup: nil, months: [3, 3, 0, 13, 5]),
            distribution: DistributionResult(rangeCountries: [])
        )
        #expect(record.seasonMonths == [3, 5], "invalid months dropped, deduped, sorted")
    }

    @Test func conservationFromWikidataFallback() {
        let taxon = TaxonMatch(speciesKey: 6, canonicalName: "X", kingdom: "Animalia",
                               phylum: "Chordata", taxonClass: "Aves")
        let wikidata = WikidataClient.Result(names: VernacularNames(french: nil, english: nil), iucnCategory: "NT")
        let record = SpeciesAssembler.assemble(
            taxon: taxon, gemini: gemini(), distribution: DistributionResult(rangeCountries: []),
            wikidata: wikidata
        )
        #expect(record.conservation?.globalCategory == "NT")
        #expect(record.conservation?.source == "Wikidata P141")
        #expect(record.conservation?.isNotable ?? false)
    }
}
