import Testing
import Foundation
import ImageIO
import CoreGraphics
@testable import FlaunedexCore

/// What leaves the phone for identification is proven, not assumed: no
/// coordinates, a bounded size, and the right way up.
struct UploadImageTests {

    /// A real JPEG of the given size, optionally tagged with an EXIF orientation.
    private func makeJPEG(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(out as CFMutableData, "public.jpeg" as CFString, 1, nil))
        let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(dest, image, properties)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func properties(of data: Data) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let props = try properties(of: data)
        return (try #require(props[kCGImagePropertyPixelWidth as String] as? Int),
                try #require(props[kCGImagePropertyPixelHeight as String] as? Int))
    }

    @Test func dropsTheCoordinates() throws {
        let tagged = try #require(ExifGPS.inject(
            into: try makeJPEG(width: 64, height: 48), latitude: 45.9237, longitude: 6.8694
        ))
        #expect(ExifGPS.readCoordinate(from: tagged) != nil, "precondition: the capture carries GPS")

        let upload = try #require(UploadImage.prepare(tagged))
        #expect(ExifGPS.readCoordinate(from: upload) == nil)
        #expect(try properties(of: upload)[kCGImagePropertyGPSDictionary as String] == nil)
    }

    @Test func boundsTheLongEdgeAndKeepsTheAspectRatio() throws {
        let upload = try #require(UploadImage.prepare(try makeJPEG(width: 3200, height: 2400)))
        let size = try pixelSize(of: upload)
        #expect(size.width == UploadImage.maxPixelSize)
        #expect(abs(size.height - 1200) <= 1)
    }

    @Test func neverEnlargesASmallPhoto() throws {
        let upload = try #require(UploadImage.prepare(try makeJPEG(width: 64, height: 48)))
        let size = try pixelSize(of: upload)
        #expect(size.width == 64)
        #expect(size.height == 48)
    }

    @Test func turnsAnOrientedCaptureUpright() throws {
        // Orientation 6 is how a phone held upright tags a landscape sensor
        // frame: the pixels must be rotated a quarter turn to display.
        let upload = try #require(UploadImage.prepare(try makeJPEG(width: 40, height: 20, orientation: 6)))
        let size = try pixelSize(of: upload)
        #expect(size.width == 20)
        #expect(size.height == 40)
        let orientation = try properties(of: upload)[kCGImagePropertyOrientation as String] as? Int
        #expect(orientation == nil || orientation == 1, "the rotation is baked in, not left to the reader")
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(UploadImage.prepare(Data("not an image".utf8)) == nil)
    }
}
