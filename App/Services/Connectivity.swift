import Foundation
import Network
import Observation

/// Observable network-reachability using `NWPathMonitor` — the source of truth
/// for draining the offline scan queue. Publishes `isOnline` and a monotonic
/// `becameOnlineTick` the ingestion layer can react to.
@Observable
final class Connectivity {
    private(set) var isOnline: Bool = true
    /// Increments each time connectivity is (re)gained; observers drain on change.
    private(set) var becameOnlineTick: Int = 0

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.taddeocarpinelli.flaunedex.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            Task { @MainActor in
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline { self.becameOnlineTick += 1 }
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
