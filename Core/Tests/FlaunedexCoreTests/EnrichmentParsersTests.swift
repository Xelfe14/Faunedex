import Testing
import Foundation
@testable import FlaunedexCore

struct EnrichmentParsersTests {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: Wikipedia

    @Test func wikipediaParseImageAndFrenchLink() throws {
        let json = """
        {
          "query": { "pages": [ {
            "pageid": 123, "title": "Petasites albus",
            "fullurl": "https://en.wikipedia.org/wiki/Petasites_albus",
            "pageimage": "Petasites_albus_002.jpg",
            "original": { "source": "https://upload.wikimedia.org/orig.jpg" },
            "thumbnail": { "source": "https://upload.wikimedia.org/thumb.jpg" },
            "langlinks": [ { "lang": "fr", "title": "Pétasite blanc",
                             "url": "https://fr.wikipedia.org/wiki/P%C3%A9tasite_blanc" } ]
          } ] }
        }
        """
        let parsed = try WikipediaClient.parse(data(json))
        let result = try #require(parsed)
        #expect(result.imageURL?.absoluteString == "https://upload.wikimedia.org/orig.jpg")
        #expect(result.thumbnailURL?.absoluteString == "https://upload.wikimedia.org/thumb.jpg")
        #expect(result.commonsFileTitle == "File:Petasites_albus_002.jpg")
        #expect(result.frenchTitle == "Pétasite blanc")
        #expect(result.frenchPageURL?.absoluteString == "https://fr.wikipedia.org/wiki/P%C3%A9tasite_blanc")
        #expect(result.preferredArticleURL == result.frenchPageURL)
    }

    @Test func wikipediaFallsBackToEnglishWhenNoFrenchLink() throws {
        let json = """
        { "query": { "pages": [ {
            "title": "Some species", "fullurl": "https://en.wikipedia.org/wiki/Some_species"
        } ] } }
        """
        let parsed = try WikipediaClient.parse(data(json))
        let result = try #require(parsed)
        #expect(result.frenchPageURL == nil)
        #expect(result.preferredArticleURL?.absoluteString == "https://en.wikipedia.org/wiki/Some_species")
    }

    @Test func wikipediaMissingPageReturnsNil() throws {
        let json = #"{ "query": { "pages": [ { "title": "Nope", "missing": true } ] } }"#
        let parsed = try WikipediaClient.parse(data(json))
        #expect(parsed == nil)
    }

    @Test func wikipediaLookupURLEncodesName() {
        let url = WikipediaClient.lookupURL(scientificName: "Hepatica nobilis")
        #expect(url.absoluteString.contains("titles=Hepatica%20nobilis")
                || url.absoluteString.contains("titles=Hepatica+nobilis"))
        #expect(url.absoluteString.contains("lllang=fr"))
    }

    // MARK: Commons

    @Test func commonsParseAttribution() throws {
        let json = """
        {
          "query": { "pages": [ {
            "imageinfo": [ {
              "url": "https://upload.wikimedia.org/file.jpg",
              "descriptionurl": "https://commons.wikimedia.org/wiki/File:File.jpg",
              "user": "Uploader",
              "extmetadata": {
                "Artist": { "value": "<a href=\\"x\\">Jane Doe</a>" },
                "LicenseShortName": { "value": "CC BY-SA 4.0" },
                "LicenseUrl": { "value": "https://creativecommons.org/licenses/by-sa/4.0" },
                "AttributionRequired": { "value": "true" }
              }
            } ]
          } ] }
        }
        """
        let parsed = try CommonsClient.parse(data(json))
        let attr = try #require(parsed)
        #expect(attr.artist == "Jane Doe")
        #expect(attr.licenseShortName == "CC BY-SA 4.0")
        #expect(attr.sourcePageURL == "https://commons.wikimedia.org/wiki/File:File.jpg")
        #expect(attr.requiresAttribution)
    }

    @Test func commonsPublicDomainNeedsNoAttribution() throws {
        let json = """
        { "query": { "pages": [ { "imageinfo": [ {
            "extmetadata": { "LicenseShortName": { "value": "Public domain" } }
        } ] } ] } }
        """
        let parsed = try CommonsClient.parse(data(json))
        let attr = try #require(parsed)
        #expect(!attr.requiresAttribution)
    }

    @Test func stripHTML() {
        #expect(CommonsClient.stripHTML("<a href=\"x\">Jane &amp; Co</a>") == "Jane & Co")
        #expect(CommonsClient.stripHTML("Plain") == "Plain")
        #expect(CommonsClient.stripHTML("") == nil)
        #expect(CommonsClient.stripHTML(nil) == nil)
    }

    // MARK: Wikidata

    @Test func wikidataParseNamesAndStatus() throws {
        let json = """
        { "results": { "bindings": [ {
            "fr": { "value": "Vulcain" },
            "en": { "value": "Red Admiral" },
            "iucnLabel": { "value": "Least Concern" }
        } ] } }
        """
        let result = try WikidataClient.parse(data(json))
        #expect(result.names.french == "Vulcain")
        #expect(result.names.english == "Red Admiral")
        #expect(result.iucnCategory == "LC")
    }

    @Test func wikidataEmptyBindings() throws {
        let result = try WikidataClient.parse(data(#"{ "results": { "bindings": [] } }"#))
        #expect(result.names.isEmpty)
        #expect(result.iucnCategory == nil)
    }

    @Test func iucnCodeMappingOrdering() {
        #expect(WikidataClient.iucnCode(fromLabel: "Critically Endangered") == "CR")
        #expect(WikidataClient.iucnCode(fromLabel: "Endangered") == "EN")
        #expect(WikidataClient.iucnCode(fromLabel: "Extinct in the Wild") == "EW")
        #expect(WikidataClient.iucnCode(fromLabel: "Extinct") == "EX")
        #expect(WikidataClient.iucnCode(fromLabel: "Near Threatened") == "NT")
        #expect(WikidataClient.iucnCode(fromLabel: "Gibberish") == nil)
    }

    // MARK: Xeno-canto

    @Test func xenoCantoPicksBestAndNormalizesURLs() throws {
        let json = """
        { "recordings": [
            { "id": "111", "rec": "Alice", "lic": "//creativecommons.org/l/by/4.0/",
              "url": "//xeno-canto.org/111", "file": "//xeno-canto.org/111/download",
              "q": "C", "type": "call" },
            { "id": "222", "rec": "Bob", "lic": "//creativecommons.org/l/by-sa/4.0/",
              "url": "//xeno-canto.org/222", "file": "//xeno-canto.org/222/download",
              "q": "A", "type": "song" }
        ] }
        """
        let parsed = try XenoCantoClient.parse(data(json))
        let audio = try #require(parsed)
        #expect(audio.catalogNumber == "XC222", "A-quality song should win")
        #expect(audio.audioURL.absoluteString == "https://xeno-canto.org/222/download")
        #expect(audio.attribution.artist == "Bob")
        #expect(audio.attribution.licenseURL == "https://creativecommons.org/l/by-sa/4.0/")
    }

    @Test func xenoCantoEmptyReturnsNil() throws {
        let parsed = try XenoCantoClient.parse(data(#"{ "recordings": [] }"#))
        #expect(parsed == nil)
    }

    // MARK: IUCN JSON walk

    @Test func iucnParseCategoryFindsNestedCode() {
        let json = """
        { "assessment": { "red_list_category_code": "VU", "scopes": [ { "description": "Europe" } ] } }
        """
        #expect(IUCNClient.parseCategory(data(json)) == "VU")
    }

    @Test func iucnParseAssessmentIDs() {
        let json = #"{ "assessments": [ { "assessment_id": 101 }, { "assessment_id": 202 } ] }"#
        #expect(Set(IUCNClient.parseAssessmentIDs(data(json))) == [101, 202])
    }
}
