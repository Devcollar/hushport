import Foundation
import HushPortCore
import Network
import Testing

@Test func receiverRegistryMergesAudioAndControlIntoOneDevice() {
    let registry = ReceiverRegistry()
    let deviceID = UUID()
    let audio = NWEndpoint.service(name: "iPhone", type: "_hushport._udp", domain: "local.", interface: nil)
    let control = NWEndpoint.service(
        name: "iPhone",
        type: "_hushport-control._udp",
        domain: "local.",
        interface: nil
    )

    _ = registry.updateAudio(deviceID: deviceID, displayName: "iPhone", endpoint: audio)
    _ = registry.updateControl(deviceID: deviceID, displayName: "iPhone", endpoint: control)

    let receivers = registry.allReceivers()
    #expect(receivers.count == 1)
    #expect(receivers.first?.deviceID == deviceID)
    #expect(receivers.first?.isReady == true)
    #expect(receivers.first?.routeRevision == 2)
}

@Test func receiverRegistryIgnoresEquivalentEndpointRefresh() {
    let registry = ReceiverRegistry()
    let deviceID = UUID()
    let audio = NWEndpoint.service(name: "iPhone", type: "_hushport._udp", domain: "local.", interface: nil)

    _ = registry.updateAudio(deviceID: deviceID, displayName: "iPhone", endpoint: audio)
    let second = registry.updateAudio(deviceID: deviceID, displayName: "iPhone", endpoint: audio)

    #expect(second == nil)
    #expect(registry.receiver(for: deviceID)?.routeRevision == 1)
}

@Test func receiverRegistrySelectsOnlyRequestedUUID() {
    let registry = ReceiverRegistry()
    let pairedID = UUID()
    let otherID = UUID()
    let audioA = NWEndpoint.service(name: "iPhone", type: "_hushport._udp", domain: "local.", interface: nil)
    let controlA = NWEndpoint.service(
        name: "iPhone",
        type: "_hushport-control._udp",
        domain: "local.",
        interface: nil
    )
    let audioB = NWEndpoint.service(name: "Other", type: "_hushport._udp", domain: "local.", interface: nil)

    _ = registry.updateAudio(deviceID: pairedID, displayName: "iPhone", endpoint: audioA)
    _ = registry.updateControl(deviceID: pairedID, displayName: "iPhone", endpoint: controlA)
    _ = registry.updateAudio(deviceID: otherID, displayName: "Other", endpoint: audioB)

    let paired = registry.receiver(for: pairedID)
    let other = registry.receiver(for: otherID)

    #expect(paired?.isReady == true)
    #expect(other?.isReady == false)
    #expect(other?.readiness == .audioOnly)
}

@Test func automaticRouteAvailableWithNilNetworkAddress() {
    let registry = ReceiverRegistry()
    let deviceID = UUID()
    let audio = NWEndpoint.service(name: "iPhone", type: "_hushport._udp", domain: "local.", interface: nil)
    let control = NWEndpoint.service(
        name: "iPhone",
        type: "_hushport-control._udp",
        domain: "local.",
        interface: nil
    )
    _ = registry.updateAudio(deviceID: deviceID, displayName: "iPhone", endpoint: audio)
    _ = registry.updateControl(deviceID: deviceID, displayName: "iPhone", endpoint: control)

    let paired = TrustedDevice(id: deviceID, name: "iPhone", networkAddress: nil)
    let receiver = registry.receiver(for: paired.id)

    #expect(paired.networkAddress == nil)
    #expect(receiver?.isReady == true)
}

@Test func receiverRegistryIncrementsRevisionWhenEndpointChanges() {
    let registry = ReceiverRegistry()
    let deviceID = UUID()
    let audioA = NWEndpoint.service(name: "iPhone", type: "_hushport._udp", domain: "local.", interface: nil)
    let audioB = NWEndpoint.service(name: "iPhone-2", type: "_hushport._udp", domain: "local.", interface: nil)

    _ = registry.updateAudio(deviceID: deviceID, displayName: "iPhone", endpoint: audioA)
    let revisionAfterFirst = registry.receiver(for: deviceID)?.routeRevision
    _ = registry.updateAudio(deviceID: deviceID, displayName: "iPhone", endpoint: audioB)
    let revisionAfterSecond = registry.receiver(for: deviceID)?.routeRevision

    #expect(revisionAfterFirst == 1)
    #expect(revisionAfterSecond == 2)
}
