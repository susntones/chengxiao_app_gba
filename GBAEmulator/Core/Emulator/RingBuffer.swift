import Foundation

/// Single-Producer Single-Consumer ring buffer for audio samples.
/// Uses NSLock for thread safety between emulation and audio threads.
final class RingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Int16>
    private let capacity: Int

    // Atomic indices using os_unfair_lock for simplicity on iOS
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<Int16>.allocate(capacity: capacity * 2) // stereo
        self.buffer.initialize(repeating: 0, count: capacity * 2)
    }

    deinit {
        buffer.deallocate()
    }

    /// Number of stereo frames available to read
    var availableFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        let available = writeIndex - readIndex
        return available >= 0 ? available : available + capacity
    }

    /// Available space for writing (stereo frames)
    var availableSpace: Int {
        return capacity - availableFrames - 1
    }

    /// Write stereo samples. Returns number of frames actually written.
    @discardableResult
    func write(_ samples: [Int16], count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let space = capacity - (writeIndex - readIndex + capacity) % capacity - 1
        let framesToWrite = min(count, space)

        if framesToWrite <= 0 { return 0 }

        for i in 0..<framesToWrite {
            let writePos = (writeIndex + i) % capacity
            buffer[writePos * 2] = samples[i * 2]       // left
            buffer[writePos * 2 + 1] = samples[i * 2 + 1] // right
        }

        writeIndex = (writeIndex + framesToWrite) % capacity
        return framesToWrite
    }

    /// Read stereo samples into buffer. Returns number of frames read.
    @discardableResult
    func read(into output: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let available = (writeIndex - readIndex + capacity) % capacity
        let framesToRead = min(maxFrames, available)

        if framesToRead <= 0 { return 0 }

        for i in 0..<framesToRead {
            let readPos = (readIndex + i) % capacity
            output[i * 2] = buffer[readPos * 2]         // left
            output[i * 2 + 1] = buffer[readPos * 2 + 1] // right
        }

        readIndex = (readIndex + framesToRead) % capacity
        return framesToRead
    }

    /// Clear all buffered audio
    func reset() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        lock.unlock()
    }
}
