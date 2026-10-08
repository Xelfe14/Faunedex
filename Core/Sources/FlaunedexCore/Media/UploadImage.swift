import Foundation
import ImageIO
import CoreGraphics

/// Prepares a captured photo for the identification request.
///
/// The capture kept on disk is the full-resolution JPEG with the sighting's GPS
/// embedded, which is right for the journal and the map but wrong to send. At
/// several megabytes a scan it is slow over the patchy signal the app is used
/// in, and the coordinates of where someone walks are not Google's to have.
/// What goes to Gemini is a re-encoded copy: scaled down, turned upright, and
/// carrying no metadata at all.
public enum UploadImage {

    /// Longest edge, in pixels, of the image sent for identification. Ample for
    /// telling species apart, and a fraction of a 12 MP capture.
    public static let maxPixelSize = 1600

    /// A downscaled, upright JPEG with no EXIF, GPS or TIFF metadata. Returns
    /// nil if `imageData` isn't a decodable image.
    public static func prepare(
        _ imageData: Data,
        maxPixelSize: Int = UploadImage.maxPixelSize,
        quality: Double = 0.8
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            // Decode the real image, never the small preview a JPEG may embed.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Apply the EXIF orientation, so the model sees the photo upright
            // even though the orientation tag is about to be dropped.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        // Adding the bare CGImage rather than the source is what strips the
        // metadata: only the properties passed here are written.
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
