import Foundation

/// Fixed prebuffer + ordered jitter buffer with packet-loss concealment for speech.
public struct AdaptivePlaybackBuffer: Sendable {
    public private(set) var queuedPackets = 0
    public private(set) var isPrimed = false
    public private(set) var gapSkips = 0
    public private(set) var latencyTrims = 0
    public private(set) var lastPopWasConcealment = false

    private let prebufferPackets: Int
    private var jitterBuffer = JitterBuffer(capacity: 64)
    private var ingestedPackets = 0
    private var stalledSince: UInt64?
    private var sustainedHighQueueSince: UInt64?
    private var lastTrimAt: UInt64?
    private var lastPayload: Data?
    private var concealmentUsesForCurrentGap = 0

    public init(prebufferPackets: Int = HushPortConstants.defaultPrebufferPackets) {
        self.prebufferPackets = min(
            max(prebufferPackets, HushPortConstants.minimumPrebufferPackets),
            HushPortConstants.maximumPrebufferPackets
        )
    }

    public mutating func ingest(
        _ packet: AudioPacket,
        now: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> JitterBuffer.InsertResult {
        let result = jitterBuffer.insert(packet)
        ingestedPackets += 1
        if !isPrimed, ingestedPackets >= prebufferPackets {
            isPrimed = true
        }
        trimExcessLatencyIfNeeded(now: now)
        queuedPackets = jitterBuffer.count
        return result
    }

    private mutating func trimExcessLatencyIfNeeded(now: UInt64) {
        let maxPackets = HushPortConstants.maximumPlaybackLatencyPackets
        guard jitterBuffer.count > maxPackets else {
            sustainedHighQueueSince = nil
            return
        }
        if sustainedHighQueueSince == nil {
            sustainedHighQueueSince = now
            return
        }
        guard now &- sustainedHighQueueSince! >= HushPortConstants.sustainedBacklogTrimNanoseconds else {
            return
        }
        let trimmed = jitterBuffer.trimToMaximumPacketCount(maxPackets - 1)
        if trimmed > 0 {
            latencyTrims += trimmed
            sustainedHighQueueSince = now
            lastTrimAt = now
        }
        queuedPackets = jitterBuffer.count
    }

    public mutating func peekReadyPayload(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Data? {
        guard isPrimed else { return nil }
        if let packet = jitterBuffer.peekNext() {
            return packet.payload
        }
        guard jitterBuffer.isStalled else { return nil }
        return nil
    }

    public mutating func popReadyPayload(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Data? {
        lastPopWasConcealment = false
        guard isPrimed else {
            queuedPackets = jitterBuffer.count
            return nil
        }

        if let packet = jitterBuffer.popNext() {
            stalledSince = nil
            concealmentUsesForCurrentGap = 0
            lastPayload = packet.payload
            queuedPackets = jitterBuffer.count
            return packet.payload
        }

        guard jitterBuffer.isStalled else {
            stalledSince = nil
            queuedPackets = jitterBuffer.count
            return nil
        }

        if stalledSince == nil {
            stalledSince = now
            queuedPackets = jitterBuffer.count
            return nil
        }

        if now &- stalledSince! < gapTimeoutNanoseconds {
            queuedPackets = jitterBuffer.count
            return nil
        }

        if let lastPayload,
           concealmentUsesForCurrentGap < HushPortConstants.maxConcealmentPacketsPerGap {
            concealmentUsesForCurrentGap += 1
            gapSkips += 1
            lastPopWasConcealment = true
            stalledSince = now
            queuedPackets = jitterBuffer.count
            return lastPayload
        }

        concealmentUsesForCurrentGap = 0
        if let gap = jitterBuffer.gapUntilNextAvailable(), gap > 4 {
            _ = jitterBuffer.skipToNextAvailable()
        } else {
            jitterBuffer.skipMissingPacket()
        }
        gapSkips += 1
        stalledSince = nil
        queuedPackets = jitterBuffer.count
        return popReadyPayload(now: now)
    }

    public mutating func reset() {
        jitterBuffer.reset()
        queuedPackets = 0
        isPrimed = false
        gapSkips = 0
        latencyTrims = 0
        ingestedPackets = 0
        stalledSince = nil
        sustainedHighQueueSince = nil
        lastTrimAt = nil
        lastPayload = nil
        concealmentUsesForCurrentGap = 0
        lastPopWasConcealment = false
    }

    private var gapTimeoutNanoseconds: UInt64 {
        let packetDurationNs = UInt64(AudioStreamFormat.prototype.framesPerPacket) * 1_000_000_000
            / UInt64(AudioStreamFormat.prototype.sampleRate)
        return packetDurationNs * 6
    }
}
