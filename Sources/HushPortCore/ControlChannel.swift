import Foundation
import Network

public enum ControlChannelError: Error, Equatable, Sendable {
    case invalidPort(UInt16)
    case sendFailed(String)
    case listenerFailed(String)
}

public struct ControlMessageEvent: Sendable {
    public let message: ControlMessage
    public let replyEndpoint: NWEndpoint
}

public enum ControlReplyEndpoint {
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

public final class ControlChannelSender: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "HushPort.ControlSender")
    private let readyGate = ReadyGate()

    public init(endpoint: NWEndpoint) {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        connection = NWConnection(to: endpoint, using: parameters)
        connection.start(queue: queue)
    }

    public init(host: String, port: UInt16 = HushPortConstants.controlPort) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ControlChannelError.invalidPort(port)
        }
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
        connection.start(queue: queue)
    }

    public func prepare() async throws {
        try await readyGate.wait(for: connection)
    }

    public func send(_ message: ControlMessage) async throws {
        try await readyGate.wait(for: connection)
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

    public func cancel() {
        connection.cancel()
    }

    deinit { connection.cancel() }
}

public final class ControlChannelReceiver: @unchecked Sendable {
    public let events: AsyncThrowingStream<ControlMessageEvent, Error>

    private let listener: NWListener
    private let queue = DispatchQueue(label: "HushPort.ControlReceiver")
    private let continuation: AsyncThrowingStream<ControlMessageEvent, Error>.Continuation

    public init(port: UInt16 = HushPortConstants.controlPort) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ControlChannelError.invalidPort(port)
        }
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        listener = try NWListener(using: parameters, on: endpointPort)
        (events, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingNewest(32))

        listener.stateUpdateHandler = { [continuation] state in
            switch state {
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
        listener.cancel()
        continuation.finish()
    }

    deinit {
        listener.cancel()
        continuation.finish()
    }

    private static func receive(
        on connection: NWConnection,
        continuation: AsyncThrowingStream<ControlMessageEvent, Error>.Continuation
    ) {
        connection.receiveMessage { data, _, _, error in
            if let data,
               !data.isEmpty,
               let message = try? ControlMessage(decoding: data),
               let replyEndpoint = connection.currentPath?.remoteEndpoint ?? Optional(connection.endpoint) {
                continuation.yield(ControlMessageEvent(message: message, replyEndpoint: replyEndpoint))
            }
            if error == nil {
                receive(on: connection, continuation: continuation)
            }
        }
    }
}
