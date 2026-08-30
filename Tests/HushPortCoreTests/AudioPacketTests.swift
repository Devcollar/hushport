import Foundation
import Testing
@testable import HushPortCore

@Test func packetRoundTrip() throws {
    let original = AudioPacket(
        streamID: 42,
        sequenceNumber: 7,
        captureTimeNanoseconds: 123_456_789,
        payload: Data([0, 1, 2, 3, 254, 255])
    )

    let decoded = try AudioPacket(decoding: original.encoded())
    #expect(decoded == original)
}

@Test func rejectsTruncatedPacket() {
    #expect(throws: AudioPacketError.truncatedHeader) {
        try AudioPacket(decoding: Data(repeating: 0, count: 8))
    }
}

@Test func rejectsIncorrectPayloadLength() throws {
    let packet = AudioPacket(
        streamID: 1,
        sequenceNumber: 1,
        captureTimeNanoseconds: 1,
        payload: Data([1, 2, 3])
    )
    var encoded = try packet.encoded()
    encoded.removeLast()

    #expect(throws: AudioPacketError.invalidPayloadLength) {
        try AudioPacket(decoding: encoded)
    }
}
