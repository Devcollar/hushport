import Foundation

public struct AudioStreamFormat: Codable, Equatable, Sendable {
    public static let prototype = AudioStreamFormat(
        sampleRate: 48_000,
        channelCount: 2,
        bitsPerChannel: 16,
        framesPerPacket: 240
    )

    public let sampleRate: UInt32
    public let channelCount: UInt8
    public let bitsPerChannel: UInt8
    public let framesPerPacket: UInt16

    public init(
        sampleRate: UInt32,
        channelCount: UInt8,
        bitsPerChannel: UInt8,
        framesPerPacket: UInt16
    ) {
        precondition(channelCount > 0)
        precondition(bitsPerChannel > 0 && bitsPerChannel.isMultiple(of: 8))
        precondition(framesPerPacket > 0)
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerChannel = bitsPerChannel
        self.framesPerPacket = framesPerPacket
    }

    public var bytesPerFrame: Int {
        Int(channelCount) * Int(bitsPerChannel / 8)
    }

    public var payloadByteCount: Int {
        Int(framesPerPacket) * bytesPerFrame
    }

    public var packetDuration: Duration {
        .nanoseconds(Int64(framesPerPacket) * 1_000_000_000 / Int64(sampleRate))
    }
}
