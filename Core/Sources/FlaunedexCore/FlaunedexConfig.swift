import Foundation

/// Centralized, non-secret configuration for the core clients. Secrets (the
/// Gemini / IUCN / Xeno-canto keys) are never stored here — they are passed in
/// at call time from the app's Keychain.
public enum FlaunedexConfig {

    /// Sent on every Wikimedia / Wikidata / GBIF request. These services ask
    /// for a descriptive User-Agent with contact info and rate-limit anonymous
    /// traffic that omits it.
    public static let userAgent = "Flaunedex/1.0 (https://github.com/; taddeocarpinelli@gmail.com)"

    // MARK: Gemini
    /// Stable, multimodal flagship Flash model (verified against ai.google.dev,
    /// Aug 2026). Kept here as the single source of truth so it can be updated
    /// in one place when Google rotates models.
    public static let geminiModel = "gemini-3.6-flash"
    /// Cheaper high-throughput fallback, used only if ever needed.
    public static let geminiFallbackModel = "gemini-3.5-flash-lite"
    public static let geminiBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    // MARK: GBIF
    public static let gbifBaseURL = URL(string: "https://api.gbif.org/v1")!

    // MARK: Wikimedia / Wikidata
    public static let wikipediaActionAPI = URL(string: "https://en.wikipedia.org/w/api.php")!
    /// French Wikipedia, searched first for dish photos: the recipe titles are
    /// French, and its search resolves near-misses to the right article.
    public static let frenchWikipediaActionAPI = URL(string: "https://fr.wikipedia.org/w/api.php")!
    public static let commonsActionAPI = URL(string: "https://commons.wikimedia.org/w/api.php")!
    public static let wikidataSPARQL = URL(string: "https://query.wikidata.org/sparql")!

    // MARK: IUCN Red List
    public static let iucnBaseURL = URL(string: "https://api.iucnredlist.org/api/v4")!

    // MARK: Xeno-canto
    public static let xenoCantoBaseURL = URL(string: "https://xeno-canto.org/api/3/recordings")!
}
