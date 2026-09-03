import Foundation
import SwiftData
import FlaunedexCore

/// The canonical dex card. One row per species (deduped in code by `gbifKey`
/// since CloudKit forbids `@Attribute(.unique)`).
///
/// CloudKit-safe by construction: every stored property has a default, and the
/// relationship is optional. Enum-typed values are stored as raw strings and
/// surfaced through typed accessors.
@Model
final class Species {
    var gbifKey: Int = 0
    var scientificName: String = ""
    var frenchName: String?
    var englishName: String?
    var family: String?

    var realmRaw: String = Realm.animal.rawValue
    var animalGroupRaw: String?

    /// Natural-range unlock set + the native/introduced split (ISO alpha-2).
    var rangeCountries: [String] = []
    var nativeCountries: [String] = []
    var introducedCountries: [String] = []

    var conservationGlobal: String?
    var conservationEurope: String?

    // Reference image + attribution (flattened for CloudKit friendliness).
    var referenceImageURLString: String?
    var referenceThumbURLString: String?
    var localImagePath: String?          // cached bytes on disk
    var imageArtist: String?
    var imageLicenseShort: String?
    var imageLicenseURL: String?
    var imageSourcePageURL: String?

    /// "En savoir plus sur Wikipédia" link (French article preferred).
    var wikipediaURLString: String?
    var wikipediaTitle: String?

    var specificiteFR: String?
    var funFactFR: String?
    var seasonMonths: [Int] = []
    var toxicityDangerFR: String?

    // Bird song + attribution.
    var audioURLString: String?
    var localAudioPath: String?
    var audioRecordist: String?
    var audioLicenseURL: String?
    var audioSourcePageURL: String?
    var audioCatalogNumber: String?

    var firstUnlockedAt: Date = Date.now
    /// Catalogue number in discovery order — the "N° 007" that gives the
    /// collection its Pokédex character. Assigned when the species is created.
    var dexNumber: Int = 0
    var enrichmentStatusRaw: String = EnrichmentStatus.pending.rawValue

    @Relationship(deleteRule: .cascade, inverse: \Sighting.species)
    var sightings: [Sighting]? = []

    init(gbifKey: Int, scientificName: String, realm: Realm) {
        self.gbifKey = gbifKey
        self.scientificName = scientificName
        self.realmRaw = realm.rawValue
    }

    // MARK: Typed accessors

    var realm: Realm { Realm(rawValue: realmRaw) ?? .animal }
    var animalGroup: AnimalGroup? { animalGroupRaw.flatMap(AnimalGroup.init(rawValue:)) }
    var enrichmentStatus: EnrichmentStatus {
        get { EnrichmentStatus(rawValue: enrichmentStatusRaw) ?? .pending }
        set { enrichmentStatusRaw = newValue.rawValue }
    }

    var displayName: String { frenchName ?? englishName ?? scientificName }
    var conservationBadge: String? { conservationEurope ?? conservationGlobal }
    var wikipediaURL: URL? { wikipediaURLString.flatMap(URL.init(string:)) }

    var isNotable: Bool {
        guard let c = conservationBadge?.uppercased() else { return false }
        return ["NT", "VU", "EN", "CR", "EW", "EX"].contains(c)
    }

    enum EnrichmentStatus: String, Codable { case pending, partial, complete }
}

/// One physical observation the user made: a photo, where and when.
@Model
final class Sighting {
    var id: UUID = UUID()
    var photoRelativePath: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var horizontalAccuracy: Double = -1
    var capturedAt: Date = Date.now
    var countryISO: String?
    /// How many times the reverse geocode has been tried. The country lookup is
    /// online-only and independent of identification, so it needs its own
    /// counter: a sighting identified from cache while the geocoder was
    /// unreachable would otherwise keep its country empty forever.
    var geocodeAttempts: Int = 0
    var note: String?

    /// Set once the queued scan resolves to a species key.
    var speciesKey: Int?
    var statusRaw: String = Status.pendingIdentification.rawValue
    var retryCount: Int = 0
    /// Low-confidence candidate list (JSON) for the review UI.
    var geminiCandidatesJSON: String?

    var species: Species?

    init(id: UUID = UUID(), photoRelativePath: String, latitude: Double, longitude: Double,
         horizontalAccuracy: Double, capturedAt: Date = .now) {
        self.id = id
        self.photoRelativePath = photoRelativePath
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.capturedAt = capturedAt
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .pendingIdentification }
        set { statusRaw = newValue.rawValue }
    }

    /// A capture taken with no usable GPS fix is stored at (0, 0). Those are
    /// hidden from the map and must never be reverse-geocoded, since (0, 0) is
    /// a real point in the Atlantic.
    var hasCoordinate: Bool { !(latitude == 0 && longitude == 0) }

    /// Whether the country still needs looking up, and is still worth retrying.
    var needsGeocoding: Bool { countryISO == nil && hasCoordinate && geocodeAttempts < 5 }

    enum Status: String, Codable {
        case pendingIdentification, pendingGeocoding, complete, failed, needsReview
    }
}
