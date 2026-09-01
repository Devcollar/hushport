import Foundation
import HushPortCore
import Testing

final class TestPowerModeClock: PowerModeClock, @unchecked Sendable {
    var currentNanoseconds: UInt64

    init(startNanoseconds: UInt64 = 0) {
        currentNanoseconds = startNanoseconds
    }

    func advance(by duration: Duration) {
        let components = duration.components
        currentNanoseconds &+= UInt64(components.seconds) * 1_000_000_000
        currentNanoseconds &+= UInt64(components.attoseconds / 1_000_000_000)
    }

    func nowNanoseconds() -> UInt64 {
        currentNanoseconds
    }
}

private func silentPayload() -> Data {
    Data(count: AudioStreamFormat.prototype.payloadByteCount)
}

private func tonePayload() -> Data {
    let format = AudioStreamFormat.prototype
    var samples = [Int16]()
    samples.reserveCapacity(Int(format.framesPerPacket) * Int(format.channelCount))
    for index in 0..<Int(format.framesPerPacket) {
        let sample = Int16(sin(Double(index) * 0.2) * 8_000)
        samples.append(sample)
        samples.append(sample)
    }
    return samples.withUnsafeBytes { Data($0) }
}

@Test func meaningfulAudioDetectedByPeakAmplitude() {
    #expect(AudioSilenceAnalyzer.isSilent(silentPayload()))
    #expect(AudioSilenceAnalyzer.isMeaningfulAudio(tonePayload()))
}

@Test func fiveSecondsSilenceRemainsActive() {
    let clock = TestPowerModeClock()
    let tracker = AudioActivityTracker(clock: clock)
    #expect(tracker.observePayload(tonePayload()) == nil)
    clock.advance(by: .seconds(5))
    #expect(tracker.observePayload(silentPayload()) == nil)
    #expect(tracker.activityState == .active)
    #expect(tracker.shouldSuppressTransmission(for: silentPayload()) == false)
}

@Test func twentyNineSecondsSilenceRemainsActive() {
    let clock = TestPowerModeClock()
    let tracker = AudioActivityTracker(clock: clock)
    _ = tracker.observePayload(tonePayload())
    clock.advance(by: .seconds(29))
    #expect(tracker.observePayload(silentPayload()) == nil)
    #expect(tracker.activityState == .active)
}

@Test func thirtySecondsSilenceBecomesIdleAndSuppressesPackets() {
    let clock = TestPowerModeClock()
    let tracker = AudioActivityTracker(clock: clock)
    _ = tracker.observePayload(tonePayload())
    clock.advance(by: .seconds(30))
    let event = tracker.observePayload(silentPayload())
    #expect(event == .becameIdle(silenceDurationNanoseconds: 30_000_000_000))
    #expect(tracker.activityState == .idle)
    #expect(tracker.shouldSuppressTransmission(for: silentPayload()) == true)
}

@Test func idleResumesOnFirstMeaningfulAudio() {
    let clock = TestPowerModeClock()
    let tracker = AudioActivityTracker(clock: clock)
    _ = tracker.observePayload(tonePayload())
    clock.advance(by: .seconds(30))
    _ = tracker.observePayload(silentPayload())
    clock.advance(by: .seconds(10))
    let event = tracker.observePayload(tonePayload())
    #expect(event == .becameActive(idleDurationNanoseconds: 10_000_000_000))
    #expect(tracker.activityState == .active)
    #expect(tracker.shouldSuppressTransmission(for: tonePayload()) == false)
}

@Test func resetReturnsTrackerToActive() {
    let clock = TestPowerModeClock()
    let tracker = AudioActivityTracker(clock: clock)
    _ = tracker.observePayload(tonePayload())
    clock.advance(by: .seconds(30))
    _ = tracker.observePayload(silentPayload())
    #expect(tracker.activityState == .idle)
    tracker.reset()
    #expect(tracker.activityState == .active)
}

private func payload(withPeak peak: Int16) -> Data {
    var payload = Data(count: AudioStreamFormat.prototype.payloadByteCount)
    payload.withUnsafeMutableBytes { rawBuffer in
        let samples = rawBuffer.bindMemory(to: Int16.self)
        for index in 0..<samples.count {
            samples[index] = peak
        }
    }
    return payload
}

@Test func hysteresisBandPreventsOscillation() {
    let intermediate = payload(withPeak: 250)
    #expect(AudioSilenceAnalyzer.isSilent(intermediate) == false)
    #expect(AudioSilenceAnalyzer.isMeaningfulAudio(intermediate) == false)

    let clock = TestPowerModeClock()
    let tracker = AudioActivityTracker(clock: clock)
    _ = tracker.observePayload(tonePayload())

    clock.advance(by: .seconds(30))
    #expect(tracker.observePayload(intermediate) == nil)
    #expect(tracker.activityState == .active)

    clock.advance(by: .seconds(30))
    _ = tracker.observePayload(silentPayload())
    #expect(tracker.activityState == .idle)

    clock.advance(by: .seconds(30))
    #expect(tracker.observePayload(intermediate) == nil)
    #expect(tracker.activityState == .idle)
    #expect(tracker.shouldSuppressTransmission(for: intermediate) == true)
}

@Test func resumeThresholdIsHigherThanSilenceThreshold() {
    let intermediate = payload(withPeak: 250)
    #expect(HushPortConstants.audioResumePeakThreshold > HushPortConstants.audioSilencePeakThreshold)
    #expect(AudioSilenceAnalyzer.isSilent(intermediate) == false)
    #expect(AudioSilenceAnalyzer.isMeaningfulAudio(intermediate) == false)
}
