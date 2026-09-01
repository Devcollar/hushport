import Foundation

public enum HushPortConstants {
    public static let audioPort: UInt16 = 49_200
    public static let controlPort: UInt16 = 49_201
    public static let bonjourServiceType = "_hushport._udp"
    public static let controlBonjourServiceType = "_hushport-control._udp"
    public static let defaultStreamID: UInt64 = 1

    /// Packets to receive before playback starts (~60ms at 5ms/packet).
    public static let defaultPrebufferPackets = 12
    public static let minimumPrebufferPackets = 8
    public static let maximumPrebufferPackets = 20
    /// Repeat the last good packet this many times before skipping a gap.
    public static let maxConcealmentPacketsPerGap = 3
    /// Start trimming only when the jitter queue stays above this depth (~140ms).
    public static let maximumPlaybackLatencyPackets = 28
    /// Require sustained backlog for this long before dropping one packet.
    public static let sustainedBacklogTrimNanoseconds: UInt64 = 3_000_000_000

    /// Continuous silence before Mac stops sending audio UDP packets while streaming intent stays on.
    public static let audioIdleThreshold: Duration = .seconds(30)

    /// Peak sample magnitude below this counts as silence when entering idle.
    public static let audioSilencePeakThreshold: Int16 = 180

    /// Peak sample magnitude at or above this resumes transmission from idle.
    public static let audioResumePeakThreshold: Int16 = 350

    /// iPhone playback may suspend after this long without new packets while still listening.
    public static let playbackSuspendAfterNoPackets: Duration = .seconds(30)
}
