import Foundation
import Testing
@testable import HushPortCore

@Test func streamHealthDetectsStableTraffic() {
    var tracker = StreamHealthTracker()
    let packetDuration = UInt64(AudioStreamFormat.prototype.framesPerPacket) * 1_000_000_000
        / UInt64(AudioStreamFormat.prototype.sampleRate)
    var now: UInt64 = 1_000_000_000
    for _ in 0..<16 {
        tracker.recordPacketArrival(now: now)
        now &+= packetDuration
    }
    #expect(tracker.quality == .excellent || tracker.quality == .good)
}

@Test func streamHealthDetectsJitteryTraffic() {
    var tracker = StreamHealthTracker()
    let packetDuration = UInt64(AudioStreamFormat.prototype.framesPerPacket) * 1_000_000_000
        / UInt64(AudioStreamFormat.prototype.sampleRate)
    var now: UInt64 = 1_000_000_000
    for index in 0..<16 {
        tracker.recordPacketArrival(now: now)
        now &+= packetDuration * UInt64(index.isMultiple(of: 2) ? 4 : 1)
    }
    #expect(tracker.quality == .poor || tracker.quality == .fair)
}

@Test func streamHealthKeepsStableScheduleAheadWhenPoor() {
    var tracker = StreamHealthTracker()
    for _ in 0..<6 {
        tracker.recordGapSkip()
    }
    #expect(tracker.recommendedScheduleAhead == 8)
}
