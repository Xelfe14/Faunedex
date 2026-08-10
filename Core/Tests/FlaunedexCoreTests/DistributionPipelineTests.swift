import Testing
@testable import FlaunedexCore

/// The unlock rule lives here, so its behavior is pinned scenario by scenario.
struct DistributionPipelineTests {

    private func counts(_ pairs: [(String, Int)]) -> [GBIFResponses.CountryCount] {
        pairs.map { GBIFResponses.CountryCount(code: $0.0, count: $0.1) }
    }
    private func rows(_ pairs: [(String, String?)]) -> [GBIFResponses.DistributionRow] {
        pairs.map { GBIFResponses.DistributionRow(country: $0.0, establishmentMeans: $0.1) }
    }

    @Test func presenceIntersectsEuropeAndDropsNoise() {
        let result = DistributionPipeline.compute(
            facetCounts: counts([("FR", 100), ("DE", 50), ("US", 999), ("ZZ", 5)]),
            distributionRows: []
        )
        #expect(result.rangeCountries == ["DE", "FR"])
    }

    @Test func minimumOccurrencesDropsVagrants() {
        let result = DistributionPipeline.compute(
            facetCounts: counts([("FR", 100), ("IT", 1)]),
            distributionRows: [],
            minimumOccurrences: 5
        )
        #expect(result.rangeCountries == ["FR"])
    }

    @Test func introducedOnlyCountryIsExcludedButTagged() {
        let result = DistributionPipeline.compute(
            facetCounts: counts([("FR", 100), ("GB", 80)]),
            distributionRows: rows([("FR", "NATIVE"), ("GB", "INTRODUCED")])
        )
        #expect(result.rangeCountries == ["FR"], "GB is introduced-only, must not unlock")
        #expect(result.introducedCountries == ["GB"])
        #expect(result.nativeCountries == ["FR"])
    }

    @Test func nativeChecklistFillsUnderSampledCountry() {
        // ES has no occurrence records here but GBIF marks it native — include it.
        let result = DistributionPipeline.compute(
            facetCounts: counts([("FR", 100)]),
            distributionRows: rows([("FR", "NATIVE"), ("ES", "NATIVE")])
        )
        #expect(result.rangeCountries == ["ES", "FR"])
    }

    @Test func countryBothNativeAndIntroducedStaysUnlocked() {
        let result = DistributionPipeline.compute(
            facetCounts: counts([("FR", 100), ("PL", 20)]),
            distributionRows: rows([("PL", "NATIVE"), ("PL", "INTRODUCED")])
        )
        #expect(result.rangeCountries.contains("PL"))
    }

    @Test func invasiveSynonymsCountAsIntroduced() {
        let result = DistributionPipeline.compute(
            facetCounts: counts([("FR", 100), ("BE", 40)]),
            distributionRows: rows([("FR", "NATIVE"), ("BE", "naturalised")])
        )
        #expect(result.rangeCountries == ["FR"])
        #expect(result.introducedCountries == ["BE"])
    }
}
