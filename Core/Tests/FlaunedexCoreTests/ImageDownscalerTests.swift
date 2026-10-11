import Testing
import Foundation
import ImageIO
import CoreGraphics
@testable import FlaunedexCore

/// Card pictures: shrunk, upright, and carrying nothing but pixels.
struct ImageDownscalerTests {

    /// A real encoded image to feed the downscaler.
    private func makeImage(width: Int, height: Int, transparent: Bool = false,
                           orientation: Int? = nil) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = transparent ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: space, bitmapInfo: info))
        if transparent {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let image = try #require(context.makeImage())

        let out = NSMutableData()
        let type = (transparent ? "public.png" : "public.jpeg") as CFString
        let destination = try #require(CGImageDestinationCreateWithData(out as CFMutableData, type, 1, nil))
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return out as Data
    }

    @Test func aLargePhotoIsBroughtDownToTheLimit() throws {
        let output = try #require(ImageDownscaler.downscale(try makeImage(width: 3200, height: 2400)))
        #expect(output.pixelWidth == 1600)
        #expect(output.pixelHeight == 1200)
    }

    @Test func aSmallPictureIsNeverEnlarged() throws {
        let output = try #require(ImageDownscaler.downscale(try makeImage(width: 300, height: 200)))
        #expect(output.pixelWidth == 300)
        #expect(output.pixelHeight == 200)
    }

    @Test func theResultIsAJPEG() throws {
        let output = try #require(ImageDownscaler.downscale(try makeImage(width: 400, height: 400)))
        let source = try #require(CGImageSourceCreateWithData(output.data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
    }

    @Test func aSidewaysPhoneShotIsStoodUpright() throws {
        // Orientation 6 means "stored landscape, display rotated 90°".
        let sideways = try makeImage(width: 400, height: 200, orientation: 6)
        let output = try #require(ImageDownscaler.downscale(sideways))
        #expect(output.pixelWidth == 200)
        #expect(output.pixelHeight == 400)
    }

    @Test func theGPSPositionIsStripped() throws {
        let tagged = try #require(ExifGPS.inject(into: try makeImage(width: 500, height: 300),
                                                 latitude: 45.9237, longitude: 6.8694))
        #expect(ExifGPS.readCoordinate(from: tagged) != nil, "the input really carries a position")
        let output = try #require(ImageDownscaler.downscale(tagged))
        #expect(ExifGPS.readCoordinate(from: output.data) == nil)
    }

    @Test func transparencyBecomesWhiteNotBlack() throws {
        let output = try #require(ImageDownscaler.downscale(try makeImage(width: 64, height: 64, transparent: true)))
        let source = try #require(CGImageSourceCreateWithData(output.data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240, "pixel \(pixel)")
    }

    @Test func somethingThatIsNotAPictureGivesNothing() {
        #expect(ImageDownscaler.downscale(Data("pas une image".utf8)) == nil)
        #expect(ImageDownscaler.downscale(Data()) == nil)
    }

    @Test func aZeroLimitGivesNothing() throws {
        #expect(ImageDownscaler.downscale(try makeImage(width: 10, height: 10), maxPixelSize: 0) == nil)
    }
}
