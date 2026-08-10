import Foundation
import CoreLocation

/// Coordinate → ISO country code, deferred and online-only (it must never block
/// capture). Uses `CLGeocoder`, which returns a clean `isoCountryCode`.
///
/// The iOS 26 `MKReverseGeocodingRequest` is a drop-in replacement behind this
/// same call site when the deployment target is raised.
struct ReverseGeocoder {
    private let geocoder = CLGeocoder()

    /// Returns the uppercase ISO alpha-2 country code, or nil if offline/unknown.
    func countryISO(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.isoCountryCode?.uppercased()
        } catch {
            return nil
        }
    }
}
