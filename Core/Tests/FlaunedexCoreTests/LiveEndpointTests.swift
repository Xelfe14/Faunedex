import Testing
import Foundation
@testable import FlaunedexCore

/// Checks that run against the real services.
///
/// They are off by default, because a test suite that needs the network is a
/// test suite that fails on a train. Run them deliberately, when something
/// upstream might have changed:
///
///     FLAUNEDEX_LIVE=1 swift test --filter LiveEndpointTests
///
/// What they are for is the class of breakage no fixture can catch: Wikipedia
/// renaming a parameter, an endpoint being retired, a response growing a new
/// shape. The offline suite proves the parsing is right; these prove the thing
/// being parsed still arrives.
struct LiveEndpointTests {

    private static var enabled: Bool { ProcessInfo.processInfo.environment["FLAUNEDEX_LIVE"] == "1" }

    @Test(.enabled(if: LiveEndpointTests.enabled))
    func frenchWikipediaStillReturnsADishPhoto() async throws {
        let service = DishPhotoService()
        let photo = try #require(await service.photo(for: "Tarte Tatin"))
        #expect(photo.imageURL.absoluteString.contains("wikimedia.org"))
        #expect(photo.imageURL.query == nil, "analytics parameters are stripped")
        #expect(photo.pageTitle?.contains("Tatin") == true)
        #expect(photo.attribution?.licenseShortName != nil, "the licence must be resolvable")
    }

    @Test(.enabled(if: LiveEndpointTests.enabled))
    func searchResolvesANearMissToTheRightArticle() async throws {
        let service = DishPhotoService()
        let photo = try #require(await service.photo(for: "Shakshuka aux poivrons"))
        #expect(photo.imageURL.absoluteString.contains("wikimedia.org"))
    }

    @Test(.enabled(if: LiveEndpointTests.enabled))
    func anInventedDishDegradesToNoPhotoRatherThanAnError() async {
        let service = DishPhotoService()
        let photo = await service.photo(for: "zzqqx plat totalement inexistant 12345")
        #expect(photo == nil || photo?.imageURL != nil, "either nothing, or something usable")
    }

    @Test(.enabled(if: LiveEndpointTests.enabled))
    func gbifSpeciesMatchStillAnswers() async throws {
        let taxon = try #require(await GBIFService().match(name: "Vulpes vulpes"))
        #expect(taxon.canonicalName == "Vulpes vulpes")
        #expect(taxon.realm == .animal)
        #expect(taxon.isTrustworthy())
    }
}
