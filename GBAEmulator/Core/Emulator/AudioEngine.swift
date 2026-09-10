import Foundation
import AVFoundation

/// Audio engine that plays GBA audio samples via AVAudioEngine
// Engine control is main-thread-only; worker access is limited to the locked ring
// buffer, and the render callback reads only the ring buffer and atomic mute flag.
final class AudioEngine: @unchecked Sendable {
    // MARK: - Properties
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let ringBuffer: RingBuffer

    // Audio format
    private let gbaSourceRate: Double = 32768.0
    private(set) var sampleRate: Double = 48000.0
    private let channelCount: Int = 2

    // State
    private(set) var isRunning = false
    private let isMuted = AtomicBool(false)

    // Ring buffer capacity (frames)
    private let bufferCapacity = 8192

    // MARK: - Init

    init() {
        ringBuffer = RingBuffer(capacity: bufferCapacity)
        setupAudioSession()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(48000)
            try session.setActive(true)
            sampleRate = session.sampleRate
        } catch {
            print("AudioEngine: Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        )!

        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count == 2,
                  let left = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let framesNeeded = Int(frameCount)
            self.ringBuffer.read(left: left, right: right, frames: framesNeeded)
            if self.isMuted.value {
                left.update(repeating: 0, count: framesNeeded)
                right.update(repeating: 0, count: framesNeeded)
            }

            return noErr
        }

        guard let sourceNode = sourceNode else { return }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }

        if sourceNode == nil { setupEngine() }
        ringBuffer.reset()

        do {
            try engine.start()
            isRunning = true
        } catch {
            print("AudioEngine: Failed to start engine: \(error)")
        }
    }

    func pause() {
        engine.pause()
        ringBuffer.reset()
        isRunning = false
    }

    func stop() {
        engine.stop()
        if let sourceNode = sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
        ringBuffer.reset()
        isRunning = false
    }

    func resume() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            print("AudioEngine: Failed to resume: \(error)")
        }
    }

    // MARK: - Audio Data

    /// Write audio samples from emulation thread to ring buffer
    func writeSamples(_ samples: [Int16], count: Int) {
        // The core still drains its audio while fast-forwarding, but copying audio
        // into a real-time buffer that cannot keep up at 10x only wastes CPU.
        guard !isMuted.value else { return }
        ringBuffer.write(samples, count: count)
    }

    // MARK: - Volume / Mute

    func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }

    func setMuted(_ muted: Bool) {
        isMuted.value = muted
    }

    /// Mute audio during fast forward to avoid chipmunk effect
    func setFastForwardMode(_ enabled: Bool) {
        isMuted.value = enabled
        ringBuffer.reset()
    }
}
