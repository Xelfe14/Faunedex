import Testing
import Foundation
@testable import FlaunedexCore

struct NearbyServiceTests {

    private func data(_ s: String) -> Data { Data(s.utf8) }
    private func facet(_ pairs: [(String, Int)]) -> [GBIFResponses.CountryCount] {
        pairs.map { GBIFResponses.CountryCount(code: $0.0, count: $0.1) }
    }

    // MARK: Ranking

    @Test func ranksByOccurrenceAndDropsCollected() {
        let ranked = NearbyService.rank(
            facet: facet([("111", 50), ("222", 900), ("333", 300)]),
            excluding: [222],
            limit: 10
        )
        #expect(ranked.map(\.key) == [333, 111], "collected species removed, rest sorted by count")
    }

    @Test func respectsLimit() {
        let ranked = NearbyService.rank(
            facet: facet([("1", 10), ("2", 9), ("3", 8), ("4", 7)]),
            excluding: [], limit: 2
        )
        #expect(ranked.count == 2)
        #expect(ranked.map(\.key) == [1, 2])
    }

    @Test func ignoresNonNumericFacetKeys() {
        let ranked = NearbyService.rank(
            facet: facet([("abc", 999), ("42", 5)]),
            excluding: [], limit: 10
        )
        #expect(ranked.map(\.key) == [42])
    }

    @Test func everythingCollectedYieldsNothing() {
        let ranked = NearbyService.rank(
            facet: facet([("1", 10), ("2", 9)]), excluding: [1, 2], limit: 10
        )
        #expect(ranked.isEmpty)
    }

    // MARK: Season window

    @Test func seasonWindowClampsAtYearEnds() {
        #expect(NearbyEndpoints.seasonWindow(around: 6) == 5...7)
        #expect(NearbyEndpoints.seasonWindow(around: 1) == 1...2, "January must not underflow")
        #expect(NearbyEndpoints.seasonWindow(around: 12) == 11...12, "December must not overflow")
        #expect(NearbyEndpoints.seasonWindow(around: 99) == 11...12, "out-of-range month is clamped")
    }

    // MARK: URL construction

    @Test func facetURLCarriesGeoDistanceMonthAndKingdom() {
        let url = NearbyEndpoints.speciesFacet(
            latitude: 45.9237, longitude: 6.8694, radiusKm: 25,
            months: 5...7, realm: .plant
        )
        let s = url.absoluteString
        #expect(s.contains("occurrence/search"))
        #expect(s.contains("45.92370") && s.contains("6.86940"), "coordinate is in the geoDistance param")
        #expect(s.contains("25km"))
        #expect(s.contains("month=5,5") == false)
        #expect(s.contains("5%2C7") || s.contains("month=5,7"), "month range passed as min,max")
        #expect(s.contains("kingdomKey=6"), "Plantae kingdom key")
        #expect(s.contains("facet=speciesKey"))
    }

    @Test func kingdomKeysMatchGBIFBackbone() {
        #expect(NearbyEndpoints.kingdomKey(for: .animal) == 1)
        #expect(NearbyEndpoints.kingdomKey(for: .fungus) == 5)
        #expect(NearbyEndpoints.kingdomKey(for: .plant) == 6)
    }

    @Test func speciesDetailURL() {
        #expect(NearbyEndpoints.species(key: 1340503).absoluteString
                == "https://api.gbif.org/v1/species/1340503")
    }

    // MARK: species/{key} parsing

    @Test func parsesSpeciesRecord() throws {
        let json = """
        {
          "key": 5231190, "nubKey": 5231190, "speciesKey": 5231190,
          "canonicalName": "Passer domesticus", "scientificName": "Passer domesticus (Linnaeus, 1758)",
          "rank": "SPECIES", "vernacularName": "House Sparrow",
          "kingdom": "Animalia", "phylum": "Chordata", "class": "Aves",
          "order": "Passeriformes", "family": "Passeridae"
        }
        """
        let parsed = try GBIFResponses.parseSpeciesRecord(data(json))
        let taxon = try #require(parsed)
        #expect(taxon.speciesKey == 5231190)
        #expect(taxon.canonicalName == "Passer domesticus")
        #expect(taxon.vernacularName == "House Sparrow")
        #expect(taxon.family == "Passeridae")
        #expect(taxon.realm == .animal)
        #expect(AnimalGroupClassifier.classify(taxon) == .bird)
    }

    @Test func speciesRecordWithoutUsableNameIsNil() throws {
        let parsed = try GBIFResponses.parseSpeciesRecord(data(#"{ "key": 1 }"#))
        #expect(parsed == nil)
    }
}
