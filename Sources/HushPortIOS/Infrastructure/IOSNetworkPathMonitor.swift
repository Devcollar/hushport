#if os(iOS)
import HushPortCore
import Network

@MainActor
final class IOSNetworkPathMonitor {
    struct Snapshot: Sendable {
        var isSatisfied: Bool
        var usesWiFi: Bool
        var usesCellular: Bool
        var interfaceNames: String
        var localIPAddress: String?

        var networkSignature: String {
            "\(interfaceNames)|\(localIPAddress ?? "none")|\(isSatisfied)"
        }
    }

    private let monitor = NWPathMonitor()
    private(set) var snapshot = Snapshot(
        isSatisfied: true,
        usesWiFi: true,
        usesCellular: false,
        interfaceNames: "",
        localIPAddress: NetworkAddress.localIPv4Address()
    )
    var onUpdate: (@MainActor (Snapshot) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let interfaceNames = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            let snapshot = Snapshot(
                isSatisfied: path.status == .satisfied,
                usesWiFi: path.usesInterfaceType(.wifi),
                usesCellular: path.usesInterfaceType(.cellular),
                interfaceNames: interfaceNames,
                localIPAddress: NetworkAddress.localIPv4Address()
            )
            Task { @MainActor in
                guard let self else { return }
                self.snapshot = snapshot
                self.onUpdate?(snapshot)
            }
        }
        monitor.start(queue: DispatchQueue(label: "HushPort.NetworkPath"))
    }

    func stop() {
        monitor.cancel()
    }
}
#endif
