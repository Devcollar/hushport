import Foundation
import HushPortCore
import Network
import Testing

@Test func trustedDeviceEncodesNetworkAddress() throws {
    let device = TrustedDevice(
        id: UUID(),
        name: "iPhone",
        networkAddress: "192.168.68.120"
    )
    let data = try JSONEncoder().encode(device)
    let decoded = try JSONDecoder().decode(TrustedDevice.self, from: data)
    #expect(decoded.networkAddress == "192.168.68.120")
}

@Test func trustedDeviceStorePersistsNetworkAddress() {
    let defaults = UserDefaults.standard
    let key = "hushport.trusted.devices"
    let backup = defaults.data(forKey: key)
    defer {
        if let backup { defaults.set(backup, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    TrustedDeviceStore.clear()
    let device = TrustedDevice(
        id: UUID(),
        name: "iPhone",
        networkAddress: "192.168.68.120"
    )
    TrustedDeviceStore.save(device)
    let loaded = TrustedDeviceStore.primary()
    #expect(loaded?.id == device.id)
    #expect(loaded?.networkAddress == "192.168.68.120")
}

@Test func streamTargetResolverPrefersBonjourPeer() {
    let peer = HushPortPeer(
        name: "iPhone",
        endpoint: .hostPort(host: "192.168.68.120", port: 49200),
        deviceID: UUID()
    )
    let paired = TrustedDevice(id: UUID(), name: "iPhone", networkAddress: "192.168.68.121")

    let target = StreamTargetResolver.resolve(
        peer: peer,
        pairedDevice: paired,
        manualHost: "10.0.0.5"
    )

    #expect(target?.host == "192.168.68.120")
    #expect(target?.source == .bonjourPeer)
}

@Test func streamTargetResolverFallsBackToPairedAddress() {
    let paired = TrustedDevice(id: UUID(), name: "iPhone", networkAddress: "192.168.68.120")

    let target = StreamTargetResolver.resolve(
        peer: nil,
        pairedDevice: paired,
        manualHost: "",
        allowStalePairedAddress: true
    )

    #expect(target?.host == "192.168.68.120")
    #expect(target?.source == .pairedDeviceAddress)
}

@Test func streamTargetResolverUsesManualHostLast() {
    let target = StreamTargetResolver.resolve(
        peer: nil,
        pairedDevice: nil,
        manualHost: "192.168.68.55"
    )

    #expect(target?.host == "192.168.68.55")
    #expect(target?.source == .manualHost)
}

@Test func networkEndpointHostExtractsIPv4() {
    let endpoint = NWEndpoint.hostPort(host: "192.168.68.120", port: 49201)
    #expect(NetworkEndpointHost.ipv4String(from: endpoint) == "192.168.68.120")
}

@Test func networkAddressDetectsIPv4SubnetMismatch() {
    #expect(NetworkAddress.isSameIPv4Subnet("192.168.0.109", "192.168.0.175"))
    #expect(!NetworkAddress.isSameIPv4Subnet("192.168.0.109", "192.168.68.102"))
}

@Test func udpAudioPacketRoundTrip() async throws {
    let port: UInt16 = 49_211
    let receiver = try UDPAudioReceiver(port: port)
    try await receiver.prepare()
  let sendTask = Task {
        let sender = try UDPAudioSender(host: "127.0.0.1", port: port)
        try await sender.prepare()
        let payload = Data(repeating: 0, count: AudioStreamFormat.prototype.payloadByteCount)
        let packet = AudioPacket(
            streamID: HushPortConstants.defaultStreamID,
            sequenceNumber: 1,
            captureTimeNanoseconds: 0,
            payload: payload
        )
        try await sender.send(packet)
        sender.cancel()
    }
    let receiveTask = Task {
        for try await packet in receiver.packets {
            return packet.sequenceNumber
        }
        return UInt32.max
    }
    _ = try await sendTask.value
    let sequence = try await receiveTask.value
    receiver.cancel()
    #expect(sequence == 1)
}
