import Foundation
import Network

public enum StreamTargetResolver {
    public enum Source: Equatable, Sendable {
        case bonjourPeer
        case pairedDeviceAddress
        case manualHost
    }

    public struct Target: Equatable, Sendable {
        public let host: String
        public let port: UInt16
        public let source: Source

        public init(host: String, port: UInt16, source: Source) {
            self.host = host
            self.port = port
            self.source = source
        }
    }

    public static func candidateHosts(
        resolvedPeerHosts: [String],
        pairedDevice: TrustedDevice?,
        manualHost: String
    ) -> [String] {
        var seen = Set<String>()
        var hosts: [String] = []

        func add(_ host: String?) {
            guard let host else { return }
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            hosts.append(trimmed)
        }

        for host in resolvedPeerHosts {
            add(host)
        }
        add(pairedDevice?.networkAddress)
        add(manualHost)
        return hosts
    }

    public static func resolve(
        peer: HushPortPeer?,
        pairedDevice: TrustedDevice?,
        manualHost: String,
        manualPort: UInt16 = HushPortConstants.audioPort,
        allowStalePairedAddress: Bool = false
    ) -> Target? {
        resolve(
            peer: peer,
            resolvedPeerHost: nil,
            pairedDevice: pairedDevice,
            manualHost: manualHost,
            manualPort: manualPort,
            allowStalePairedAddress: allowStalePairedAddress
        )
    }

    public static func resolve(
        peer: HushPortPeer?,
        resolvedPeerHost: String?,
        pairedDevice: TrustedDevice?,
        manualHost: String,
        manualPort: UInt16 = HushPortConstants.audioPort,
        allowStalePairedAddress: Bool = false
    ) -> Target? {
        if let resolvedPeerHost, !resolvedPeerHost.isEmpty {
            return Target(host: resolvedPeerHost, port: manualPort, source: .bonjourPeer)
        }

        if let peer,
           let host = NetworkEndpointHost.ipv4String(from: peer.endpoint),
           !host.isEmpty {
            return Target(host: host, port: manualPort, source: .bonjourPeer)
        }

        if allowStalePairedAddress,
           let address = pairedDevice?.networkAddress,
           !address.isEmpty {
            return Target(host: address, port: manualPort, source: .pairedDeviceAddress)
        }

        let trimmedHost = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHost.isEmpty {
            return Target(host: trimmedHost, port: manualPort, source: .manualHost)
        }

        return nil
    }
}

public enum NetworkEndpointHost {
    public static func ipv4String(from endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        return ipv4String(from: host)
    }

    public static func ipv4String(from host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let address):
            return String(describing: address)
        case .name(let name, _):
            return name.isEmpty ? nil : name
        case .ipv6:
            return nil
        @unknown default:
            let value = String(describing: host)
            return value.contains(".") ? value : nil
        }
    }
}
