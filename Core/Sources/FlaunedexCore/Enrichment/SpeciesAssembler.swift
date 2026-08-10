import Foundation

/// Merges every source into one `SpeciesRecord`, encoding the precedence rules
/// in one place (and one test). Pure — takes already-fetched inputs so it needs
/// no network.
///
/// Name precedence: **Wikidata → Gemini → GBIF vernacular** (Wikidata P1843 is
/// the most reliable FR+EN source; Gemini is a good second; GBIF vernacular is
/// spotty). Taxonomy (family/realm/group) is authoritative from GBIF, with
/// Gemini only as a fallback when GBIF is silent.
public enum SpeciesAssembler {

    public static func assemble(
        taxon: TaxonMatch,
        gemini: GeminiIdentification,
        distribution: DistributionResult,
        wikipedia: WikipediaResult? = nil,
        imageAttribution: MediaAttribution? = nil,
        wikidata: WikidataClient.Result? = nil,
        gbifVernacular: VernacularNames? = nil,
        iucnEuropeCategory: String? = nil,
        iucnGlobalCategory: String? = nil,
        birdAudio: BirdAudio? = nil
    ) -> SpeciesRecord {

        let realm = taxon.realm ?? gemini.realm ?? .animal

        var animalGroup: AnimalGroup?
        if realm == .animal {
            let fromTaxon = AnimalGroupClassifier.classify(taxon)
            // If the taxonomy couldn't pin it down, accept the model's hint.
            animalGroup = (fromTaxon == .other ? gemini.animalGroup : nil) ?? fromTaxon
        }

        let french = wikidata?.names.french ?? gemini.frenchName ?? gbifVernacular?.french
        let english = wikidata?.names.english ?? gemini.englishName ?? gbifVernacular?.english

        // Conservation: prefer an explicit IUCN category, fall back to Wikidata.
        let global = iucnGlobalCategory ?? wikidata?.iucnCategory
        let conservation: ConservationStatus?
        if global != nil || iucnEuropeCategory != nil {
            let source = (iucnGlobalCategory != nil || iucnEuropeCategory != nil) ? "IUCN v4" : "Wikidata P141"
            conservation = ConservationStatus(
                globalCategory: global, europeCategory: iucnEuropeCategory, source: source
            )
        } else {
            conservation = nil
        }

        return SpeciesRecord(
            gbifKey: taxon.speciesKey,
            scientificName: taxon.canonicalName,
            frenchName: french,
            englishName: english,
            family: taxon.family ?? gemini.family,
            realm: realm,
            animalGroup: animalGroup,
            rangeCountries: distribution.rangeCountries,
            nativeCountries: distribution.nativeCountries,
            introducedCountries: distribution.introducedCountries,
            conservation: conservation,
            referenceImageURLString: wikipedia?.imageURL?.absoluteString,
            referenceThumbURLString: wikipedia?.thumbnailURL?.absoluteString,
            imageAttribution: imageAttribution,
            wikipediaURLString: wikipedia?.preferredArticleURL?.absoluteString,
            wikipediaTitle: wikipedia?.frenchTitle ?? wikipedia?.title,
            specificiteFR: gemini.specificiteFR,
            funFactFR: gemini.funFactFR,
            seasonMonths: sanitizeMonths(gemini.seasonMonths),
            toxicityDangerFR: gemini.toxicityDangerFR,
            audioURLString: birdAudio?.audioURL.absoluteString,
            audioAttribution: birdAudio?.attribution,
            audioCatalogNumber: birdAudio?.catalogNumber
        )
    }

    /// Keep only valid 1–12 months, de-duplicated and ordered.
    static func sanitizeMonths(_ months: [Int]?) -> [Int]? {
        guard let months else { return nil }
        let valid = Array(Set(months.filter { (1...12).contains($0) })).sorted()
        return valid.isEmpty ? nil : valid
    }
}
