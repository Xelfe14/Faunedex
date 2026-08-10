import Foundation

/// Combines the occurrence-facet presence with checklist establishment-means to
/// produce the natural-range unlock set the user chose:
///
///   rangeCountries = (wild presence ∪ explicitly-native) − introduced-only
///
/// - **Wild presence** comes from the occurrence facet (already basis-of-record
///   filtered upstream) intersected with the European whitelist.
/// - **Explicitly-native** checklist countries are added so under-sampled
///   regions (a known GBIF bias) aren't wrongly locked.
/// - **Introduced-only** countries (marked introduced and *not* also native)
///   are subtracted, so garden escapees and lost migrants don't light up a
///   country — while still being retained in `introducedCountries` for a
///   distinct "introduit" tag in the UI.
public enum DistributionPipeline {

    private static let nativeMeans: Set<String> = ["native"]
    private static let introducedMeans: Set<String> = [
        "introduced", "invasive", "naturalised", "naturalized", "alien",
    ]

    /// Compute the distribution result.
    /// - Parameters:
    ///   - facetCounts: parsed country facet (see `GBIFResponses.parseCountryFacet`).
    ///   - distributionRows: parsed checklist rows (see `GBIFResponses.parseDistributions`).
    ///   - minimumOccurrences: drop facet countries below this count to suppress
    ///     one-off vagrants. Defaults to 1 (presence only).
    public static func compute(
        facetCounts: [GBIFResponses.CountryCount],
        distributionRows: [GBIFResponses.DistributionRow],
        minimumOccurrences: Int = 1
    ) -> DistributionResult {

        let presence = Set(
            EuropeanCountries.filterToEurope(
                facetCounts.filter { $0.count >= minimumOccurrences }.map(\.code)
            )
        )

        var native = Set<String>()
        var introduced = Set<String>()
        for row in distributionRows {
            guard EuropeanCountries.contains(row.country) else { continue }
            let means = (row.establishmentMeans ?? "").lowercased()
            let code = row.country.uppercased()
            if nativeMeans.contains(means) { native.insert(code) }
            else if introducedMeans.contains(means) { introduced.insert(code) }
        }

        let introducedOnly = introduced.subtracting(native)
        let range = presence.union(native).subtracting(introducedOnly)

        return DistributionResult(
            rangeCountries: range.sorted(),
            nativeCountries: native.sorted(),
            introducedCountries: introduced.sorted()
        )
    }
}
