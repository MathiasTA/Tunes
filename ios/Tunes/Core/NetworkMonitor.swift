import Foundation
import Network
import Observation

/// Knows whether we're online, and whether the connection is Wi-Fi or mobile data.
@MainActor @Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private(set) var isWiFi = true
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in
                self?.isOnline = online
                self?.isWiFi = online && wifi && !expensive
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "tunes.network"))
    }

    /// Mobile data (or a hotspot / Low Data Mode connection).
    var onMobileData: Bool { isOnline && !isWiFi }
}
