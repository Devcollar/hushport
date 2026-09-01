import Foundation

public enum AudioActivityState: Equatable, Sendable {
    case active
    case idle
}

public enum AudioActivityEvent: Equatable, Sendable {
    case becameIdle(silenceDurationNanoseconds: UInt64)
    case becameActive(idleDurationNanoseconds: UInt64)
}

/// Cheap peak-amplitude silence detection for PCM Int16 stereo payloads.
public enum AudioSilenceAnalyzer {
    public static func peakAmplitude(in payload: Data) -> Int16 {
        guard payload.count >= 2 else { return 0 }
        var peak: Int16 = 0
        payload.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<samples.count {
                let magnitude = abs(samples[index])
                if magnitude > peak {
                    peak = magnitude
                }
            }
        }
        return peak
    }

    public static func isSilent(
        _ payload: Data,
        peakThreshold: Int16 = HushPortConstants.audioSilencePeakThreshold
    ) -> Bool {
        peakAmplitude(in: payload) < peakThreshold
    }

    public static func isMeaningfulAudio(
        _ payload: Data,
        peakThreshold: Int16 = HushPortConstants.audioResumePeakThreshold
    ) -> Bool {
        peakAmplitude(in: payload) >= peakThreshold
    }
}

public protocol PowerModeClock: Sendable {
    func nowNanoseconds() -> UInt64
}

public struct SystemPowerModeClock: PowerModeClock, Sendable {
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

/// Tracks prolonged silence while streaming intent remains enabled.
public final class AudioActivityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let idleThresholdNanoseconds: UInt64
    private let clock: PowerModeClock
    private var state: AudioActivityState = .active
    private var lastMeaningfulAudioAtNanoseconds: UInt64
    private var idleEnteredAtNanoseconds: UInt64?

    public init(
        idleThreshold: Duration = HushPortConstants.audioIdleThreshold,
        clock: PowerModeClock = SystemPowerModeClock()
    ) {
        self.clock = clock
        idleThresholdNanoseconds = Self.nanoseconds(idleThreshold)
        lastMeaningfulAudioAtNanoseconds = clock.nowNanoseconds()
    }

    public var activityState: AudioActivityState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = .active
        idleEnteredAtNanoseconds = nil
        lastMeaningfulAudioAtNanoseconds = clock.nowNanoseconds()
    }

    @discardableResult
    public func observePayload(_ payload: Data) -> AudioActivityEvent? {
        lock.lock()
        defer { lock.unlock() }
        let now = clock.nowNanoseconds()

        if state == .idle {
            guard AudioSilenceAnalyzer.isMeaningfulAudio(payload) else { return nil }
            let idleDuration = now &- (idleEnteredAtNanoseconds ?? now)
            state = .active
            idleEnteredAtNanoseconds = nil
            lastMeaningfulAudioAtNanoseconds = now
            return .becameActive(idleDurationNanoseconds: idleDuration)
        }

        if !AudioSilenceAnalyzer.isSilent(payload) {
            lastMeaningfulAudioAtNanoseconds = now
            return nil
        }

        let silenceDuration = now &- lastMeaningfulAudioAtNanoseconds
        guard silenceDuration >= idleThresholdNanoseconds else { return nil }
        state = .idle
        idleEnteredAtNanoseconds = now
        return .becameIdle(silenceDurationNanoseconds: silenceDuration)
    }

    public func shouldSuppressTransmission(for payload: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if state == .active { return false }
        return !AudioSilenceAnalyzer.isMeaningfulAudio(payload)
    }

    private static func nanoseconds(_ duration: Duration) -> UInt64 {
        let components = duration.components
        return UInt64(components.seconds) * 1_000_000_000 + UInt64(components.attoseconds / 1_000_000_000)
    }
}
