import Testing
import Foundation
import ImageIO
import CoreGraphics
@testable import FlaunedexCore

/// The zoom buttons for each kind of iPhone, and photos brought in from the
/// library: converted like a capture, with their place and date kept.
struct CameraZoomTests {

    @Test func wideAndTelephotoLikeAnIPhoneXS() {
        let zoom = CameraZoom(minFactor: 1, maxFactor: 95, switchOverFactors: [2], hasUltraWide: false)
        #expect(zoom.mainFactor == 1)
        #expect(zoom.presets == [1, 2])
        #expect(zoom.maxFactor == 10, "digital zoom stops at 10×")
        #expect(zoom.factor(forDisplayed: 2) == 2)
    }

    @Test func ultraWideMainAndTelephotoLikeAPro() {
        let zoom = CameraZoom(minFactor: 1, maxFactor: 123, switchOverFactors: [2, 10], hasUltraWide: true)
        #expect(zoom.mainFactor == 2, "1× is the main lens, at the first switch-over")
        #expect(zoom.presets == [0.5, 1, 2, 5])
        #expect(zoom.displayed(1) == 0.5)
        #expect(zoom.factor(forDisplayed: 1) == 2)
        #expect(zoom.maxFactor == 20)
    }

    @Test func aSingleLensStillOffersTwiceDigital() {
        let zoom = CameraZoom(minFactor: 1, maxFactor: 16, switchOverFactors: [], hasUltraWide: false)
        #expect(zoom.presets == [1, 2])
    }

    @Test func zoomStaysWithinWhatTheDeviceCanDo() {
        let zoom = CameraZoom(minFactor: 1, maxFactor: 95, switchOverFactors: [2], hasUltraWide: false)
        #expect(zoom.factor(forDisplayed: 0.2) == 1)
        #expect(zoom.factor(forDisplayed: 40) == 10)
    }

    @Test func theActiveButtonIsTheLensBelow() {
        let zoom = CameraZoom(minFactor: 1, maxFactor: 123, switchOverFactors: [2, 10], hasUltraWide: true)
        #expect(zoom.activePreset(for: 0.7) == 0.5)
        #expect(zoom.activePreset(for: 1) == 1)
        #expect(zoom.activePreset(for: 3.4) == 2)
        #expect(zoom.activePreset(for: 8) == 5)
    }

    @Test func labelsAreFrench() {
        #expect(CameraZoom.label(0.5) == "0,5")
        #expect(CameraZoom.label(1) == "1")
        #expect(CameraZoom.label(1.43) == "1,4")
        #expect(CameraZoom.label(2.98) == "3")
        #expect(CameraZoom.label(10) == "10")
    }
}

struct LibraryPhotoTests {

    /// A real image of the given type and size, with the metadata given.
    private func makeImage(width: Int, height: Int, type: String = "public.jpeg",
                           metadata: [String: Any] = [:]) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(out as CFMutableData, type as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func properties(of data: Data) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func type(of data: Data) throws -> String? {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceGetType(source) as String?
    }

    @Test func keepsWhereAndWhenItWasTaken() throws {
        let data = try makeImage(width: 64, height: 48, metadata: [
            kCGImagePropertyGPSDictionary as String: ExifGPS.gpsDictionary(
                latitude: 45.9237, longitude: 6.8694, horizontalAccuracy: 8),
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: "2026:07:14 09:30:00",
                kCGImagePropertyExifOffsetTimeOriginal as String: "+02:00",
            ],
        ])
        let photo = try #require(LibraryPhoto(data))
        #expect(abs((photo.latitude ?? 0) - 45.9237) < 0.0001)
        #expect(abs((photo.longitude ?? 0) - 6.8694) < 0.0001)
        #expect(photo.horizontalAccuracy == 8)
        #expect(photo.takenAt == ISO8601DateFormatter().date(from: "2026-07-14T07:30:00Z"))
        #expect(ExifGPS.readCoordinate(from: photo.jpeg) != nil, "the stored copy keeps its place, like a capture")
    }

    @Test func aDateWithoutTimeZoneIsTakenAsLocal() throws {
        let data = try makeImage(width: 16, height: 16, metadata: [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: "2025:12:01 18:00:00",
            ],
        ])
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))
        let photo = try #require(LibraryPhoto(data, timeZone: paris))
        #expect(photo.takenAt == ISO8601DateFormatter().date(from: "2025-12-01T17:00:00Z"))
        #expect(photo.latitude == nil && photo.longitude == nil && photo.horizontalAccuracy == nil)
    }

    @Test func aPNGWithNothingBecomesAPlainJPEG() throws {
        let photo = try #require(LibraryPhoto(try makeImage(width: 20, height: 10, type: "public.png")))
        #expect(try type(of: photo.jpeg) == "public.jpeg")
        #expect(photo.takenAt == nil)
        #expect(photo.latitude == nil)
    }

    @Test func aLargePhotoIsScaledDown() throws {
        let photo = try #require(LibraryPhoto(try makeImage(width: 400, height: 300), maxPixelSize: 200))
        let props = try properties(of: photo.jpeg)
        #expect(props[kCGImagePropertyPixelWidth as String] as? Int == 200)
        #expect(props[kCGImagePropertyPixelHeight as String] as? Int == 150)
    }

    @Test func aRotatedPhotoIsTurnedUpright() throws {
        // Stored landscape, tagged to be shown rotated a quarter turn.
        let data = try makeImage(width: 40, height: 20, metadata: [kCGImagePropertyOrientation as String: 6])
        let photo = try #require(LibraryPhoto(data))
        let props = try properties(of: photo.jpeg)
        #expect(props[kCGImagePropertyPixelWidth as String] as? Int == 20)
        #expect(props[kCGImagePropertyPixelHeight as String] as? Int == 40)
        #expect((props[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1)
    }

    @Test func notAnImageIsRefused() {
        #expect(LibraryPhoto(Data("pas une photo".utf8)) == nil)
    }

    @Test func timeZoneOffsetsAreRead() {
        #expect(LibraryPhoto.timeZone(offset: "+02:00")?.secondsFromGMT() == 7200)
        #expect(LibraryPhoto.timeZone(offset: "-05:30")?.secondsFromGMT() == -19800)
        #expect(LibraryPhoto.timeZone(offset: "Z") == nil)
    }
}
