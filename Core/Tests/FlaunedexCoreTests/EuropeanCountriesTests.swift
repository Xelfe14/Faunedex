import Testing
@testable import FlaunedexCore

struct EuropeanCountriesTests {

    @Test func containsIsCaseInsensitive() {
        #expect(EuropeanCountries.contains("FR"))
        #expect(EuropeanCountries.contains("fr"))
        #expect(EuropeanCountries.contains("de"))
        #expect(!EuropeanCountries.contains("US"))
        #expect(!EuropeanCountries.contains("ZZ"))
    }

    @Test func frenchNames() {
        #expect(EuropeanCountries.frenchName(for: "FR") == "France")
        #expect(EuropeanCountries.frenchName(for: "de") == "Allemagne")
        #expect(EuropeanCountries.frenchName(for: "GB") == "Royaume-Uni")
        // Unknown code returns itself uppercased.
        #expect(EuropeanCountries.frenchName(for: "us") == "US")
    }

    @Test func filterDropsNonEuropeanDedupesAndSorts() {
        let input = ["US", "fr", "FR", "IT", "ZZ", "de", "JP"]
        #expect(EuropeanCountries.filterToEurope(input) == ["DE", "FR", "IT"])
    }

    @Test func filterEmpty() {
        #expect(EuropeanCountries.filterToEurope(["US", "JP"]) == [])
    }
}
