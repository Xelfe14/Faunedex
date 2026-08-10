import Foundation

/// Attribution captured for any reused media (image or audio). Stored alongside
/// the asset so the app can honour CC-BY / CC-BY-SA obligations — no asset is
/// ever shown without rendering its credit.
public struct MediaAttribution: Codable, Sendable, Equatable {
    public let artist: String?
    public let licenseShortName: String?
    public let licenseURL: String?
    /// Link back to the source page (Commons File: page, Xeno-canto recording).
    public let sourcePageURL: String?

    public init(artist: String?, licenseShortName: String?, licenseURL: String?, sourcePageURL: String?) {
        self.artist = artist
        self.licenseShortName = licenseShortName
        self.licenseURL = licenseURL
        self.sourcePageURL = sourcePageURL
    }

    /// Public-domain / CC0 assets carry no attribution obligation.
    public var requiresAttribution: Bool {
        guard let l = licenseShortName?.lowercased() else { return true }
        if l.contains("public domain") || l.contains("cc0") || l.contains("pd") { return false }
        return true
    }
}

/// A representative reference image for a species, resolved from Wikimedia.
public struct ReferenceImage: Sendable, Equatable {
    public let imageURL: URL
    public let thumbnailURL: URL?
    /// The Commons `File:` title, needed to look up license/attribution.
    public let fileTitle: String?
    public let attribution: MediaAttribution?

    public init(imageURL: URL, thumbnailURL: URL?, fileTitle: String?, attribution: MediaAttribution?) {
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.fileTitle = fileTitle
        self.attribution = attribution
    }
}

/// French + English common names for a species.
public struct VernacularNames: Sendable, Equatable {
    public let french: String?
    public let english: String?

    public init(french: String?, english: String?) {
        self.french = french
        self.english = english
    }

    public var isEmpty: Bool { french == nil && english == nil }
}

/// IUCN-style conservation category, global and (where available) European-scoped.
public struct ConservationStatus: Sendable, Equatable {
    /// e.g. "LC", "NT", "VU", "EN", "CR", "DD", "EX".
    public let globalCategory: String?
    public let europeCategory: String?
    /// Where the value came from ("IUCN v4" or "Wikidata P141").
    public let source: String?

    public init(globalCategory: String?, europeCategory: String?, source: String?) {
        self.globalCategory = globalCategory
        self.europeCategory = europeCategory
        self.source = source
    }

    /// The category to badge with: prefer the European assessment, fall back to
    /// the global one.
    public var displayCategory: String? { europeCategory ?? globalCategory }

    /// Whether this should render as a "rare"/prestige badge in the dex.
    public var isNotable: Bool {
        guard let c = displayCategory?.uppercased() else { return false }
        return ["NT", "VU", "EN", "CR", "EW", "EX"].contains(c)
    }
}

/// A reference bird recording from Xeno-canto (birds only).
public struct BirdAudio: Sendable, Equatable {
    public let audioURL: URL
    public let attribution: MediaAttribution
    /// Xeno-canto catalogue id, e.g. "XC803241".
    public let catalogNumber: String?

    public init(audioURL: URL, attribution: MediaAttribution, catalogNumber: String?) {
        self.audioURL = audioURL
        self.attribution = attribution
        self.catalogNumber = catalogNumber
    }
}
