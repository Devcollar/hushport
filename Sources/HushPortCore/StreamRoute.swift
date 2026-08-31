import Foundation
import Network

public struct StreamRoute: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case bonjour
        case manualHost
    }

    public let deviceID: UUID
    public let audioEndpoint: NWEndpoint
    public let controlEndpoint: NWEndpoint
    public let routeRevision: UInt64
    public let source: Source

    public init(
        deviceID: UUID,
        audioEndpoint: NWEndpoint,
        controlEndpoint: NWEndpoint,
        routeRevision: UInt64,
        source: Source
    ) {
        self.deviceID = deviceID
        self.audioEndpoint = audioEndpoint
        self.controlEndpoint = controlEndpoint
        self.routeRevision = routeRevision
        self.source = source
    }
}
