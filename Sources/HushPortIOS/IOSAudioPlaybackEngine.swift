#if os(iOS)
import AVFAudio
import Foundation
import HushPortCore

@MainActor
final class IOSAudioPlaybackEngine {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var playbackFormat: AVAudioFormat?
    private var isGraphPrepared = false
    private var sessionConfigured = false
    private var scheduleGeneration: UInt64 = 0
    private var scheduledBufferCount = 0
    private var maxScheduledBuffers = 24
    private var softenNextBuffer = false

    var onNeedsMoreAudio: (() -> Void)?

    var isRunning: Bool {
        isGraphPrepared && engine.isRunning
    }

    var canAcceptMoreBuffers: Bool {
        scheduledBufferCount < maxScheduledBuffers
    }

    var scheduledPackets: Int {
        scheduledBufferCount
    }

    func setScheduleAheadLimit(_ packets: Int) {
        maxScheduledBuffers = min(max(packets, 8), 32)
    }

    func prepare() throws {
        try configureSessionIfNeeded()
        try prepareGraphIfNeeded()
        try ensurePlaying()
    }

    func ensurePlaying() throws {
        try configureSessionIfNeeded()
        if !isGraphPrepared {
            try prepareGraphIfNeeded()
        }
        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
        player.volume = 1
    }

    func prepareForBackground() throws {
        try configureSessionIfNeeded()
        try ensurePlaying()
    }

    func stop() {
        scheduleGeneration &+= 1
        scheduledBufferCount = 0
        softenNextBuffer = false
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
    }

    func reset() {
        stop()
        if engine.attachedNodes.contains(player) {
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        isGraphPrepared = false
        playbackFormat = nil
        sessionConfigured = false
    }

    func markNextBufferSoftened() {
        softenNextBuffer = true
    }

    @discardableResult
    func schedule(payload: Data, softened: Bool = false) -> Bool {
        let streamFormat = AudioStreamFormat.prototype
        guard payload.count == streamFormat.payloadByteCount else { return false }

        if !isGraphPrepared || !engine.isRunning {
            do {
                try ensurePlaying()
            } catch {
                return false
            }
        }
        guard isGraphPrepared,
              engine.isRunning,
              scheduledBufferCount < maxScheduledBuffers,
              let audioFormat = playbackFormat,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFormat,
                frameCapacity: AVAudioFrameCount(streamFormat.framesPerPacket)
              ),
              let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else {
            return false
        }

        buffer.frameLength = buffer.frameCapacity
        let frameCount = Int(buffer.frameLength)
        payload.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<frameCount {
                left[index] = Self.floatSample(samples[index * 2])
                right[index] = Self.floatSample(samples[index * 2 + 1])
            }
        }

        if softened || softenNextBuffer {
            Self.applyFadeIn(left: left, right: right, frameCount: frameCount)
            softenNextBuffer = false
        }

        if !player.isPlaying {
            player.play()
        }

        let generation = scheduleGeneration
        scheduledBufferCount += 1
        player.scheduleBuffer(buffer, completionHandler: completionHandler(generation: generation))
        return true
    }

    private func completionHandler(generation: UInt64) -> AVAudioNodeCompletionHandler {
        { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.scheduleGeneration else { return }
                self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                self.onNeedsMoreAudio?()
            }
        }
    }

    private static func floatSample(_ sample: Int16) -> Float {
        if sample < 0 {
            return Float(sample) / 32768.0
        }
        return Float(sample) / 32767.0
    }

    private static func applyFadeIn(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int) {
        let fadeSamples = min(64, frameCount)
        guard fadeSamples > 0 else { return }
        for index in 0..<fadeSamples {
            let gain = Float(index + 1) / Float(fadeSamples)
            left[index] *= gain
            right[index] *= gain
        }
    }

    private func configureSessionIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()
        if sessionConfigured {
            try session.setActive(true, options: [])
            return
        }

        let configurations: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.playback, .default, [.allowBluetoothA2DP]),
            (.playback, .default, []),
        ]

        var lastError: Error?
        for (category, mode, options) in configurations {
            do {
                try session.setCategory(category, mode: mode, options: options)
                try? session.setPreferredIOBufferDuration(0.01)
                try session.setActive(true, options: [])
                sessionConfigured = true
                return
            } catch {
                lastError = error
            }
        }

        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        for (category, mode, options) in configurations {
            do {
                try session.setCategory(category, mode: mode, options: options)
                try session.setActive(true, options: [])
                sessionConfigured = true
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NSError(domain: NSOSStatusErrorDomain, code: -50)
    }

    private func prepareGraphIfNeeded() throws {
        guard !isGraphPrepared else { return }
        let streamFormat = AudioStreamFormat.prototype
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(streamFormat.sampleRate),
            channels: AVAudioChannelCount(streamFormat.channelCount)
        ) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -50)
        }
        playbackFormat = format
        if !engine.attachedNodes.contains(player) {
            engine.attach(player)
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        isGraphPrepared = true
    }
}
#endif
