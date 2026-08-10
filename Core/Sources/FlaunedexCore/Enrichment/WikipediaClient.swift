import Foundation

/// One Wikipedia lookup gives us three things at once: a reference image, the
/// Commons file title (for licensing), and the **article link** the user can
/// open for more info — French page preferred, English as fallback.
public struct WikipediaResult: Sendable, Equatable {
    public let title: String?
    public let englishPageURL: URL?
    public let frenchTitle: String?
    public let frenchPageURL: URL?
    public let imageURL: URL?
    public let thumbnailURL: URL?
    /// Commons `File:` title used to fetch license/attribution.
    public let commonsFileTitle: String?

    public init(
        title: String?, englishPageURL: URL?, frenchTitle: String?, frenchPageURL: URL?,
        imageURL: URL?, thumbnailURL: URL?, commonsFileTitle: String?
    ) {
        self.title = title
        self.englishPageURL = englishPageURL
        self.frenchTitle = frenchTitle
        self.frenchPageURL = frenchPageURL
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.commonsFileTitle = commonsFileTitle
    }

    /// The link to show on the species card — French article if one exists,
    /// otherwise the English article.
    public var preferredArticleURL: URL? { frenchPageURL ?? englishPageURL }
}

/// Builds and parses the MediaWiki Action API call (chosen over the
/// announced-deprecated REST `rest_v1`). One request returns the lead image,
/// the page URLs, and the French inter-language link.
public enum WikipediaClient {

    /// Action API query by scientific name against English Wikipedia (whose page
    /// titles reliably match Latin binomials), pulling the French langlink.
    public static func lookupURL(scientificName: String) -> URL {
        var c = URLComponents(url: FlaunedexConfig.wikipediaActionAPI, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "prop", value: "pageimages|langlinks|info"),
            URLQueryItem(name: "piprop", value: "original|thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "500"),
            URLQueryItem(name: "inprop", value: "url"),
            URLQueryItem(name: "lllang", value: "fr"),
            URLQueryItem(name: "llprop", value: "url"),
            URLQueryItem(name: "titles", value: scientificName),
        ]
        return c.url!
    }

    struct ResponseDTO: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            let title: String?
            let missing: Bool?
            let fullurl: String?
            let canonicalurl: String?
            let pageimage: String?
            let original: Img?
            let thumbnail: Img?
            let langlinks: [LangLink]?
        }
        struct Img: Decodable { let source: String? }
        struct LangLink: Decodable { let lang: String?; let title: String?; let url: String? }
        let query: Query?
    }

    public static func parse(_ data: Data) throws -> WikipediaResult? {
        let dto = try JSONDecoder().decode(ResponseDTO.self, from: data)
        guard let page = dto.query?.pages?.first, page.missing != true else { return nil }

        let fr = page.langlinks?.first { ($0.lang ?? "").lowercased() == "fr" }
        let fileTitle = page.pageimage.map { $0.hasPrefix("File:") ? $0 : "File:\($0)" }

        return WikipediaResult(
            title: page.title,
            englishPageURL: (page.fullurl ?? page.canonicalurl).flatMap(URL.init(string:)),
            frenchTitle: fr?.title,
            frenchPageURL: fr?.url.flatMap(URL.init(string:)),
            imageURL: page.original?.source.flatMap(URL.init(string:)),
            thumbnailURL: page.thumbnail?.source.flatMap(URL.init(string:)),
            commonsFileTitle: fileTitle
        )
    }
}
