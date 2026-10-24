import Foundation
import CoreLocation
import Observation

/// Location for tagging captures and for Découvertes.
///
/// A cold GPS can take well over ten seconds to fix, so the capture screen
/// warms it up as soon as it opens (`startWarmingUp`) and the shutter takes
/// whatever recent fix exists, instantly. When there is none yet, the photo is
/// still taken at once and `waitForFix` attaches the position when it arrives.
/// The first version asked for a single fix at the moment of the shutter with
/// a four-second limit, and a first capture outdoors routinely came back with
/// no position at all, invisible on the map.
///
/// Confined to the main actor on purpose. Two callers can race here (the
/// capture screen and Découvertes both ask for a fix, and Découvertes re-asks
/// every time the realm segment changes), and a bare class would let the second
/// request overwrite the first continuation, stranding the first caller forever.
/// On the main actor there is exactly one place that owns the continuation, and
/// a second request finishes the first one instead of dropping it.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// Whether the app may use the location. Observed by the capture screen,
    /// which says so when it may not.
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// A fix has arrived since the GPS started. Drives the capture screen's
    /// position indicator.
    private(set) var hasFix = false

    private let manager = CLLocationManager()
    @ObservationIgnored private var continuation: CheckedContinuation<CLLocation?, Never>?
    @ObservationIgnored private var bestFix: CLLocation?
    @ObservationIgnored private var latestFix: CLLocation?
    @ObservationIgnored private var desiredAccuracy: CLLocationAccuracy = 50
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    /// Continuous updates are wanted while the camera is open.
    @ObservationIgnored private var warm = false
    @ObservationIgnored private var waiters = 0
    @ObservationIgnored private var updating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorization = manager.authorizationStatus
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Keep the GPS running so a fix is ready when the shutter is pressed.
    func startWarmingUp() {
        warm = true
        requestAuthorization()
        startUpdatesIfAllowed()
    }

    func stopWarmingUp() {
        warm = false
        stopUpdatesIfIdle()
    }

    /// A fix from the last `maxAge` seconds, good to `maxAccuracy` metres.
    func recentFix(maxAge: TimeInterval = 120, maxAccuracy: CLLocationAccuracy = 200) -> CLLocation? {
        guard let fix = latestFix,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxAccuracy,
              -fix.timestamp.timeIntervalSinceNow <= maxAge else { return nil }
        return fix
    }

    /// Wait for a usable fix, for a photo taken before the GPS had one. Any
    /// number of these can wait at once, unlike `currentLocation`.
    func waitForFix(maxAccuracy: CLLocationAccuracy = 100, timeout: TimeInterval = 45) async -> CLLocation? {
        waiters += 1
        defer {
            waiters -= 1
            stopUpdatesIfIdle()
        }
        requestAuthorization()
        startUpdatesIfAllowed()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isDenied { return nil }
            if let fix = recentFix(maxAge: 60, maxAccuracy: maxAccuracy) { return fix }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        // Better a rough position than none: a sighting placed to the nearest
        // few hundred metres still lands in the right valley.
        return recentFix(maxAge: 120, maxAccuracy: 1_000)
    }

    /// Await a single location fix. Falls back to the best fix seen (or nil)
    /// after `timeout` seconds so nothing waits forever.
    func currentLocation(accuracy: CLLocationAccuracy = 50, timeout: TimeInterval = 10) async -> CLLocation? {
        // A request already in flight is settled with whatever it has rather
        // than being silently replaced.
        finish(with: bestFix)

        if let fix = recentFix(maxAge: 30, maxAccuracy: accuracy) { return fix }
        if isDenied { return nil }

        desiredAccuracy = accuracy
        bestFix = recentFix()
        return await withCheckedContinuation { cont in
            continuation = cont
            requestAuthorization()
            startUpdatesIfAllowed()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(with: self?.bestFix)
            }
        }
    }

    // MARK: Updates

    private func startUpdatesIfAllowed() {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways, !updating else { return }
        updating = true
        manager.startUpdatingLocation()
    }

    /// Stop the GPS once nobody needs it, to spare the battery.
    private func stopUpdatesIfIdle() {
        guard updating, !warm, waiters == 0, continuation == nil else { return }
        updating = false
        manager.stopUpdatingLocation()
    }

    /// Resume the pending continuation exactly once.
    private func finish(with location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: location)
        }
        stopUpdatesIfIdle()
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorization = manager.authorizationStatus
            if isDenied {
                finish(with: nil)
            } else if warm || waiters > 0 || continuation != nil {
                startUpdatesIfAllowed()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
            latestFix = loc
            if !hasFix { hasFix = true }
            if bestFix == nil || loc.horizontalAccuracy < (bestFix?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
                bestFix = loc
            }
            if loc.horizontalAccuracy <= desiredAccuracy { finish(with: loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            // "Location unknown" is transient while the GPS searches; only a
            // refusal ends the wait early.
            if (error as? CLError)?.code == .denied {
                finish(with: bestFix)
            }
        }
    }
}
