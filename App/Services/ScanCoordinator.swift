import Foundation
import SwiftData
import Observation
import FlaunedexCore

/// Owns the capture → queue → identify → persist flow. Capture writes a complete
/// `Sighting` synchronously (fully offline); everything networked is deferred to
/// `processQueue()`, which the UI calls on appear and whenever connectivity is
/// regained.
@MainActor
@Observable
final class ScanCoordinator {
    private let context: ModelContext
    private let keys: APIKeys
    private let photos = PhotoStore()
    private let geocoder = ReverseGeocoder()
    private let pipeline = SpeciesIdentificationPipeline()

    /// Set when a scan unlocks a brand-new species, so the UI can celebrate.
    var newlyUnlocked: Species?
    var isProcessing = false

    init(context: ModelContext, keys: APIKeys) {
        self.context = context
        self.keys = keys
    }

    /// Persist a captured photo + GPS as a queued sighting. Returns immediately;
    /// identification happens later in `processQueue()`.
    @discardableResult
    func enqueueCapture(imageData: Data, latitude: Double, longitude: Double, accuracy: Double) throws -> Sighting {
        let id = UUID()
        let path = try photos.save(imageData, id: id)
        let sighting = Sighting(id: id, photoRelativePath: path,
                                latitude: latitude, longitude: longitude, horizontalAccuracy: accuracy)
        context.insert(sighting)
        try context.save()
        return sighting
    }

    /// Drain every unresolved sighting. Safe to call repeatedly; each item is
    /// idempotent and retried with a cap. Sightings awaiting the user's decision
    /// (`needsReview`) are skipped for identification: only an explicit retry
    /// moves those.
    ///
    /// Geocoding is drained separately from identification because the two fail
    /// independently. A photo taken in the mountains can be identified from a
    /// hotel wifi hours later while the country lookup happens to fail; if that
    /// country were only ever attempted on the identification pass, the sighting
    /// would be marked complete and lose its country permanently, which quietly
    /// breaks the "vu ici" markers and the "pays visités" count.
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let all = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []

        for sighting in all where sighting.needsGeocoding {
            await geocode(sighting)
        }

        guard keys.hasGeminiKey else {
            try? context.save()
            return
        }
        for sighting in all
        where sighting.status != .complete && sighting.status != .needsReview && sighting.retryCount < 5 {
            await process(sighting)
        }
        try? context.save()
    }

    /// Resolve the country for one sighting, counting the attempt either way so
    /// a permanently unresolvable coordinate cannot be retried forever.
    private func geocode(_ sighting: Sighting) async {
        sighting.geocodeAttempts += 1
        if let iso = await geocoder.countryISO(latitude: sighting.latitude, longitude: sighting.longitude) {
            sighting.countryISO = iso
        }
    }

    /// The candidate identifications recorded for an uncertain sighting.
    func candidates(for sighting: Sighting) -> [GeminiIdentification.Candidate] {
        guard let json = sighting.geminiCandidatesJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([GeminiIdentification.Candidate].self, from: data)) ?? []
    }

    /// Re-run identification for an uncertain sighting — either with deeper
    /// reasoning, or confirming a candidate the user picked.
    func retryIdentification(for sighting: Sighting, choosing scientificName: String? = nil) async {
        guard keys.hasGeminiKey, let data = photos.load(sighting.photoRelativePath) else { return }
        isProcessing = true
        defer { isProcessing = false }

        let bundle = SpeciesIdentificationPipeline.Keys(
            gemini: keys.geminiKey,
            iucn: keys.iucnToken.isEmpty ? nil : keys.iucnToken,
            xenoCanto: keys.xenoCantoKey.isEmpty ? nil : keys.xenoCantoKey
        )
        do {
            let outcome = try await pipeline.run(
                base64Image: data.base64EncodedString(),
                mimeType: "image/jpeg",
                keys: bundle,
                thinkingLevel: .high,
                hintScientificName: scientificName
            )
            if let record = outcome.record {
                link(sighting: sighting, to: record)
                sighting.geminiCandidatesJSON = nil
                sighting.status = .complete
            } else {
                sighting.geminiCandidatesJSON = encodeCandidates(outcome.identification)
                sighting.status = .needsReview
            }
        } catch {
            sighting.status = .failed
        }
        try? context.save()
    }

    private func process(_ sighting: Sighting) async {
        // Country resolution is handled by `processQueue`, which retries it on
        // its own schedule regardless of whether identification succeeded.

        // Identify + enrich if still needed.
        if sighting.speciesKey == nil {
            guard let data = photos.load(sighting.photoRelativePath) else {
                sighting.status = .failed
                return
            }
            let keysBundle = SpeciesIdentificationPipeline.Keys(
                gemini: keys.geminiKey,
                iucn: keys.iucnToken.isEmpty ? nil : keys.iucnToken,
                xenoCanto: keys.xenoCantoKey.isEmpty ? nil : keys.xenoCantoKey
            )
            do {
                let outcome = try await pipeline.run(
                    base64Image: data.base64EncodedString(), mimeType: "image/jpeg", keys: keysBundle)
                if let record = outcome.record {
                    link(sighting: sighting, to: record)
                    sighting.status = .complete
                } else {
                    sighting.geminiCandidatesJSON = encodeCandidates(outcome.identification)
                    sighting.status = .needsReview
                    sighting.retryCount += 1
                }
            } catch {
                sighting.retryCount += 1
                sighting.status = .failed
            }
        }
        try? context.save()
    }

    /// Find the existing species for this key or create it, then link the
    /// sighting. Firing the celebration only for a genuinely new dex entry.
    private func link(sighting: Sighting, to record: SpeciesRecord) {
        let key = record.gbifKey
        let existing = (try? context.fetch(
            FetchDescriptor<Species>(predicate: #Predicate { $0.gbifKey == key })
        ))?.first

        let species: Species
        if let existing {
            species = existing
        } else {
            species = Species(gbifKey: record.gbifKey, scientificName: record.scientificName, realm: record.realm)
            species.dexNumber = nextDexNumber()
            apply(record, to: species)
            context.insert(species)
            newlyUnlocked = species
        }
        sighting.species = species
        sighting.speciesKey = record.gbifKey
    }

    /// Next catalogue number = highest assigned so far + 1, so numbers stay
    /// stable even if an entry is later deleted.
    private func nextDexNumber() -> Int {
        let all = (try? context.fetch(FetchDescriptor<Species>())) ?? []
        return (all.map(\.dexNumber).max() ?? 0) + 1
    }

    private func apply(_ r: SpeciesRecord, to s: Species) {
        s.frenchName = r.frenchName
        s.englishName = r.englishName
        s.family = r.family
        s.animalGroupRaw = r.animalGroup?.rawValue
        s.rangeCountries = r.rangeCountries
        s.nativeCountries = r.nativeCountries
        s.introducedCountries = r.introducedCountries
        s.conservationGlobal = r.conservation?.globalCategory
        s.conservationEurope = r.conservation?.europeCategory
        s.referenceImageURLString = r.referenceImageURLString
        s.referenceThumbURLString = r.referenceThumbURLString
        s.imageArtist = r.imageAttribution?.artist
        s.imageLicenseShort = r.imageAttribution?.licenseShortName
        s.imageLicenseURL = r.imageAttribution?.licenseURL
        s.imageSourcePageURL = r.imageAttribution?.sourcePageURL
        s.wikipediaURLString = r.wikipediaURLString
        s.wikipediaTitle = r.wikipediaTitle
        s.specificiteFR = r.specificiteFR
        s.funFactFR = r.funFactFR
        s.seasonMonths = r.seasonMonths ?? []
        s.toxicityDangerFR = r.toxicityDangerFR
        s.audioURLString = r.audioURLString
        s.audioRecordist = r.audioAttribution?.artist
        s.audioLicenseURL = r.audioAttribution?.licenseURL
        s.audioSourcePageURL = r.audioAttribution?.sourcePageURL
        s.audioCatalogNumber = r.audioCatalogNumber
        s.enrichmentStatus = .complete
    }

    private func encodeCandidates(_ id: GeminiIdentification) -> String? {
        guard let candidates = id.candidates, !candidates.isEmpty,
              let data = try? JSONEncoder().encode(candidates) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
