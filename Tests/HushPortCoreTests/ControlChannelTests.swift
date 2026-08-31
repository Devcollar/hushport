import Foundation
import HushPortCore
import Network
import Testing

@Test func controlReplyEndpointUsesControlPort() {
    let endpoint = NWEndpoint.hostPort(
        host: NWEndpoint.Host("192.168.1.20"),
        port: 54321
    )
    let resolved = ControlReplyEndpoint.resolve(endpoint)
    #expect(resolved == .hostPort(host: "192.168.1.20", port: 49201))
}

@Test func controlReplyEndpointRejectsServiceEndpoint() {
    let endpoint = NWEndpoint.service(
        name: "iPhone",
        type: "_hushport-control._udp",
        domain: "local.",
        interface: nil
    )
    #expect(ControlReplyEndpoint.resolve(endpoint) == nil)
}

enum ControlPongVerification {
    static func matchesPong(senderID: UUID, pairedDeviceID: UUID?) -> Bool {
        senderID == pairedDeviceID
    }
}

@Test func pongVerificationAcceptsMatchingUUID() {
    let id = UUID()
    #expect(ControlPongVerification.matchesPong(senderID: id, pairedDeviceID: id))
}

@Test func pongVerificationRejectsMismatchedUUID() {
    #expect(!ControlPongVerification.matchesPong(senderID: UUID(), pairedDeviceID: UUID()))
}

@Test func controlChannelSenderCancelIsIdempotent() throws {
    let sender = try ControlChannelSender(host: "127.0.0.1", port: 49_299)
    sender.cancel()
    sender.cancel()
}
