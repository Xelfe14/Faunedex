import Foundation

/// Fetches license + attribution for a Commons image. `extmetadata` is
/// free-form and frequently missing or malformed, so parsing is defensive:
/// unknown/absent fields degrade to nil rather than failing the decode.
public enum CommonsClient {

    public static func imageInfoURL(fileTitle: String) -> URL {
        var c = URLComponents(url: FlaunedexConfig.commonsActionAPI, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "extmetadata|url|user"),
            URLQueryItem(name: "titles", value: fileTitle),
        ]
        return c.url!
    }

    /// A tolerant extmetadata value: takes the `value` field whatever its JSON
    /// type, and ignores the rest.
    private struct ExtField: Decodable {
        let value: String?
        enum CodingKeys: String, CodingKey { case value }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let s = try? c.decode(String.self, forKey: .value) { value = s }
            else if let i = try? c.decode(Int.self, forKey: .value) { value = String(i) }
            else if let b = try? c.decode(Bool.self, forKey: .value) { value = b ? "true" : "false" }
            else { value = nil }
        }
    }

    private struct ResponseDTO: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            let imageinfo: [ImageInfo]?
        }
        struct ImageInfo: Decodable {
            let url: String?
            let descriptionurl: String?
            let user: String?
            let extmetadata: [String: ExtField]?
        }
        let query: Query?
    }

    public static func parse(_ data: Data) throws -> MediaAttribution? {
        let dto = try JSONDecoder().decode(ResponseDTO.self, from: data)
        guard let info = dto.query?.pages?.first?.imageinfo?.first else { return nil }
        let meta = info.extmetadata ?? [:]

        let artist = stripHTML(meta["Artist"]?.value) ?? info.user
        let licenseShort = meta["LicenseShortName"]?.value ?? meta["License"]?.value
        let licenseURL = meta["LicenseUrl"]?.value

        return MediaAttribution(
            artist: artist,
            licenseShortName: licenseShort,
            licenseURL: licenseURL,
            sourcePageURL: info.descriptionurl
        )
    }

    /// Crude HTML-tag / entity strip so an `Artist` like
    /// `<a href="...">Jane Doe</a>` renders as `Jane Doe`.
    static func stripHTML(_ input: String?) -> String? {
        guard let input, !input.isEmpty else { return nil }
        var s = input
        // Remove tags.
        while let open = s.firstIndex(of: "<"), let close = s[open...].firstIndex(of: ">") {
            s.removeSubrange(open...close)
        }
        // Decode a few common entities.
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&nbsp;": " ", "&lt;": "<", "&gt;": ">"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
