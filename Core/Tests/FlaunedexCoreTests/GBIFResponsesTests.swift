import Testing
import Foundation
@testable import FlaunedexCore

struct GBIFResponsesTests {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    @Test func parseAcceptedMatch() throws {
        let json = """
        {
          "usageKey": 1340503, "scientificName": "Bombus terrestris (Linnaeus, 1758)",
          "canonicalName": "Bombus terrestris", "rank": "SPECIES", "status": "ACCEPTED",
          "confidence": 99, "matchType": "EXACT",
          "kingdom": "Animalia", "phylum": "Arthropoda", "class": "Insecta",
          "order": "Hymenoptera", "family": "Apidae", "speciesKey": 1340503
        }
        """
        let parsed = try GBIFResponses.parseMatch(data(json))
        let match = try #require(parsed)
        #expect(match.speciesKey == 1340503)
        #expect(match.canonicalName == "Bombus terrestris")
        #expect(match.family == "Apidae")
        #expect(match.taxonClass == "Insecta")
        #expect(match.realm == .animal)
        #expect(match.isTrustworthy())
    }

    @Test func synonymPrefersAcceptedKey() throws {
        let json = """
        {
          "usageKey": 5555, "acceptedUsageKey": 9999, "canonicalName": "Old name",
          "species": "Accepted name", "rank": "SPECIES", "status": "SYNONYM",
          "confidence": 97, "matchType": "EXACT", "kingdom": "Plantae", "family": "Asteraceae"
        }
        """
        let parsed = try GBIFResponses.parseMatch(data(json))
        let match = try #require(parsed)
        #expect(match.speciesKey == 9999, "should collapse to the species/accepted key")
        #expect(match.canonicalName == "Accepted name")
        #expect(match.realm == .plant)
    }

    @Test func noneMatchIsNil() throws {
        let json = #"{ "matchType": "NONE", "confidence": 0, "synonym": false }"#
        let parsed = try GBIFResponses.parseMatch(data(json))
        #expect(parsed == nil)
    }

    @Test func lowConfidenceFuzzyMatchFlaggedUntrustworthy() throws {
        let json = """
        { "usageKey": 42, "canonicalName": "Something", "matchType": "FUZZY", "confidence": 60,
          "kingdom": "Animalia" }
        """
        let parsed = try GBIFResponses.parseMatch(data(json))
        let match = try #require(parsed)
        #expect(!match.isTrustworthy(), "confidence 60 < 90 should be rejected")
    }

    @Test func parseCountryFacet() throws {
        let json = """
        {
          "count": 12345,
          "facets": [
            { "field": "COUNTRY", "counts": [
                { "name": "FR", "count": 900 },
                { "name": "de", "count": 500 },
                { "name": "US", "count": 3 }
            ] }
          ]
        }
        """
        let facet = try GBIFResponses.parseCountryFacet(data(json))
        #expect(facet.count == 3)
        #expect(facet[0] == .init(code: "FR", count: 900))
        #expect(facet[1].code == "DE")  // upper-cased
    }

    @Test func parseDistributionsKeepsOnlyCleanCountryCodes() throws {
        let json = """
        {
          "results": [
            { "country": "FR", "establishmentMeans": "NATIVE" },
            { "country": "ES", "establishmentMeans": "INTRODUCED" },
            { "locationId": "TDWG:GER", "locality": "Germany", "establishmentMeans": "NATIVE" },
            { "establishmentMeans": "NATIVE" }
          ]
        }
        """
        let rows = try GBIFResponses.parseDistributions(data(json))
        #expect(rows.count == 2)
        #expect(rows.map(\.country) == ["FR", "ES"])
        #expect(rows[0].establishmentMeans == "NATIVE")
    }

    @Test func parseVernacular() throws {
        let json = """
        {
          "results": [
            { "vernacularName": "Buff-tailed bumblebee", "language": "eng" },
            { "vernacularName": "Bourdon terrestre", "language": "fra" },
            { "vernacularName": "Erdhummel", "language": "deu" }
          ]
        }
        """
        let names = try GBIFResponses.parseVernacular(data(json))
        #expect(names.french == "Bourdon terrestre")
        #expect(names.english == "Buff-tailed bumblebee")
    }
}
