import Foundation
import Network

public enum ControlChannelError: Error, Equatable, Sendable {
    case invalidPort(UInt16)
    case sendFailed(String)
    case listenerFailed(String)
    case notReady(String)
}

public struct ControlMessageEvent: Sendable {
    public let message: ControlMessage
    public let replyEndpoint: NWEndpoint
    /// Sends a response on the exact inbound UDP flow accepted by NWListener.
    /// This preserves the listener's local port (49201) and the peer's ephemeral
    /// source port, which is required for request/reply on a connected UDP socket.
    public let directReply: ControlChannelDirectReply
}

public final class ControlChannelDirectReply: @unchecked Sendable {
    private let connection: NWConnection

    fileprivate init(connection: NWConnection) {
        self.connection = connection
    }

    public func send(_ message: ControlMessage) async throws {
        let payload = try message.encoded()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: ControlChannelError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

public enum ControlReplyEndpoint {
    /// Replies to the peer's control listener on the standard control port.
    public static func resolve(
        _ endpoint: NWEndpoint,
        port: UInt16 = HushPortConstants.controlPort
    ) -> NWEndpoint? {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }
        if case let .hostPort(host, _) = endpoint {
            return .hostPort(host: host, port: endpointPort)
        }
        return nil
    }
}

public enum PairingClientError: LocalizedError, Equatable, Sendable {
    case timeout
    case rejected

    public var errorDescription: String? {
        switch self {
        case .timeout:
            "Pairing timed out. Make sure HushPort is open on both devices and try again."
        case .rejected:
            "Pairing was rejected. Refresh the code on your Mac and try again."
        }
    }
}

enum ControlChannelDebug {
    static func log(_ platform: String, _ message: String) {
        #if DEBUG
        print("[CTRL][\(platform)] \(message)")
        #endif
    }
}

private final class ControlReceiveCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?

    init(_ continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func finish(_ data: Data?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: data)
    }
}

public final class ControlChannelSender: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "HushPort.ControlSender")
    private let readyGate = ReadyGate()
    private let lock = NSLock()
    private var hasCancelled = false
    private let debugPlatform: String

    public init(endpoint: NWEndpoint, debugPlatform: String = "sender") {
        self.debugPlatform = debugPlatform
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        connection = NWConnection(to: endpoint, using: parameters)
        installStateLogging()
        connection.start(queue: queue)
        ControlChannelDebug.log(debugPlatform, "event=connectionCreated endpoint=\(endpoint)")
    }

    public init(host: String, port: UInt16 = HushPortConstants.controlPort, debugPlatform: String = "sender") throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ControlChannelError.invalidPort(port)
        }
        self.debugPlatform = debugPlatform
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
        installStateLogging()
        connection.start(queue: queue)
        ControlChannelDebug.log(debugPlatform, "event=connectionCreated host=\(host) port=\(port)")
    }

    private func installStateLogging() {
        connection.stateUpdateHandler = { [debugPlatform] state in
            switch state {
            case .preparing:
                ControlChannelDebug.log(debugPlatform, "event=connectionState state=preparing")
            case .ready:
                ControlChannelDebug.log(debugPlatform, "event=connectionState state=ready")
            case .failed(let error):
                ControlChannelDebug.log(debugPlatform, "event=connectionState state=failed error=\(error.localizedDescription)")
            case .cancelled:
                ControlChannelDebug.log(debugPlatform, "event=connectionState state=cancelled")
            case .waiting(let error):
                ControlChannelDebug.log(debugPlatform, "event=connectionState state=waiting error=\(String(describing: error))")
            @unknown default:
                ControlChannelDebug.log(debugPlatform, "event=connectionState state=unknown")
            }
        }
    }

    public func prepare() async throws {
        try await readyGate.wait(for: connection)
    }

    public func send(_ message: ControlMessage) async throws {
        try await readyGate.wait(for: connection)
        let payload = try message.encoded()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.send(content: payload, completion: .contentProcessed { [self] error in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                if let error {
                    ControlChannelDebug.log(
                        self.debugPlatform,
                        "event=sendCompleted error=\(error.localizedDescription)"
                    )
                    continuation.resume(throwing: ControlChannelError.sendFailed(error.localizedDescription))
                } else {
                    ControlChannelDebug.log(self.debugPlatform, "event=sendCompleted error=none")
                    continuation.resume()
                }
            })
        }
    }

    /// Waits for one inbound datagram on this connection (UDP reply path).
    ///
    /// This deliberately does not use a task group for the timeout. A pending
    /// `receiveMessage` callback is not cancelled by `Task.cancel()`, so a task
    /// group can otherwise wait forever for the receive child after timeout.
    public func receive(timeout: Duration) async -> Data? {
        do {
            try await readyGate.wait(for: connection)
        } catch {
            return nil
        }

        let data = await withCheckedContinuation { continuation in
            let completion = ControlReceiveCompletion(continuation)
            connection.receiveMessage { data, _, _, error in
                completion.finish(error == nil ? data : nil)
            }
            Task {
                try? await Task.sleep(for: timeout)
                completion.finish(nil)
            }
        }

        if let data, !data.isEmpty {
            ControlChannelDebug.log(debugPlatform, "event=receiveCompleted bytes=\(data.count)")
        } else {
            ControlChannelDebug.log(debugPlatform, "event=receiveCompleted bytes=0")
        }
        return data
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCancelled else { return }
        hasCancelled = true
        connection.cancel()
    }

    deinit {
        cancel()
    }
}

public final class ControlChannelReceiver: @unchecked Sendable {
    public let events: AsyncThrowingStream<ControlMessageEvent, Error>

    private let listener: NWListener
    private let queue = DispatchQueue(label: "HushPort.ControlReceiver")
    private let continuation: AsyncThrowingStream<ControlMessageEvent, Error>.Continuation
    private let lock = NSLock()
    private var hasCancelled = false

    public init(
        port: UInt16 = HushPortConstants.controlPort,
        serviceName: String? = nil,
        deviceID: UUID? = nil,
        preferWiFi: Bool = false
    ) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ControlChannelError.invalidPort(port)
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
        if let serviceName, let deviceID {
            var txtRecord = NWTXTRecord()
            txtRecord["id"] = deviceID.uuidString
            listener.service = NWListener.Service(
                name: Self.sanitizedServiceName(serviceName),
                type: HushPortConstants.controlBonjourServiceType,
                txtRecord: txtRecord
            )
        }
        (events, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingNewest(32))

        listener.serviceRegistrationUpdateHandler = { change in
            switch change {
            case .add(let endpoint):
                ControlChannelDebug.log("listener", "event=serviceRegistered type=\(HushPortConstants.controlBonjourServiceType) endpoint=\(endpoint)")
            case .remove(let endpoint):
                ControlChannelDebug.log("listener", "event=serviceRemoved type=\(HushPortConstants.controlBonjourServiceType) endpoint=\(endpoint)")
            @unknown default:
                break
            }
        }

        listener.stateUpdateHandler = { [continuation] state in
            switch state {
            case .ready:
                ControlChannelDebug.log("listener", "event=listenerReady port=\(port)")
            case .failed(let error):
                continuation.finish(throwing: ControlChannelError.listenerFailed(error.localizedDescription))
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
        continuation: AsyncThrowingStream<ControlMessageEvent, Error>.Continuation
    ) {
        connection.receiveMessage { data, _, _, error in
            if let data, !data.isEmpty {
                if let message = try? ControlMessage(decoding: data),
                   let replyEndpoint = connection.currentPath?.remoteEndpoint ?? Optional(connection.endpoint) {
                    ControlChannelDebug.log(
                        "listener",
                        "event=messageReceived type=\(message.type.rawValue) senderID=\(message.senderID) reply=\(replyEndpoint)"
                    )
                    continuation.yield(
                        ControlMessageEvent(
                            message: message,
                            replyEndpoint: replyEndpoint,
                            directReply: ControlChannelDirectReply(connection: connection)
                        )
                    )
                } else {
                    ControlChannelDebug.log(
                        "listener",
                        "event=messageDropped bytes=\(data.count) decodeFailed=\(error != nil)"
                    )
                }
            }
            if error == nil {
                receive(on: connection, continuation: continuation)
            }
        }
    }
}
