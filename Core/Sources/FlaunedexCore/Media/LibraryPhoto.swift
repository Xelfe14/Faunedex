import Foundation
import ImageIO
import CoreGraphics

/// A photo chosen from the library, to be identified like one just taken.
///
/// It is stored like a capture: an upright JPEG of bounded size, whatever it
/// came as (HEIC, PNG, a 48 MP original). Where and when it was taken are read
/// from its metadata and kept on the copy, so an old walk's photo lands on
/// the map where it was taken and in the journal on its own day, not today.
public struct LibraryPhoto: Sendable {
    public let jpeg: Data
    public let latitude: Double?
    public let longitude: Double?
    /// The GPS error in metres, when the photo records one.
    public let horizontalAccuracy: Double?
    public let takenAt: Date?

    /// Longest edge kept, the size of a 12 MP capture's.
    public static let maxPixelSize = 4032

    /// Returns nil if `data` isn't a decodable image. `timeZone` is where the
    /// photo is assumed to have been taken when it doesn't say.
    public init?(_ data: Data, maxPixelSize: Int = LibraryPhoto.maxPixelSize, timeZone: TimeZone = .current) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        guard let jpeg = Self.jpeg(from: source, properties: properties, maxPixelSize: maxPixelSize) else {
            return nil
        }
        self.jpeg = jpeg
        let coordinate = ExifGPS.coordinate(in: properties)
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        horizontalAccuracy = coordinate == nil ? nil : gps?[kCGImagePropertyGPSHPositioningError as String] as? Double
        takenAt = Self.date(in: properties, timeZone: timeZone)
    }

    /// Re-encode as JPEG, turned upright and scaled down if needed, keeping
    /// the EXIF, GPS and TIFF metadata.
    private static func jpeg(from source: CGImageSource, properties: [String: Any], maxPixelSize: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // The pixels are upright now, so the orientation tag must say so.
        var metadata: [String: Any] = [
            kCGImagePropertyOrientation as String: 1,
            kCGImageDestinationLossyCompressionQuality as String: 0.9,
        ]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary] {
            if let dictionary = properties[key as String] { metadata[key as String] = dictionary }
        }
        if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            metadata[kCGImagePropertyTIFFDictionary as String] = tiff
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// When the photo was taken: EXIF's original date, in the time zone it
    /// records, else `timeZone`. Falls back to the digitised and TIFF dates.
    static func date(in properties: [String: Any], timeZone: TimeZone) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let candidates: [(String?, String?)] = [
            (exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
             exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String),
            (exif[kCGImagePropertyExifDateTimeDigitized as String] as? String,
             exif[kCGImagePropertyExifOffsetTimeDigitized as String] as? String),
            (tiff[kCGImagePropertyTIFFDateTime as String] as? String,
             exif[kCGImagePropertyExifOffsetTime as String] as? String),
        ]
        for case let (stamp?, offset) in candidates {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = offset.flatMap(Self.timeZone(offset:)) ?? timeZone
            if let date = formatter.date(from: stamp) { return date }
        }
        return nil
    }

    /// "+02:00" or "-05:30" as a time zone.
    static func timeZone(offset: String) -> TimeZone? {
        let parts = offset.dropFirst().split(separator: ":")
        guard let sign = offset.first, sign == "+" || sign == "-",
              parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }
}
