import Testing
import Foundation
import ImageIO
import CoreGraphics
@testable import FlaunedexCore

/// GPS tagging is what makes the sightings map work, so it's round-tripped
/// against real encoded image data rather than assumed.
struct ExifGPSTests {

    /// A tiny real JPEG to inject metadata into.
    private func makeJPEG(width: Int = 8, height: Int = 8) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let out = NSMutableData()
        let type = "public.jpeg" as CFString
        let dest = try #require(CGImageDestinationCreateWithData(out as CFMutableData, type, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    @Test func roundTripsPositiveCoordinate() throws {
        let jpeg = try makeJPEG()
        // Chamonix, French Alps.
        let tagged = try #require(ExifGPS.inject(into: jpeg, latitude: 45.9237, longitude: 6.8694))
        let read = try #require(ExifGPS.readCoordinate(from: tagged))
        #expect(abs(read.latitude - 45.9237) < 0.0001)
        #expect(abs(read.longitude - 6.8694) < 0.0001)
    }

    @Test func roundTripsSouthernAndWesternHemispheres() throws {
        let jpeg = try makeJPEG()
        let tagged = try #require(ExifGPS.inject(into: jpeg, latitude: -33.9249, longitude: -18.4241))
        let read = try #require(ExifGPS.readCoordinate(from: tagged))
        #expect(read.latitude < 0, "southern latitude must come back negative")
        #expect(read.longitude < 0, "western longitude must come back negative")
        #expect(abs(read.latitude + 33.9249) < 0.0001)
        #expect(abs(read.longitude + 18.4241) < 0.0001)
    }

    @Test func untaggedImageHasNoCoordinate() throws {
        let jpeg = try makeJPEG()
        #expect(ExifGPS.readCoordinate(from: jpeg) == nil)
    }

    @Test func injectionPreservesDecodableImage() throws {
        let jpeg = try makeJPEG(width: 16, height: 16)
        let tagged = try #require(ExifGPS.inject(into: jpeg, latitude: 48.8566, longitude: 2.3522))
        let source = try #require(CGImageSourceCreateWithData(tagged as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(props[kCGImagePropertyPixelWidth as String] as? Int == 16)
        #expect(props[kCGImagePropertyPixelHeight as String] as? Int == 16)
    }

    @Test func altitudeAndAccuracyRecorded() {
        let gps = ExifGPS.gpsDictionary(
            latitude: 45.0, longitude: 6.0, altitude: 1200, horizontalAccuracy: 12, timestamp: Date(timeIntervalSince1970: 0)
        )
        #expect(gps[kCGImagePropertyGPSAltitude as String] as? Double == 1200)
        #expect(gps[kCGImagePropertyGPSAltitudeRef as String] as? Int == 0)
        #expect(gps[kCGImagePropertyGPSHPositioningError as String] as? Double == 12)
        #expect(gps[kCGImagePropertyGPSDateStamp as String] as? String == "1970:01:01")
    }

    @Test func negativeAltitudeUsesBelowSeaLevelRef() {
        let gps = ExifGPS.gpsDictionary(latitude: 0, longitude: 0, altitude: -50)
        #expect(gps[kCGImagePropertyGPSAltitudeRef as String] as? Int == 1)
        #expect(gps[kCGImagePropertyGPSAltitude as String] as? Double == 50, "altitude is stored as magnitude")
    }

    @Test func invalidImageDataReturnsNil() {
        let garbage = Data("not an image".utf8)
        #expect(ExifGPS.inject(into: garbage, latitude: 1, longitude: 2) == nil)
    }
}
