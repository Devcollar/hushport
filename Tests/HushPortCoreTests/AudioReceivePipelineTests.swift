import Foundation
import HushPortCore
import Testing

private func audioPacket(_ sequence: UInt32, marker: UInt8 = 0) -> AudioPacket {
    var payload = Data(count: AudioStreamFormat.prototype.payloadByteCount)
    payload[0] = marker
    return AudioPacket(
        streamID: HushPortConstants.defaultStreamID,
        sequenceNumber: sequence,
        captureTimeNanoseconds: UInt64(sequence),
        payload: payload
    )
}

private actor PlaybackTestHarness {
    private var buffer: AdaptivePlaybackBuffer

    init(prebufferPackets: Int = HushPortConstants.defaultPrebufferPackets) {
        buffer = AdaptivePlaybackBuffer(prebufferPackets: prebufferPackets)
    }

    func ingest(_ packet: AudioPacket) {
        _ = buffer.ingest(packet)
    }

    var isPrimed: Bool {
        buffer.isPrimed
    }

    func drainAll() -> Int {
        var count = 0
        while buffer.popReadyPayload() != nil {
            count += 1
        }
        return count
    }

    func firstPayloadByte() -> UInt8? {
        guard let payload = buffer.popReadyPayload() else { return nil }
        return payload.first
    }
}

@Test func audioPacketsReachPlaybackBufferInOrder() async throws {
    let port: UInt16 = 49_212
    let receiver = try UDPAudioReceiver(port: port)
    let harness = PlaybackTestHarness()

    let receiveTask = Task {
        var received = 0
        for try await packet in receiver.packets {
            await harness.ingest(packet)
            received += 1
            if received >= 8 { break }
        }
        return received
    }

    try await Task.sleep(for: .milliseconds(50))

    let sender = try UDPAudioSender(host: "127.0.0.1", port: port)
    try await sender.prepare()
    for sequence in UInt32(0)..<8 {
        try await sender.send(audioPacket(sequence, marker: UInt8(sequence)))
    }
    sender.cancel()

    let receivedCount = try await receiveTask.value
    receiver.cancel()

    #expect(receivedCount == 8)
    #expect(await harness.isPrimed)
    #expect(await harness.drainAll() == 8)
}

@Test func audioPayloadBytesArePreservedThroughBuffer() async {
    let harness = PlaybackTestHarness()
    for sequence in 0..<HushPortConstants.defaultPrebufferPackets {
        await harness.ingest(audioPacket(UInt32(sequence), marker: UInt8(sequence)))
    }
    #expect(await harness.isPrimed)
    #expect(await harness.firstPayloadByte() == 0)
}

@Test func sustainedAudioStreamFillsPlaybackBuffer() async throws {
    let port: UInt16 = 49_213
    let receiver = try UDPAudioReceiver(port: port)
    let harness = PlaybackTestHarness()
    let packetCount = 24

    let receiveTask = Task {
        var received = 0
        for try await packet in receiver.packets {
            await harness.ingest(packet)
            received += 1
            if received >= packetCount { break }
        }
        return received
    }

    try await Task.sleep(for: .milliseconds(50))

    let sender = try UDPAudioSender(host: "127.0.0.1", port: port)
    try await sender.prepare()
    for sequence in UInt32(0)..<UInt32(packetCount) {
        try await sender.send(audioPacket(sequence))
        try await Task.sleep(for: .milliseconds(1))
    }
    sender.cancel()

    let receivedCount = try await receiveTask.value
    receiver.cancel()

    #expect(receivedCount == packetCount)
    #expect(await harness.drainAll() == packetCount)
}
