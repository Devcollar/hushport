import Foundation
import Network

public struct DiscoveredReceiver: Equatable, Sendable, Identifiable {
    public enum Readiness: Equatable, Sendable {
        case audioOnly
        case controlOnly
        case ready
    }

    public let deviceID: UUID
    public var displayName: String
    public var audioEndpoint: NWEndpoint?
    public var controlEndpoint: NWEndpoint?
    public var routeRevision: UInt64

    public var id: UUID { deviceID }

    public var readiness: Readiness {
        switch (audioEndpoint, controlEndpoint) {
        case (.some, .some): .ready
        case (.some, .none): .audioOnly
        case (.none, .some): .controlOnly
        case (.none, .none): .audioOnly
        }
    }

    public var isReady: Bool { readiness == .ready }

    public init(
        deviceID: UUID,
        displayName: String,
        audioEndpoint: NWEndpoint? = nil,
        controlEndpoint: NWEndpoint? = nil,
        routeRevision: UInt64 = 0
    ) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.audioEndpoint = audioEndpoint
        self.controlEndpoint = controlEndpoint
        self.routeRevision = routeRevision
    }
}

public enum ReceiverRegistryUpdate: Equatable, Sendable {
    case upsert(DiscoveredReceiver)
    case remove(UUID)
}

public final class ReceiverRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var receivers: [UUID: DiscoveredReceiver] = [:]

    public init() {}

    public func allReceivers() -> [DiscoveredReceiver] {
        lock.lock()
        defer { lock.unlock() }
        return receivers.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    public func receiver(for deviceID: UUID) -> DiscoveredReceiver? {
        lock.lock()
        defer { lock.unlock() }
        return receivers[deviceID]
    }

    @discardableResult
    public func updateAudio(
        deviceID: UUID,
        displayName: String,
        endpoint: NWEndpoint
    ) -> ReceiverRegistryUpdate? {
        lock.lock()
        defer { lock.unlock() }
        var receiver = receivers[deviceID] ?? DiscoveredReceiver(
            deviceID: deviceID,
            displayName: displayName
        )
        receiver.displayName = displayName
        guard receiver.audioEndpoint != endpoint else { return nil }
        receiver.audioEndpoint = endpoint
        receiver.routeRevision &+= 1
        receivers[deviceID] = receiver
        return .upsert(receiver)
    }

    @discardableResult
    public func updateControl(
        deviceID: UUID,
        displayName: String,
        endpoint: NWEndpoint
    ) -> ReceiverRegistryUpdate? {
        lock.lock()
        defer { lock.unlock() }
        var receiver = receivers[deviceID] ?? DiscoveredReceiver(
            deviceID: deviceID,
            displayName: displayName
        )
        receiver.displayName = displayName
        guard receiver.controlEndpoint != endpoint else { return nil }
        receiver.controlEndpoint = endpoint
        receiver.routeRevision &+= 1
        receivers[deviceID] = receiver
        return .upsert(receiver)
    }

    @discardableResult
    public func removeAudio(deviceID: UUID) -> ReceiverRegistryUpdate? {
        lock.lock()
        defer { lock.unlock() }
        guard var receiver = receivers[deviceID], receiver.audioEndpoint != nil else { return nil }
        receiver.audioEndpoint = nil
        receiver.routeRevision &+= 1
        if receiver.audioEndpoint == nil, receiver.controlEndpoint == nil {
            receivers.removeValue(forKey: deviceID)
            return .remove(deviceID)
        }
        receivers[deviceID] = receiver
        return .upsert(receiver)
    }

    @discardableResult
    public func removeControl(deviceID: UUID) -> ReceiverRegistryUpdate? {
        lock.lock()
        defer { lock.unlock() }
        guard var receiver = receivers[deviceID], receiver.controlEndpoint != nil else { return nil }
        receiver.controlEndpoint = nil
        receiver.routeRevision &+= 1
        if receiver.audioEndpoint == nil, receiver.controlEndpoint == nil {
            receivers.removeValue(forKey: deviceID)
            return .remove(deviceID)
        }
        receivers[deviceID] = receiver
        return .upsert(receiver)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        receivers.removeAll()
    }
}
