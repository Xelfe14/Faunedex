import Testing
import Foundation
@testable import FlaunedexCore

struct DomainTests {

    @Test func geminiIdentificationLenientDecode() throws {
        // Minimal payload with an out-of-vocabulary confidence value.
        let json = Data(#"{ "identified": false, "confidence": "banana", "realm": "plant" }"#.utf8)
        let id = try JSONDecoder().decode(GeminiIdentification.self, from: json)
        #expect(id.confidence == .low, "unknown confidence degrades to low")
        #expect(id.realm == .plant)
        #expect(id.needsReview, "identified=false must route to review")
        #expect(id.scientificName == nil)
    }

    @Test func needsReviewWhenNoName() throws {
        let json = Data(#"{ "identified": true, "confidence": "high" }"#.utf8)
        let id = try JSONDecoder().decode(GeminiIdentification.self, from: json)
        #expect(id.needsReview, "high confidence but no scientific name is still a review")
    }

    @Test func realmFromKingdom() {
        #expect(Realm(gbifKingdom: "Plantae") == .plant)
        #expect(Realm(gbifKingdom: "animalia") == .animal)
        #expect(Realm(gbifKingdom: "Fungi") == .fungus)
        #expect(Realm(gbifKingdom: "Chromista") == nil)
    }

    @Test func conservationStatus() {
        let vu = ConservationStatus(globalCategory: "LC", europeCategory: "VU", source: "IUCN v4")
        #expect(vu.displayCategory == "VU", "prefer the European assessment")
        #expect(vu.isNotable)

        let lc = ConservationStatus(globalCategory: "LC", europeCategory: nil, source: nil)
        #expect(lc.displayCategory == "LC")
        #expect(!lc.isNotable)
    }

    @Test func attributionRequirement() {
        let cc0 = MediaAttribution(artist: nil, licenseShortName: "CC0", licenseURL: nil, sourcePageURL: nil)
        #expect(!cc0.requiresAttribution)
        let bysa = MediaAttribution(artist: "X", licenseShortName: "CC BY-SA 4.0", licenseURL: nil, sourcePageURL: nil)
        #expect(bysa.requiresAttribution)
        let unknown = MediaAttribution(artist: nil, licenseShortName: nil, licenseURL: nil, sourcePageURL: nil)
        #expect(unknown.requiresAttribution, "unknown license is treated as attribution-required")
    }
}
