#if os(macOS)
import Foundation
import HushPortCore
import HushPortRingBuffer

enum SharedAudioCaptureError: LocalizedError {
    case driverNotRunning

    var errorDescription: String? {
        "HushPort Audio is not running. Install the audio driver and restart the Mac first."
    }
}

final class SharedAudioCapture: @unchecked Sendable {
    private static let catchUpLatencyFrames: UInt32 = 2_400

    private let handle: OpaquePointer
    private var floatSamples: [Float]
    private var integerSamples: [Int16]

    init() throws {
        guard let handle = HushPortSharedAudioOpenReader() else {
            throw SharedAudioCaptureError.driverNotRunning
        }
        self.handle = handle
        let sampleCount = Int(AudioStreamFormat.prototype.framesPerPacket) * 2
        floatSamples = .init(repeating: 0, count: sampleCount)
        integerSamples = .init(repeating: 0, count: sampleCount)
    }

    deinit {
        HushPortSharedAudioClose(handle)
    }

    func discardBufferedFrames(upTo maxLatencyFrames: UInt32 = catchUpLatencyFrames) {
        HushPortSharedAudioCatchUp(handle, maxLatencyFrames)
    }

    func readPayload() -> Data? {
        let requestedFrames = UInt32(AudioStreamFormat.prototype.framesPerPacket)
        let frameCount = floatSamples.withUnsafeMutableBufferPointer { buffer in
            HushPortSharedAudioReadFloat32(handle, buffer.baseAddress, requestedFrames)
        }
        guard frameCount == requestedFrames else { return nil }

        for index in integerSamples.indices {
            let sample = floatSamples[index]
            let clamped = min(max(sample, -1), 1)
            if clamped < 0 {
                integerSamples[index] = Int16(clamped * 32768.0)
            } else {
                integerSamples[index] = Int16(clamped * 32767.0)
            }
        }
        return integerSamples.withUnsafeBytes { Data($0) }
    }
}
#endif
