import HushPortRingBuffer
import Testing

@Test func ringBufferPreservesFramesAcrossWraparound() throws {
    let buffer = try #require(PHRingBufferCreate(4, 2))
    defer { PHRingBufferDestroy(buffer) }

    var first: [UInt16] = [10, 11, 12]
    #expect(PHRingBufferWrite(buffer, &first, 3) == 3)

    var firstRead = [UInt16](repeating: 0, count: 2)
    #expect(PHRingBufferRead(buffer, &firstRead, 2) == 2)
    #expect(firstRead == [10, 11])

    var second: [UInt16] = [13, 14, 15]
    #expect(PHRingBufferWrite(buffer, &second, 3) == 3)

    var finalRead = [UInt16](repeating: 0, count: 4)
    #expect(PHRingBufferRead(buffer, &finalRead, 4) == 4)
    #expect(finalRead == [12, 13, 14, 15])
}

@Test func ringBufferReportsOverrunAndUnderrunWithoutBlocking() throws {
    let buffer = try #require(PHRingBufferCreate(2, 1))
    defer { PHRingBufferDestroy(buffer) }

    var input: [UInt8] = [1, 2, 3]
    #expect(PHRingBufferWrite(buffer, &input, 3) == 2)
    #expect(PHRingBufferReadableFrames(buffer) == 2)
    #expect(PHRingBufferWritableFrames(buffer) == 0)

    var output = [UInt8](repeating: 0, count: 3)
    #expect(PHRingBufferRead(buffer, &output, 3) == 2)
    #expect(Array(output.prefix(2)) == [1, 2])
    #expect(PHRingBufferRead(buffer, &output, 1) == 0)
}

@Test func sharedAudioTransfersInterleavedStereoFrames() throws {
    let writer = try #require(HushPortSharedAudioOpenWriter())
    defer { HushPortSharedAudioClose(writer) }
    let reader = try #require(HushPortSharedAudioOpenReader())
    defer { HushPortSharedAudioClose(reader) }

    var input: [Float] = [0.25, -0.25, 0.5, -0.5]
    HushPortSharedAudioWriteFloat32(writer, &input, 2)

    var output = [Float](repeating: 0, count: 4)
    #expect(HushPortSharedAudioReadFloat32(reader, &output, 2) == 2)
    #expect(output == input)
}
