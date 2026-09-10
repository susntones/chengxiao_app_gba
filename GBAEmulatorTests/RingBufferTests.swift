import Testing
@testable import GBAEmulator

struct RingBufferTests {
    @Test func writeAndRead() {
        let buffer = RingBuffer(capacity: 1024)

        // Write 100 stereo frames
        var samples = [Int16](repeating: 0, count: 200)
        for i in 0..<200 {
            samples[i] = Int16(i)
        }

        let written = buffer.write(samples, count: 100)
        #expect(written == 100)
        #expect(buffer.availableFrames == 100)

        // Read them back
        var output = [Int16](repeating: 0, count: 200)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, maxFrames: 100)
        }
        #expect(read == 100)
        #expect(output[0] == 0)
        #expect(output[1] == 1)
        #expect(output[198] == 198)
        #expect(output[199] == 199)
    }

    @Test func bufferOverflow() {
        let buffer = RingBuffer(capacity: 64)

        // Try to write more than capacity
        let samples = [Int16](repeating: 42, count: 200)
        let written = buffer.write(samples, count: 100)

        // Should only write up to capacity - 1
        #expect(written < 100)
        #expect(written == 63) // capacity - 1
    }

    @Test func emptyRead() {
        let buffer = RingBuffer(capacity: 1024)

        var output = [Int16](repeating: 99, count: 100)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, maxFrames: 50)
        }

        #expect(read == 0)
    }

    @Test func planarFloatConversionAndUnderrun() {
        let buffer = RingBuffer(capacity: 8)
        #expect(buffer.write([.min, .max, 16384, -16384], count: 99) == 2)
        var left = [Float](repeating: 99, count: 4)
        var right = [Float](repeating: 99, count: 4)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                buffer.read(left: l.baseAddress!, right: r.baseAddress!, frames: 4)
            }
        }
        #expect(left == [-1, 0.5, 0, 0])
        #expect(right == [Float(Int16.max) / 32768, -0.5, 0, 0])
        #expect(buffer.availableFrames == 0)
    }

    @Test func wraparound() {
        let buffer = RingBuffer(capacity: 4)
        buffer.write([1, 2, 3, 4, 5, 6], count: 3)
        var output = [Int16](repeating: 0, count: 6)
        output.withUnsafeMutableBufferPointer { ptr in
            #expect(buffer.read(into: ptr.baseAddress!, maxFrames: 2) == 2)
        }
        #expect(buffer.write([7, 8, 9, 10], count: 2) == 2)
        output.withUnsafeMutableBufferPointer { ptr in
            #expect(buffer.read(into: ptr.baseAddress!, maxFrames: 3) == 3)
        }
        #expect(output == [5, 6, 7, 8, 9, 10])
    }

    @Test func reset() {
        let buffer = RingBuffer(capacity: 1024)

        let samples = [Int16](repeating: 1, count: 100)
        buffer.write(samples, count: 50)
        #expect(buffer.availableFrames == 50)

        buffer.reset()
        #expect(buffer.availableFrames == 0)
    }
}
