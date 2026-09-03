import Foundation

/// A photograph of a finished dish, with everything needed to credit it.
public struct DishPhoto: Sendable, Equatable {
    public let imageURL: URL
    public let thumbnailURL: URL?
    public let pageTitle: String?
    public let articleURL: URL?
    /// Commons `File:` title, used to look up artist and licence.
    public let commonsFileTitle: String?
    public var attribution: MediaAttribution?

    public init(imageURL: URL, thumbnailURL: URL? = nil, pageTitle: String? = nil,
                articleURL: URL? = nil, commonsFileTitle: String? = nil,
                attribution: MediaAttribution? = nil) {
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.pageTitle = pageTitle
        self.articleURL = articleURL
        self.commonsFileTitle = commonsFileTitle
        self.attribution = attribution
    }
}

/// Finds a real photograph for a dish.
///
/// The recipe text comes from a language model, but the picture does not: it is
/// a photograph of the actual dish, taken by a person, pulled from Wikipedia
/// with its Commons licence and credited on the card. That choice follows the
/// rest of the app, where every reused image already carries its attribution,
/// and it means a recipe illustrates the real thing rather than a plausible
/// looking invention.
///
/// French Wikipedia is searched first because the dish names are French and its
/// search resolves near-misses well (verified live: "Shakshuka aux poivrons"
/// lands on "Chakchouka", with a photo). English is the fallback for dishes
/// French Wikipedia does not cover.
public enum DishPhotoEndpoints {

    /// Full-text search that returns the best page together with its lead image,
    /// in one request. `gsrnamespace=0` keeps the search inside real articles.
    public static func search(query: String, host: URL) -> URL {
        var components = URLComponents(url: host, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: query),
            URLQueryItem(name: "gsrlimit", value: "1"),
            URLQueryItem(name: "gsrnamespace", value: "0"),
            URLQueryItem(name: "prop", value: "pageimages|info"),
            URLQueryItem(name: "piprop", value: "original|thumbnail|name"),
            URLQueryItem(name: "pithumbsize", value: "600"),
            URLQueryItem(name: "inprop", value: "url"),
        ]
        return components.url!
    }

    /// Wikimedia appends analytics parameters to the image URLs it hands out.
    /// They are noise in a stored record and in an attribution link, so the
    /// query string is dropped: these files are addressed by path alone.
    public static func cleanedImageURL(_ raw: String?) -> URL? {
        guard let raw, var components = URLComponents(string: raw) else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    struct ResponseDTO: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            let title: String?
            let index: Int?
            let fullurl: String?
            let canonicalurl: String?
            let pageimage: String?
            let original: Image?
            let thumbnail: Image?
        }
        struct Image: Decodable { let source: String? }
        let query: Query?
    }

    /// Parse a search response into a photo, or nil when the best page has no
    /// image (a real outcome for obscure dishes, and not an error).
    public static func parse(_ data: Data) throws -> DishPhoto? {
        let dto = try JSONDecoder().decode(ResponseDTO.self, from: data)
        let pages = (dto.query?.pages ?? []).sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        guard let page = pages.first,
              let image = cleanedImageURL(page.original?.source ?? page.thumbnail?.source)
        else { return nil }

        let fileTitle = page.pageimage.map { $0.hasPrefix("File:") ? $0 : "File:\($0)" }
        return DishPhoto(
            imageURL: image,
            thumbnailURL: cleanedImageURL(page.thumbnail?.source) ?? image,
            pageTitle: page.title,
            articleURL: (page.fullurl ?? page.canonicalurl).flatMap(URL.init(string:)),
            commonsFileTitle: fileTitle
        )
    }
}

/// Fetches a dish photo, French Wikipedia first, then English, then the Commons
/// licence for whichever image was found.
public struct DishPhotoService: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Best-effort throughout: a recipe with no picture is still a recipe, so
    /// every failure here degrades to nil instead of propagating.
    public func photo(for query: String) async -> DishPhoto? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var found: DishPhoto?
        for host in [FlaunedexConfig.frenchWikipediaActionAPI, FlaunedexConfig.wikipediaActionAPI] {
            // `try?` flattens the optional result, so a thrown error and a page
            // with no image both simply move on to the next language.
            guard let data = try? await http.getData(DishPhotoEndpoints.search(query: trimmed, host: host)),
                  let photo = try? DishPhotoEndpoints.parse(data) else { continue }
            found = photo
            break
        }
        guard var photo = found else { return nil }

        if let fileTitle = photo.commonsFileTitle,
           let data = try? await http.getData(CommonsClient.imageInfoURL(fileTitle: fileTitle)),
           let attribution = try? CommonsClient.parse(data) {
            photo.attribution = attribution
        }
        return photo
    }
}
