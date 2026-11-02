import Network
import Foundation

@MainActor
final class CampusNetworkMonitor {
    private var monitor: NWPathMonitor?
    private var signature: String?

    func start(onChange: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = "\(path.status)|\(path.availableInterfaces.map { $0.name }.sorted())|\(path.isExpensive)"
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.signature = signature }
                if let previous = self.signature, previous != signature { onChange() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "edu.neu.lumen.network"))
    }

    deinit { monitor?.cancel() }
}
