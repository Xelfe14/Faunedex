import Foundation

/// Xeno-canto API v3 (free key as a query param) for a reference bird song.
/// Only used when GBIF says the taxon is a bird. Each recording carries its own
/// CC license, so attribution is read per-recording.
public enum XenoCantoClient {

    /// Build the v3 recordings query for a genus + species. The key is required.
    public static func recordingsURL(genus: String, species: String, key: String) -> URL {
        var c = URLComponents(url: FlaunedexConfig.xenoCantoBaseURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "query", value: "gen:\"\(genus)\" sp:\"\(species)\""),
            URLQueryItem(name: "key", value: key),
        ]
        return c.url!
    }

    private struct ResponseDTO: Decodable {
        let recordings: [Recording]?
        struct Recording: Decodable {
            let id: String?
            let rec: String?      // recordist
            let lic: String?      // license URL (often protocol-relative)
            let url: String?      // recording page
            let file: String?     // audio file URL
            let q: String?        // quality A–E
            let type: String?     // e.g. "song", "call"
        }
    }

    /// Parse and select the best recording: prefer quality A/B and a song (not a
    /// call), then fall back to whatever is available.
    public static func parse(_ data: Data) throws -> BirdAudio? {
        let dto = try JSONDecoder().decode(ResponseDTO.self, from: data)
        let recordings = dto.recordings ?? []
        guard !recordings.isEmpty else { return nil }

        func score(_ r: ResponseDTO.Recording) -> Int {
            var s = 0
            switch (r.q ?? "").uppercased() {
            case "A": s += 3
            case "B": s += 2
            case "C": s += 1
            default: break
            }
            if (r.type ?? "").lowercased().contains("song") { s += 2 }
            return s
        }

        guard let best = recordings.max(by: { score($0) < score($1) }),
              let fileURL = normalizedURL(best.file) else { return nil }

        let attribution = MediaAttribution(
            artist: best.rec,
            licenseShortName: nil,
            licenseURL: normalizedURL(best.lic)?.absoluteString,
            sourcePageURL: normalizedURL(best.url)?.absoluteString
        )
        let catalog = best.id.map { "XC\($0)" }
        return BirdAudio(audioURL: fileURL, attribution: attribution, catalogNumber: catalog)
    }

    /// Xeno-canto returns some URLs protocol-relative ("//..."); make them https.
    static func normalizedURL(_ raw: String?) -> URL? {
        guard var s = raw, !s.isEmpty else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        return URL(string: s)
    }
}
