import Foundation
import HushPortCore
import Network
import Testing

@Test func pairingCodeHasSixDigits() {
    let code = PairingCodeGenerator.makeCode()
    #expect(code.count == 6)
    #expect(PairingCodeGenerator.isValid(code))
}

@Test func pairingCodeRejectsInvalidValues() {
    #expect(!PairingCodeGenerator.isValid("12345"))
    #expect(!PairingCodeGenerator.isValid("abcdef"))
}

@Test func controlMessageRoundTripIncludesNetworkAddress() throws {
    let message = ControlMessage(
        type: .pong,
        senderID: UUID(),
        senderName: "iPhone",
        networkAddress: "192.168.68.120"
    )
    let decoded = try ControlMessage(decoding: try message.encoded())
    #expect(decoded.networkAddress == "192.168.68.120")
}

@Test func streamTargetResolverCollectsCandidateHosts() {
    let paired = TrustedDevice(id: UUID(), name: "iPhone", networkAddress: "192.168.68.120")
    let hosts = StreamTargetResolver.candidateHosts(
        resolvedPeerHosts: ["192.168.68.121", "192.168.68.120"],
        pairedDevice: paired,
        manualHost: "10.0.0.5"
    )
    #expect(hosts == ["192.168.68.121", "192.168.68.120", "10.0.0.5"])
}

@Test func controlMessageRoundTrip() throws {
    let message = ControlMessage(
        type: .pairRequest,
        senderID: UUID(),
        senderName: "MacBook Pro",
        pairingCode: "123456"
    )
    let data = try message.encoded()
    let decoded = try ControlMessage(decoding: data)
    #expect(decoded == message)
}

@Test func trustedDeviceStorePersistsPrimaryDevice() {
    let defaults = UserDefaults.standard
    let key = "hushport.trusted.devices"
    let backup = defaults.data(forKey: key)
    defer {
        if let backup { defaults.set(backup, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    TrustedDeviceStore.clear()
    let device = TrustedDevice(id: UUID(), name: "iPhone")
    TrustedDeviceStore.save(device)
    #expect(TrustedDeviceStore.primary()?.id == device.id)
}

@Test func pairingPayloadRoundTrip() {
    let offer = MacPairingOffer(
        deviceID: UUID(),
        deviceName: "MacBook Pro",
        pairingCode: "123456",
        hostAddress: "192.168.1.10"
    )
    let url = PairingPayload.makeURL(offer: offer)
    let parsed = PairingPayload.parse(url)
    #expect(parsed == offer)
}
