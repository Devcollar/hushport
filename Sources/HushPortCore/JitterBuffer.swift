import Foundation

public struct JitterBuffer: Sendable {
    public enum InsertResult: Equatable, Sendable {
        case accepted
        case duplicate
        case tooLate
    }

    private var packets: [UInt32: AudioPacket] = [:]
    private var nextSequenceNumber: UInt32?
    private let capacity: Int

    public init(capacity: Int = 32) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var count: Int { packets.count }

    public var isStalled: Bool {
        guard let nextSequenceNumber else { return false }
        return packets[nextSequenceNumber] == nil && !packets.isEmpty
    }

    @discardableResult
    public mutating func insert(_ packet: AudioPacket) -> InsertResult {
        if let nextSequenceNumber, packet.sequenceNumber < nextSequenceNumber {
            return .tooLate
        }
        guard packets[packet.sequenceNumber] == nil else {
            return .duplicate
        }

        if nextSequenceNumber == nil {
            nextSequenceNumber = packet.sequenceNumber
        }
        packets[packet.sequenceNumber] = packet

        while packets.count > capacity {
            if let nextSequenceNumber, packets[nextSequenceNumber] == nil {
                skipMissingPacket()
            } else if let highestSequenceNumber = packets.keys.max() {
                packets.removeValue(forKey: highestSequenceNumber)
            } else {
                break
            }
        }
        return .accepted
    }

    public mutating func peekNext() -> AudioPacket? {
        guard let sequenceNumber = nextSequenceNumber else { return nil }
        return packets[sequenceNumber]
    }

    public mutating func popNext() -> AudioPacket? {
        guard let sequenceNumber = nextSequenceNumber,
              let packet = packets.removeValue(forKey: sequenceNumber) else {
            return nil
        }
        nextSequenceNumber = sequenceNumber &+ 1
        return packet
    }

    public mutating func skipMissingPacket() {
        guard let nextSequenceNumber else { return }
        self.nextSequenceNumber = nextSequenceNumber &+ 1
    }

    public func gapUntilNextAvailable() -> UInt32? {
        guard let nextSequenceNumber, packets[nextSequenceNumber] == nil else { return nil }
        guard let lowestAvailable = packets.keys.min() else { return nil }
        return lowestAvailable &- nextSequenceNumber
    }

    public mutating func skipToNextAvailable() -> Bool {
        guard let nextSequenceNumber, packets[nextSequenceNumber] == nil else { return false }
        guard let lowestAvailable = packets.keys.min() else { return false }
        self.nextSequenceNumber = lowestAvailable
        return true
    }

    @discardableResult
    public mutating func discardNextInSequence() -> Bool {
        guard let sequenceNumber = nextSequenceNumber else { return false }
        if packets.removeValue(forKey: sequenceNumber) != nil {
            nextSequenceNumber = sequenceNumber &+ 1
            return true
        }
        if isStalled {
            skipMissingPacket()
            return discardNextInSequence()
        }
        return false
    }

    public mutating func trimToMaximumPacketCount(_ maxPackets: Int) -> Int {
        var discarded = 0
        while count > maxPackets, discardNextInSequence() {
            discarded += 1
        }
        return discarded
    }

    public mutating func reset() {
        packets.removeAll(keepingCapacity: true)
        nextSequenceNumber = nil
    }
}
