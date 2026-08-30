import Foundation

public struct AudioPacket: Equatable, Sendable {
    public static let magic: UInt32 = 0x5048_5344 // PHSD
    public static let protocolVersion: UInt8 = 1
    public static let headerByteCount = 28

    public let streamID: UInt64
    public let sequenceNumber: UInt32
    public let captureTimeNanoseconds: UInt64
    public let payload: Data

    public init(
        streamID: UInt64,
        sequenceNumber: UInt32,
        captureTimeNanoseconds: UInt64,
        payload: Data
    ) {
        self.streamID = streamID
        self.sequenceNumber = sequenceNumber
        self.captureTimeNanoseconds = captureTimeNanoseconds
        self.payload = payload
    }

    public func encoded() throws -> Data {
        guard payload.count <= Int(UInt16.max) else {
            throw AudioPacketError.payloadTooLarge(payload.count)
        }

        var data = Data(capacity: Self.headerByteCount + payload.count)
        data.appendBigEndian(Self.magic)
        data.append(Self.protocolVersion)
        data.append(0) // flags
        data.appendBigEndian(UInt16(Self.headerByteCount))
        data.appendBigEndian(streamID)
        data.appendBigEndian(sequenceNumber)
        data.appendBigEndian(captureTimeNanoseconds)
        data.appendBigEndian(UInt16(payload.count))
        data.appendBigEndian(UInt16(0)) // reserved
        data.append(payload)
        return data
    }

    public init(decoding data: Data) throws {
        guard data.count >= Self.headerByteCount else {
            throw AudioPacketError.truncatedHeader
        }

        var reader = DataReader(data: data)
        guard try reader.readUInt32() == Self.magic else {
            throw AudioPacketError.invalidMagic
        }
        guard try reader.readUInt8() == Self.protocolVersion else {
            throw AudioPacketError.unsupportedVersion
        }
        _ = try reader.readUInt8()
        guard try reader.readUInt16() == UInt16(Self.headerByteCount) else {
            throw AudioPacketError.invalidHeaderLength
        }

        streamID = try reader.readUInt64()
        sequenceNumber = try reader.readUInt32()
        captureTimeNanoseconds = try reader.readUInt64()
        let payloadLength = Int(try reader.readUInt16())
        _ = try reader.readUInt16()

        guard reader.remainingByteCount == payloadLength else {
            throw AudioPacketError.invalidPayloadLength
        }
        payload = try reader.readData(count: payloadLength)
    }
}

public enum AudioPacketError: Error, Equatable {
    case truncatedHeader
    case invalidMagic
    case unsupportedVersion
    case invalidHeaderLength
    case invalidPayloadLength
    case payloadTooLarge(Int)
}

private struct DataReader {
    let data: Data
    var offset = 0

    var remainingByteCount: Int { data.count - offset }

    mutating func readUInt8() throws -> UInt8 {
        guard remainingByteCount >= 1 else { throw AudioPacketError.truncatedHeader }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try readData(count: 2)
        return bytes.reduce(0) { ($0 << 8) | UInt16($1) }
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readData(count: 4)
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readData(count: 8)
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, remainingByteCount >= count else {
            throw AudioPacketError.truncatedHeader
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
}
