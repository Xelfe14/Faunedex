import Foundation
import ImageIO
import CoreGraphics

/// Prepares a picture for a knowledge card: small enough to sync, upright, and
/// stripped of everything but pixels.
///
/// Three things happen, each for a concrete reason:
///
/// 1. The longest side is brought down to `maxPixelSize` (never up). An iPhone
///    photo weighs several megabytes; a card needs a few hundred kilobytes, and
///    iCloud has to carry every one of them.
/// 2. The EXIF orientation is applied to the pixels. Phones store most photos
///    sideways plus a "rotate me" flag; once the metadata is gone the flag is
///    gone too, so the rotation has to be baked in first.
/// 3. The result is re-encoded from bare pixels, so no metadata survives, GPS
///    position included. A photo pasted onto a vocabulary card should not
///    carry the coordinates of the kitchen it was taken in.
///
/// Transparency is flattened onto white, because JPEG has no alpha channel and
/// the alternative is transparent pixels silently turning black.
public enum ImageDownscaler {

    public struct Output: Sendable, Equatable {
        public let data: Data
        public let pixelWidth: Int
        public let pixelHeight: Int
    }

    public static let defaultMaxPixelSize = 1600
    public static let defaultQuality = 0.8

    public static func downscale(
        _ data: Data,
        maxPixelSize: Int = defaultMaxPixelSize,
        quality: Double = defaultQuality
    ) -> Output? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height)
        // Asking for more pixels than the source has would upscale it.
        let target = longest > 0 ? min(maxPixelSize, longest) : maxPixelSize

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let flat = flattenedOnWhite(scaled) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let encodeOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, flat, encodeOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Output(data: output as Data, pixelWidth: flat.width, pixelHeight: flat.height)
    }

    /// Draw the image on an opaque white canvas of the same size.
    static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage()
    }
}
