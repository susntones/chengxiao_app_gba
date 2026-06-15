import Foundation
import AVFoundation

/// Audio engine that plays GBA audio samples via AVAudioEngine
final class AudioEngine {
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
    private var isMuted = false

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
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: true
        )!

        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = ablPointer.first,
                  let data = buffer.mData?.assumingMemoryBound(to: Int16.self) else {
                return noErr
            }

            let framesNeeded = Int(frameCount)

            if self.isMuted {
                // Output silence when muted
                memset(data, 0, framesNeeded * self.channelCount * MemoryLayout<Int16>.size)
                return noErr
            }

            // Read from ring buffer
            let framesRead = self.ringBuffer.read(into: data, maxFrames: framesNeeded)

            // Fill remaining with silence to prevent noise
            if framesRead < framesNeeded {
                let remainingStart = data.advanced(by: framesRead * self.channelCount)
                let remainingBytes = (framesNeeded - framesRead) * self.channelCount * MemoryLayout<Int16>.size
                memset(remainingStart, 0, remainingBytes)
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

        setupEngine()

        do {
            try engine.start()
            isRunning = true
        } catch {
            print("AudioEngine: Failed to start engine: \(error)")
        }
    }

    func pause() {
        engine.pause()
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
        ringBuffer.write(samples, count: count)
    }

    // MARK: - Volume / Mute

    func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    /// Mute audio during fast forward to avoid chipmunk effect
    func setFastForwardMode(_ enabled: Bool) {
        isMuted = enabled
    }
}
