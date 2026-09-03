import Foundation
import CoreLocation

/// One-shot location for tagging a capture. Requests When-In-Use authorization
/// and returns the first fix that meets an accuracy threshold, or the best fix
/// seen before a short timeout, never blocking the shutter indefinitely.
///
/// Confined to the main actor on purpose. Two callers can race here (the
/// capture screen and Découvertes both ask for a fix, and Découvertes re-asks
/// every time the realm segment changes), and a bare class would let the second
/// request overwrite the first continuation, stranding the first caller forever.
/// On the main actor there is exactly one place that owns the continuation, and
/// a second request finishes the first one instead of dropping it.
@MainActor
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
        // A request already in flight is settled with whatever it has rather
        // than being silently replaced.
        finish(with: bestFix)

        desiredAccuracy = accuracy
        bestFix = nil
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(with: self?.bestFix)
            }
        }
    }

    /// Resume the pending continuation exactly once.
    private func finish(with location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: location)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let loc = locations.last else { return }
            if bestFix == nil || loc.horizontalAccuracy < (bestFix?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
                bestFix = loc
            }
            if loc.horizontalAccuracy <= desiredAccuracy { finish(with: loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            finish(with: bestFix)
        }
    }
}
