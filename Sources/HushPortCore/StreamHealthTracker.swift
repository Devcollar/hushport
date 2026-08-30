import Foundation

public enum StreamConnectionQuality: String, Sendable, Equatable {
    case excellent
    case good
    case fair
    case poor
    case unknown

    public var displayName: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Weak"
        case .unknown: "Checking"
        }
    }

    public var guidance: String? {
        switch self {
        case .poor:
            "Wi-Fi may be unstable. Move closer to your router and keep Mac and iPhone on the same network."
        case .fair:
            "Connection is usable, but you may hear brief glitches if Wi-Fi gets busier."
        default:
            nil
        }
    }
}

/// Tracks packet timing and loss recovery to estimate stream quality.
public struct StreamHealthTracker: Sendable {
    public private(set) var quality: StreamConnectionQuality = .unknown
    public private(set) var jitterMilliseconds: Double = 0
    public private(set) var gapSkipsTotal = 0
    public private(set) var latencyTrimsTotal = 0

    private var recentGaps: [UInt64] = []
    private var lastArrivalUptime: UInt64?
    private var recentGapSkipTimes: [UInt64] = []
    private var recentLatencyTrimTimes: [UInt64] = []

    private var packetDurationNanoseconds: UInt64 {
        UInt64(AudioStreamFormat.prototype.framesPerPacket) * 1_000_000_000
            / UInt64(AudioStreamFormat.prototype.sampleRate)
    }

    public init() {}

    public mutating func recordPacketArrival(now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        if let lastArrivalUptime {
            let gap = now &- lastArrivalUptime
            recentGaps.append(gap)
            if recentGaps.count > 32 {
                recentGaps.removeFirst(recentGaps.count - 32)
            }
        }
        lastArrivalUptime = now
        recomputeQuality(now: now)
    }

    public mutating func recordGapSkip(now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        gapSkipsTotal += 1
        recentGapSkipTimes.append(now)
        recentGapSkipTimes.removeAll { now &- $0 > 10_000_000_000 }
        recomputeQuality(now: now)
    }

    public mutating func recordLatencyTrim(now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        latencyTrimsTotal += 1
        recentLatencyTrimTimes.append(now)
        recentLatencyTrimTimes.removeAll { now &- $0 > 10_000_000_000 }
        recomputeQuality(now: now)
    }

    public mutating func reset() {
        quality = .unknown
        jitterMilliseconds = 0
        gapSkipsTotal = 0
        latencyTrimsTotal = 0
        recentGaps.removeAll(keepingCapacity: true)
        lastArrivalUptime = nil
        recentGapSkipTimes.removeAll(keepingCapacity: true)
        recentLatencyTrimTimes.removeAll(keepingCapacity: true)
    }

    /// Keep schedule-ahead stable. Extra buffering worsens drift on long sessions.
    public var recommendedScheduleAhead: Int {
        switch quality {
        case .poor, .fair:
            8
        case .good:
            9
        case .excellent, .unknown:
            8
        }
    }

    private mutating func recomputeQuality(now: UInt64) {
        let recentGapSkips = recentGapSkipTimes.count
        let recentLatencyTrims = recentLatencyTrimTimes.count
        guard recentGaps.count >= 8 else {
            if recentGapSkips >= 3 || recentLatencyTrims >= 2 {
                quality = .poor
            }
            return
        }

        let sorted = recentGaps.sorted()
        let median = sorted[sorted.count / 2]
        jitterMilliseconds = Double(median) / 1_000_000
        let medianAsPacketMultiplier = Double(median) / Double(packetDurationNanoseconds)

        if recentGapSkips >= 4 || medianAsPacketMultiplier > 4 || recentLatencyTrims >= 3 {
            quality = .poor
        } else if recentGapSkips >= 2 || medianAsPacketMultiplier > 2.5 || recentLatencyTrims >= 1 {
            quality = .fair
        } else if medianAsPacketMultiplier > 1.6 {
            quality = .good
        } else {
            quality = .excellent
        }
    }
}
