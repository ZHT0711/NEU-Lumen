import Network
import Foundation

@MainActor
final class CampusNetworkMonitor {
    private var monitor: NWPathMonitor?
    private var signature: CampusNetworkPath?

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = CampusNetworkPath(connected: path.status == .satisfied,
                interfaces: [NWInterface.InterfaceType.wifi, .cellular, .wiredEthernet, .loopback, .other]
                    .filter { path.usesInterfaceType($0) }.map { String(describing: $0) }.sorted(),
                gateways: path.gateways.map { String(describing: $0) }.sorted(),
                expensive: path.isExpensive, constrained: path.isConstrained)
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.signature = signature }
                if self.signature != signature { onChange(signature.connected) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "edu.neu.lumen.network"))
    }

    deinit { monitor?.cancel() }
}
