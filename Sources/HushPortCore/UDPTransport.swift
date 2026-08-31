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
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        connection = NWConnection(to: endpoint, using: parameters)
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
    private let lock = NSLock()
    private var hasCancelled = false

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
                type: HushPortConstants.bonjourServiceType,
                txtRecord: txtRecord
            )
        }
        queue = DispatchQueue(label: "HushPort.UDPAudioReceiver")
        (packets, continuation) = AsyncThrowingStream.makeStream(
            bufferingPolicy: .bufferingNewest(512)
        )

        listener.serviceRegistrationUpdateHandler = { change in
            #if DEBUG
            switch change {
            case .add(let endpoint):
                print("[AUDIO][listener] event=serviceRegistered type=\(HushPortConstants.bonjourServiceType) endpoint=\(endpoint)")
            case .remove(let endpoint):
                print("[AUDIO][listener] event=serviceRemoved type=\(HushPortConstants.bonjourServiceType) endpoint=\(endpoint)")
            @unknown default:
                break
            }
            #endif
        }

        listener.stateUpdateHandler = { [continuation] state in
            switch state {
            case .ready:
                #if DEBUG
                print("[AUDIO][listener] event=listenerReady port=\(port)")
                #endif
            case .failed(let error):
                #if DEBUG
                print("[AUDIO][listener] event=listenerFailed error=\(error.localizedDescription)")
                #endif
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
        lock.lock()
        defer { lock.unlock() }
        guard !hasCancelled else { return }
        hasCancelled = true
        listener.cancel()
        continuation.finish()
    }

    deinit {
        cancel()
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

    public init(receiver: DiscoveredReceiver, endpoint: NWEndpoint) {
        self.name = receiver.displayName
        self.endpoint = endpoint
        self.detail = Self.describe(endpoint: endpoint)
        self.deviceID = receiver.deviceID
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
}

public final class ReceiverDiscovery: @unchecked Sendable {
    public let registry: ReceiverRegistry

    private let audioBrowser: NWBrowser
    private let controlBrowser: NWBrowser
    private let queue = DispatchQueue(label: "HushPort.ReceiverDiscovery")
    private let onChange: @Sendable ([DiscoveredReceiver]) -> Void
    private var knownAudioEndpoints: [UUID: NWEndpoint] = [:]
    private var knownControlEndpoints: [UUID: NWEndpoint] = [:]

    public init(
        onChange: @escaping @Sendable ([DiscoveredReceiver]) -> Void,
        onBrowseIssue: (@Sendable (String) -> Void)? = nil
    ) {
        self.onChange = onChange
        registry = ReceiverRegistry()
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        audioBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: HushPortConstants.bonjourServiceType, domain: nil),
            using: parameters
        )
        controlBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: HushPortConstants.controlBonjourServiceType, domain: nil),
            using: parameters
        )

        let reportIssue = onBrowseIssue
        audioBrowser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                #if DEBUG
                print("[HushPort] audio browser ready")
                #endif
            case .failed(let error):
                #if DEBUG
                print("[HushPort] audio browser failed: \(error.localizedDescription)")
                #endif
                reportIssue?("audio: \(error.localizedDescription)")
            default:
                break
            }
        }
        controlBrowser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                #if DEBUG
                print("[HushPort] control browser ready")
                #endif
            case .failed(let error):
                #if DEBUG
                print("[HushPort] control browser failed: \(error.localizedDescription)")
                #endif
                reportIssue?("control: \(error.localizedDescription)")
            default:
                break
            }
        }

        audioBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleAudioResults(results, changes: changes)
        }
        controlBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleControlResults(results, changes: changes)
        }
        audioBrowser.start(queue: queue)
        controlBrowser.start(queue: queue)
    }

    public func cancel() {
        audioBrowser.cancel()
        controlBrowser.cancel()
        registry.reset()
    }

    deinit {
        cancel()
    }

    private func handleAudioResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        _ = changes
        var latest: [UUID: (String, NWEndpoint)] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint,
                  let deviceID = Self.deviceID(from: result) else { continue }
            latest[deviceID] = (name, result.endpoint)
        }

        var revisionChanged = false
        for oldID in knownAudioEndpoints.keys where latest[oldID] == nil {
            knownAudioEndpoints.removeValue(forKey: oldID)
            if registry.removeAudio(deviceID: oldID) != nil {
                revisionChanged = true
            }
        }
        for (deviceID, entry) in latest {
            knownAudioEndpoints[deviceID] = entry.1
            if registry.updateAudio(deviceID: deviceID, displayName: entry.0, endpoint: entry.1) != nil {
                revisionChanged = true
                #if DEBUG
                print("[HushPort] discovered audio service device=\(deviceID) endpoint=\(entry.1)")
                #endif
            }
        }
        if revisionChanged {
            emitRegistryUpdate()
        }
    }

    private func handleControlResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        _ = changes
        var latest: [UUID: (String, NWEndpoint)] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint,
                  let deviceID = Self.deviceID(from: result) else { continue }
            latest[deviceID] = (name, result.endpoint)
        }

        var revisionChanged = false
        for oldID in knownControlEndpoints.keys where latest[oldID] == nil {
            knownControlEndpoints.removeValue(forKey: oldID)
            if registry.removeControl(deviceID: oldID) != nil {
                revisionChanged = true
            }
        }
        for (deviceID, entry) in latest {
            knownControlEndpoints[deviceID] = entry.1
            if registry.updateControl(deviceID: deviceID, displayName: entry.0, endpoint: entry.1) != nil {
                revisionChanged = true
                #if DEBUG
                print("[HushPort] discovered control service device=\(deviceID) endpoint=\(entry.1)")
                #endif
            }
        }
        if revisionChanged {
            emitRegistryUpdate()
        }
    }

    private func emitRegistryUpdate() {
        let receivers = registry.allReceivers()
        for receiver in receivers where receiver.isReady {
            #if DEBUG
            print("[HushPort] receiver registry ready device=\(receiver.deviceID) revision=\(receiver.routeRevision)")
            #endif
        }
        onChange(receivers)
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

@available(*, deprecated, renamed: "ReceiverDiscovery")
public typealias HushPortDiscovery = ReceiverDiscovery

extension ReceiverDiscovery {
    public static let serviceType = HushPortConstants.bonjourServiceType
}

