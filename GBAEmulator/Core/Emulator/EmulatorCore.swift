import Foundation
import Combine
import UIKit
import os

// MARK: - Emulator State
enum EmulatorState: Equatable {
    case stopped
    case loading
    case running
    case paused
}

// MARK: - Thread-Safe Atomic Wrappers

/// Thread-safe Bool using os_unfair_lock
final class AtomicBool: @unchecked Sendable {
    private var _value: Bool
    private var lock = os_unfair_lock()

    init(_ value: Bool) { _value = value }

    var value: Bool {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _value }
        set { os_unfair_lock_lock(&lock); _value = newValue; os_unfair_lock_unlock(&lock) }
    }
}

/// Thread-safe Double using os_unfair_lock
final class AtomicDouble: @unchecked Sendable {
    private var _value: Double
    private var lock = os_unfair_lock()

    init(_ value: Double) { _value = value }

    var value: Double {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _value }
        set { os_unfair_lock_lock(&lock); _value = newValue; os_unfair_lock_unlock(&lock) }
    }
}

// MARK: - Emulator Core
@MainActor
final class EmulatorCore: ObservableObject {
    // MARK: - Published State
    @Published private(set) var state: EmulatorState = .stopped
    @Published var speedMultiplier: Double = 1.0

    // MARK: - Thread-Safe State (accessed from emulation thread)
    private let atomicIsRunning = AtomicBool(false)
    private let atomicSpeed = AtomicDouble(1.0)

    // MARK: - Internal State
    private var context: OpaquePointer? // EmulatorContext*
    private var emulationThread: Thread?
    private let inputManager: InputManager
    private let audioEngine: AudioEngine
    private let videoRenderer: VideoRenderer

    // MARK: - Thread Synchronization
    private let threadExitSemaphore = DispatchSemaphore(value: 0)

    // MARK: - Frame Timing
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private let targetFrameTime: CFTimeInterval = 1.0 / 59.7275 // GBA native refresh rate

    // MARK: - Callbacks
    var onFrameReady: ((UnsafePointer<UInt32>) -> Void)?

    // MARK: - Init

    init(inputManager: InputManager, audioEngine: AudioEngine, videoRenderer: VideoRenderer) {
        self.inputManager = inputManager
        self.audioEngine = audioEngine
        self.videoRenderer = videoRenderer
    }

    deinit {
        // Signal emulation thread to stop; full teardown happens via stop()
        atomicIsRunning.value = false
    }

    // MARK: - Lifecycle

    func loadROM(at url: URL) throws {
        state = .loading

        // Create emulator context
        guard let ctx = emulator_create() else {
            state = .stopped
            throw EmulatorError.failedToInitialize
        }
        context = ctx

        // Set save path
        let savePath = StorageService.saveFilePath(for: url.lastPathComponent)
        emulator_set_save_path(ctx, savePath.path)

        // Load ROM
        guard emulator_load_rom(ctx, url.path) else {
            emulator_destroy(ctx)
            context = nil
            state = .stopped
            throw EmulatorError.failedToLoadROM(url.lastPathComponent)
        }

        // Set audio sample rate to device rate
        let sampleRate = audioEngine.sampleRate
        emulator_set_audio_sample_rate(ctx, sampleRate)

        // Skip BIOS by default
        emulator_set_skip_bios(ctx, true)

        state = .paused
    }

    func start() {
        guard state == .paused, let ctx = context else { return }

        state = .running
        atomicIsRunning.value = true
        atomicSpeed.value = speedMultiplier

        // Start audio engine
        audioEngine.start()

        // Start emulation thread, passing OpaquePointer (EmulatorContext*) directly
        emulationThread = Thread { [weak self] in
            self?.emulationLoop(ctx: ctx)
            self?.threadExitSemaphore.signal()
        }
        emulationThread?.name = "com.gbaemulator.emulation"
        emulationThread?.qualityOfService = .userInteractive
        emulationThread?.start()
    }

    func pause() {
        guard state == .running else { return }
        atomicIsRunning.value = false
        state = .paused
        audioEngine.pause()

        // Wait for emulation thread to exit (max 100ms)
        _ = threadExitSemaphore.wait(timeout: .now() + 0.1)
    }

    func resume() {
        guard state == .paused else { return }
        start()
    }

    func stop() {
        atomicIsRunning.value = false
        state = .stopped
        audioEngine.stop()

        // Wait for emulation thread to fully exit before destroying context
        emulationThread?.cancel()
        _ = threadExitSemaphore.wait(timeout: .now() + 0.5)
        emulationThread = nil

        if let ctx = context {
            emulator_destroy(ctx)
            context = nil
        }
    }

    // MARK: - Speed Control

    func setFastForward(_ enabled: Bool) {
        if enabled {
            speedMultiplier = SettingsManager.shared.fastForwardSpeed.rawValue
        } else {
            speedMultiplier = 1.0
        }
        atomicSpeed.value = speedMultiplier
    }

    func toggleFastForward() {
        if speedMultiplier > 1.0 {
            setFastForward(false)
        } else {
            setFastForward(true)
        }
    }

    // MARK: - Save States

    func saveState(to path: String) -> Bool {
        guard let ctx = context else { return false }
        return emulator_save_state_to_file(ctx, path)
    }

    func loadState(from path: String) -> Bool {
        guard let ctx = context else { return false }
        return emulator_load_state_from_file(ctx, path)
    }

    // MARK: - Game Info

    var gameTitle: String {
        guard let ctx = context else { return "" }
        let title = emulator_get_game_title(ctx)
        return title.map { String(cString: $0) } ?? ""
    }

    // MARK: - Screenshot

    func captureScreenshot() -> Data? {
        guard let ctx = context else { return nil }
        guard let buffer = emulator_get_video_buffer(ctx) else { return nil }

        let width = Int(GBA_SCREEN_WIDTH)
        let height = Int(GBA_SCREEN_HEIGHT)

        guard let cgCtx = CGContext(
            data: UnsafeMutableRawPointer(mutating: buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let cgImage = cgCtx.makeImage() else { return nil }

        // Scale to 2x for thumbnail
        let scaledWidth = width * 2
        let scaledHeight = height * 2
        guard let scaledCtx = CGContext(
            data: nil,
            width: scaledWidth,
            height: scaledHeight,
            bitsPerComponent: 8,
            bytesPerRow: scaledWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        scaledCtx.interpolationQuality = .none
        scaledCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))

        guard let scaledImage = scaledCtx.makeImage() else { return nil }

        return UIImage(cgImage: scaledImage).pngData()
    }

    // MARK: - Emulation Loop (runs on dedicated thread)

    /// OpaquePointer maps to EmulatorContext* — safe to capture across threads since
    /// the context lifetime is managed by atomicIsRunning + threadExitSemaphore.
    private func emulationLoop(ctx: OpaquePointer) {
        let frameTime = targetFrameTime

        while atomicIsRunning.value && !Thread.current.isCancelled {
            let startTime = CACurrentMediaTime()

            // Poll input
            let keys = inputManager.pollInput()
            emulator_set_keys(ctx, keys)

            // Run one frame
            emulator_run_frame(ctx)

            // Get video buffer and notify renderer (copies buffer internally)
            if let videoBuffer = emulator_get_video_buffer(ctx) {
                videoRenderer.updateFrame(buffer: videoBuffer)
            }

            // Drain audio samples every frame to avoid blip_buf overflow
            let samplesAvailable = Int(emulator_get_audio_samples_available(ctx))
            if samplesAvailable > 0 {
                var audioBuffer = [Int16](repeating: 0, count: samplesAvailable * 2)
                let samplesRead = emulator_read_audio(ctx, &audioBuffer, Int32(samplesAvailable))
                if samplesRead > 0 {
                    audioEngine.writeSamples(audioBuffer, count: Int(samplesRead))
                }
            }

            // Frame timing — sleep to maintain target FPS
            let currentSpeed = atomicSpeed.value
            let adjustedFrameTime = frameTime / currentSpeed
            let elapsed = CACurrentMediaTime() - startTime
            let sleepTime = adjustedFrameTime - elapsed
            if sleepTime > 0 {
                Thread.sleep(forTimeInterval: sleepTime)
            }
        }
    }
}

// MARK: - Errors

enum EmulatorError: LocalizedError {
    case failedToInitialize
    case failedToLoadROM(String)
    case failedToSaveState
    case failedToLoadState

    var errorDescription: String? {
        switch self {
        case .failedToInitialize:
            return "Failed to initialize the emulator core"
        case .failedToLoadROM(let name):
            return "Failed to load ROM: \(name)"
        case .failedToSaveState:
            return "Failed to save state"
        case .failedToLoadState:
            return "Failed to load state"
        }
    }
}
