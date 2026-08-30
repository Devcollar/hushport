import Foundation
import HushPortCore
import Network
import Testing

@Test func controlMessageUnpairRoundTrip() throws {
    let message = ControlMessage(
        type: .unpair,
        senderID: UUID(),
        senderName: "iPhone"
    )
    let decoded = try ControlMessage(decoding: try message.encoded())
    #expect(decoded == message)
}

@Test func unpairMessageReachesControlListener() async throws {
    let port: UInt16 = 49_214
    let listener = try ControlChannelReceiver(port: port)
    let senderID = UUID()

    let receiveTask = Task {
        for try await event in listener.events {
            if event.message.type == .unpair {
                return event.message.senderID
            }
        }
        return UUID()
    }

    try await Task.sleep(for: .milliseconds(50))

    let sender = try ControlChannelSender(
        host: "127.0.0.1",
        port: port
    )
    try await sender.prepare()
    try await sender.send(
        ControlMessage(
            type: .unpair,
            senderID: senderID,
            senderName: "iPhone"
        )
    )
    sender.cancel()

    let receivedID = try await receiveTask.value
    listener.cancel()
    #expect(receivedID == senderID)
}

@Test func trustedDeviceStoreClearsOnUnpair() {
    let defaults = UserDefaults.standard
    let key = "hushport.trusted.devices"
    let backup = defaults.data(forKey: key)
    defer {
        if let backup { defaults.set(backup, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    let device = TrustedDevice(id: UUID(), name: "iPhone", networkAddress: "192.168.1.10")
    TrustedDeviceStore.save(device)
    #expect(TrustedDeviceStore.primary() != nil)

    TrustedDeviceStore.clear()
    #expect(TrustedDeviceStore.primary() == nil)
}
