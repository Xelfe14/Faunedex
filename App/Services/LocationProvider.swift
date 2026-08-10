import Foundation
import CoreLocation

/// One-shot location for tagging a capture. Requests When-In-Use authorization
/// and returns the first fix that meets an accuracy threshold, or the best fix
/// seen before a short timeout — never blocking the shutter indefinitely.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var bestFix: CLLocation?
    private var desiredAccuracy: CLLocationAccuracy = 50
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Await a single location fix. Falls back to the best fix seen (or nil)
    /// after `timeout` seconds so capture is never held up.
    func currentLocation(accuracy: CLLocationAccuracy = 50, timeout: TimeInterval = 4) async -> CLLocation? {
        desiredAccuracy = accuracy
        bestFix = nil
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(with: self?.bestFix)
            }
        }
    }

    private func finish(with location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        if bestFix == nil || loc.horizontalAccuracy < (bestFix?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
            bestFix = loc
        }
        if loc.horizontalAccuracy <= desiredAccuracy { finish(with: loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: bestFix)
    }
}
