import Foundation
import Network

public enum UDPTransportError: Error, Equatable, Sendable {
    case invalidHost
    case invalidPort(UInt16)
    case connectionFailed(String)
    case listenerFailed(String)
    case notReady
}

/// Sends framed audio packets over one connected UDP socket.
public final class UDPAudioSender: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let readyGate = ReadyGate()

    public init(host: String, port: UInt16) throws {
        guard !host.isEmpty else { throw UDPTransportError.invalidHost }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw UDPTransportError.invalidPort(port)
        }
        connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .udp)
        queue = DispatchQueue(label: "HushPort.UDPAudioSender")
        connection.start(queue: queue)
    }

    public init(endpoint: NWEndpoint) {
        connection = NWConnection(to: endpoint, using: .udp)
        queue = DispatchQueue(label: "HushPort.UDPAudioSender")
        connection.start(queue: queue)
    }

    public func prepare() async throws {
        try await readyGate.wait(for: connection)
    }

    public func send(_ packet: AudioPacket) async throws {
        let content = try packet.encoded()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: content, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: UDPTransportError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Best-effort send for realtime audio. Does not block on network stack backpressure.
    public func sendRealtime(_ packet: AudioPacket) throws {
        let content = try packet.encoded()
        connection.send(content: content, completion: .idempotent)
    }

    public func cancel() {
        connection.cancel()
    }

    deinit {
        connection.cancel()
    }
}

/// Listens for UDP datagrams and exposes valid audio packets as an AsyncStream.
public final class UDPAudioReceiver: @unchecked Sendable {
    public let packets: AsyncThrowingStream<AudioPacket, Error>

    private let listener: NWListener
    private let queue: DispatchQueue
    private let continuation: AsyncThrowingStream<AudioPacket, Error>.Continuation
    private let listenerReady = ListenerReadyGate()

    public init(
        port: UInt16,
        serviceName: String? = nil,
        deviceID: UUID? = nil,
        preferWiFi: Bool = false
    ) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw UDPTransportError.invalidPort(port)
        }

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        #if os(iOS)
        if preferWiFi {
            parameters.requiredInterfaceType = .wifi
        }
        #endif
        listener = try NWListener(using: parameters, on: endpointPort)
        if let serviceName {
            var txtRecord = NWTXTRecord()
            if let deviceID {
                txtRecord["id"] = deviceID.uuidString
            }
            listener.service = NWListener.Service(
                name: Self.sanitizedServiceName(serviceName),
                type: HushPortDiscovery.serviceType,
                txtRecord: txtRecord
            )
        }
        queue = DispatchQueue(label: "HushPort.UDPAudioReceiver")
        (packets, continuation) = AsyncThrowingStream.makeStream(
            bufferingPolicy: .bufferingNewest(512)
        )

        listener.stateUpdateHandler = { [continuation] state in
            switch state {
            case .failed(let error):
                continuation.finish(throwing: UDPTransportError.listenerFailed(error.localizedDescription))
            case .cancelled:
                continuation.finish()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [continuation, queue] connection in
            connection.start(queue: queue)
            Self.receive(on: connection, continuation: continuation)
        }
        listener.start(queue: queue)
    }

    public func prepare() async throws {
        try await listenerReady.wait(for: listener)
    }

    public func cancel() {
        listener.cancel()
        continuation.finish()
    }

    deinit {
        listener.cancel()
        continuation.finish()
    }

    private static func sanitizedServiceName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "HushPort" : String(sanitized.prefix(63))
    }

    private static func receive(
        on connection: NWConnection,
        continuation: AsyncThrowingStream<AudioPacket, Error>.Continuation
    ) {
        connection.receiveMessage { data, _, _, error in
            if let data, !data.isEmpty, let packet = try? AudioPacket(decoding: data) {
                continuation.yield(packet)
            }
            if error == nil {
                receive(on: connection, continuation: continuation)
            }
        }
    }
}

public enum PeerEndpointResolver {
    public static func resolveHost(for peer: HushPortPeer) async -> String? {
        if let host = NetworkEndpointHost.ipv4String(from: peer.endpoint), !host.isEmpty {
            return host
        }
        for attempt in 0..<3 {
            if let host = await resolveServiceHost(peer.endpoint, port: HushPortConstants.audioPort) {
                return host
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
            }
        }
        return nil
    }

    private static func resolveServiceHost(_ endpoint: NWEndpoint, port: UInt16) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                guard let resolved = try? await resolveService(endpoint, port: port),
                      let host = NetworkEndpointHost.ipv4String(from: resolved),
                      !host.isEmpty else {
                    return nil
                }
                return host
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(900))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    public static func resolveHost(from endpoint: NWEndpoint, port: UInt16 = HushPortConstants.audioPort) async -> String? {
        if let host = NetworkEndpointHost.ipv4String(from: endpoint), !host.isEmpty {
            return host
        }
        do {
            let resolved = try await resolveService(endpoint, port: port)
            return NetworkEndpointHost.ipv4String(from: resolved)
        } catch {
            return nil
        }
    }

    public static func controlEndpoint(for peer: HushPortPeer) async throws -> NWEndpoint {
        switch peer.endpoint {
        case let .hostPort(host, _):
            guard let port = NWEndpoint.Port(rawValue: HushPortConstants.controlPort) else {
                throw UDPTransportError.invalidPort(HushPortConstants.controlPort)
            }
            return .hostPort(host: host, port: port)
        default:
            return try await resolveService(peer.endpoint, port: HushPortConstants.controlPort)
        }
    }

    private static func resolveService(_ endpoint: NWEndpoint, port: UInt16) async throws -> NWEndpoint {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw UDPTransportError.invalidPort(port)
        }
        let connection = NWConnection(to: endpoint, using: .udp)
        let queue = DispatchQueue(label: "HushPort.EndpointResolver")
        connection.start(queue: queue)
        let gate = ReadyGate()
        try await gate.wait(for: connection)
        defer { connection.cancel() }
        if case let .hostPort(host, _) = connection.currentPath?.remoteEndpoint {
            return .hostPort(host: host, port: endpointPort)
        }
        throw UDPTransportError.connectionFailed("Could not resolve peer address")
    }
}

public struct HushPortPeer: Hashable, @unchecked Sendable, Identifiable {
    public let name: String
    public let endpoint: NWEndpoint
    public let detail: String?
    public let deviceID: UUID?

    public var id: String {
        if let deviceID {
            return deviceID.uuidString
        }
        return "\(name)-\(detail ?? "\(endpoint)")"
    }

    public var displayName: String {
        if let detail {
            return "\(name) (\(detail))"
        }
        return name
    }

    public init(name: String, endpoint: NWEndpoint, detail: String? = nil, deviceID: UUID? = nil) {
        self.name = name
        self.endpoint = endpoint
        self.detail = detail
        self.deviceID = deviceID
    }
}

public final class HushPortDiscovery: @unchecked Sendable {
    public static let serviceType = HushPortConstants.bonjourServiceType

    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "HushPort.Discovery")
    private let onChange: @Sendable ([HushPortPeer]) -> Void

    public init(onChange: @escaping @Sendable ([HushPortPeer]) -> Void) {
        self.onChange = onChange
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [onChange] results, _ in
            let peers = results.compactMap { result -> HushPortPeer? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                let deviceID = Self.deviceID(from: result)
                let detail = Self.describe(endpoint: result.endpoint)
                return HushPortPeer(name: name, endpoint: result.endpoint, detail: detail, deviceID: deviceID)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            onChange(peers)
        }
        browser.start(queue: queue)
    }

    public func cancel() {
        browser.cancel()
    }

    deinit {
        browser.cancel()
    }

    private static func describe(endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case let .hostPort(host, port):
            return "\(host):\(port)"
        case let .service(name, type, domain, _):
            let domainSuffix = domain.isEmpty ? "" : ".\(domain)"
            return "\(name).\(type)\(domainSuffix)"
        default:
            return nil
        }
    }

    private static func deviceID(from result: NWBrowser.Result) -> UUID? {
        guard case let .bonjour(txtRecord) = result.metadata,
              let idString = txtRecord["id"],
              let id = UUID(uuidString: idString) else {
            return nil
        }
        return id
    }
}
