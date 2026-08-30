import Foundation
import Testing
@testable import HushPortCore

private func audioPacket(_ sequence: UInt32) -> AudioPacket {
    AudioPacket(
        streamID: HushPortConstants.defaultStreamID,
        sequenceNumber: sequence,
        captureTimeNanoseconds: UInt64(sequence),
        payload: Data(count: AudioStreamFormat.prototype.payloadByteCount)
    )
}

@Test func adaptiveBufferWaitsForPrebufferWithoutDiscarding() {
    let target = HushPortConstants.minimumPrebufferPackets
    var buffer = AdaptivePlaybackBuffer(prebufferPackets: target)
    #expect(buffer.popReadyPayload() == nil)

    for sequence in 0..<(target - 1) {
        _ = buffer.ingest(audioPacket(UInt32(sequence)))
        #expect(buffer.popReadyPayload() == nil)
    }
    #expect(buffer.queuedPackets == target - 1)

    _ = buffer.ingest(audioPacket(UInt32(target - 1)))
    #expect(buffer.isPrimed)
    #expect(buffer.popReadyPayload()?.count == AudioStreamFormat.prototype.payloadByteCount)
    #expect(buffer.popReadyPayload()?.count == AudioStreamFormat.prototype.payloadByteCount)
}

@Test func adaptiveBufferRecoversFromPacketLoss() {
    var buffer = AdaptivePlaybackBuffer(prebufferPackets: HushPortConstants.minimumPrebufferPackets)
    for sequence in 0..<HushPortConstants.minimumPrebufferPackets {
        _ = buffer.ingest(audioPacket(UInt32(sequence)))
    }
    _ = buffer.ingest(audioPacket(20))

    for _ in 0..<HushPortConstants.minimumPrebufferPackets {
        #expect(buffer.popReadyPayload()?.count == AudioStreamFormat.prototype.payloadByteCount)
    }

    let stalledAt = DispatchTime.now().uptimeNanoseconds
    #expect(buffer.popReadyPayload(now: stalledAt) == nil)

    let later = stalledAt + 45_000_000
    let payload = buffer.popReadyPayload(now: later)
    #expect(payload?.count == AudioStreamFormat.prototype.payloadByteCount)
    #expect(buffer.gapSkips >= 1)
}

@Test func adaptiveBufferQueuedPacketsReflectsLiveDepth() {
    var buffer = AdaptivePlaybackBuffer(prebufferPackets: HushPortConstants.minimumPrebufferPackets)
    for sequence in 0..<(HushPortConstants.minimumPrebufferPackets + 2) {
        _ = buffer.ingest(audioPacket(UInt32(sequence)))
    }
    #expect(buffer.queuedPackets == HushPortConstants.minimumPrebufferPackets + 2)

    _ = buffer.popReadyPayload()
    #expect(buffer.queuedPackets == HushPortConstants.minimumPrebufferPackets + 1)
}

@Test func adaptiveBufferTrimsSustainedHighLatency() {
    var buffer = AdaptivePlaybackBuffer(prebufferPackets: HushPortConstants.minimumPrebufferPackets)
    let start = DispatchTime.now().uptimeNanoseconds
    for sequence in 0..<40 {
        _ = buffer.ingest(audioPacket(UInt32(sequence)), now: start)
    }
    #expect(buffer.queuedPackets == 40)

    let later = start + HushPortConstants.sustainedBacklogTrimNanoseconds + 1
    _ = buffer.ingest(audioPacket(40), now: later)
    #expect(buffer.queuedPackets < 40)
    #expect(buffer.latencyTrims > 0)
}

@Test func adaptiveBufferKeepsHealthyBacklog() {
    var buffer = AdaptivePlaybackBuffer(prebufferPackets: HushPortConstants.minimumPrebufferPackets)
    for sequence in 0..<10 {
        _ = buffer.ingest(audioPacket(UInt32(sequence)))
    }
    #expect(buffer.queuedPackets == 10)
    #expect(buffer.latencyTrims == 0)
}
