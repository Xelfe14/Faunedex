import Foundation
import ImageIO
import CoreGraphics

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Writes and reads EXIF GPS metadata on image data.
///
/// A custom AVFoundation camera does **not** embed GPS in captured photos, so
/// the app injects it itself. Doing it here with ImageIO (rather than through
/// AVFoundation's replacement-metadata API) keeps the logic platform-neutral and
/// unit-testable on macOS — GPS tagging is what makes the sightings map work, so
/// it's worth proving rather than assuming.
public enum ExifGPS {

    /// Build the EXIF GPS dictionary for a coordinate.
    public static func gpsDictionary(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        timestamp: Date? = nil
    ) -> [String: Any] {
        var gps: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(latitude),
            kCGImagePropertyGPSLatitudeRef as String: latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(longitude),
            kCGImagePropertyGPSLongitudeRef as String: longitude >= 0 ? "E" : "W",
        ]
        if let altitude {
            gps[kCGImagePropertyGPSAltitude as String] = abs(altitude)
            // 0 = above sea level, 1 = below.
            gps[kCGImagePropertyGPSAltitudeRef as String] = altitude >= 0 ? 0 : 1
        }
        if let horizontalAccuracy, horizontalAccuracy >= 0 {
            gps[kCGImagePropertyGPSHPositioningError as String] = horizontalAccuracy
        }
        if let timestamp {
            gps[kCGImagePropertyGPSDateStamp as String] = dateStampFormatter.string(from: timestamp)
            gps[kCGImagePropertyGPSTimeStamp as String] = timeStampFormatter.string(from: timestamp)
        }
        return gps
    }

    /// Return a copy of `imageData` with EXIF GPS embedded. Returns nil if the
    /// data isn't a decodable image.
    public static func inject(
        into imageData: Data,
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        timestamp: Date? = nil
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        properties[kCGImagePropertyGPSDictionary as String] = gpsDictionary(
            latitude: latitude, longitude: longitude, altitude: altitude,
            horizontalAccuracy: horizontalAccuracy, timestamp: timestamp
        )

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Read a coordinate back out of image data, converting the hemisphere refs
    /// into signed degrees. Returns nil when there is no GPS block.
    public static func readCoordinate(from imageData: Data) -> (latitude: Double, longitude: Double)? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double
        else { return nil }

        let latRef = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String) ?? "N"
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String) ?? "E"
        return (latRef.uppercased() == "S" ? -lat : lat,
                lonRef.uppercased() == "W" ? -lon : lon)
    }

    private static let dateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let timeStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
