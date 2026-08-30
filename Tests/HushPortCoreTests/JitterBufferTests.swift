import Foundation
import Testing
@testable import HushPortCore

private func packet(_ sequence: UInt32) -> AudioPacket {
    AudioPacket(
        streamID: 1,
        sequenceNumber: sequence,
        captureTimeNanoseconds: UInt64(sequence),
        payload: Data([UInt8(truncatingIfNeeded: sequence)])
    )
}

@Test func reordersPackets() {
    var buffer = JitterBuffer()
    #expect(buffer.insert(packet(10)) == .accepted)
    #expect(buffer.insert(packet(12)) == .accepted)
    #expect(buffer.insert(packet(11)) == .accepted)

    #expect(buffer.popNext()?.sequenceNumber == 10)
    #expect(buffer.popNext()?.sequenceNumber == 11)
    #expect(buffer.popNext()?.sequenceNumber == 12)
}

@Test func rejectsDuplicatesAndLatePackets() {
    var buffer = JitterBuffer()
    #expect(buffer.insert(packet(5)) == .accepted)
    #expect(buffer.insert(packet(5)) == .duplicate)
    #expect(buffer.popNext()?.sequenceNumber == 5)
    #expect(buffer.insert(packet(5)) == .tooLate)
}

@Test func canSkipPacketLoss() {
    var buffer = JitterBuffer()
    _ = buffer.insert(packet(20))
    _ = buffer.insert(packet(22))

    #expect(buffer.popNext()?.sequenceNumber == 20)
    #expect(buffer.popNext() == nil)
    buffer.skipMissingPacket()
    #expect(buffer.popNext()?.sequenceNumber == 22)
}
