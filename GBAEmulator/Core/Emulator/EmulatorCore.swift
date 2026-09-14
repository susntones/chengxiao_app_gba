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
        atomicIsRunning.value = false
        if emulationThread != nil {
            threadExitSemaphore.wait()
        }
        if let context { emulator_destroy(context) }
    }

    /// Only the worker accesses this pointer until its exit semaphore is signalled.
    private struct WorkerContext: @unchecked Sendable {
        let pointer: OpaquePointer
    }

    // MARK: - Lifecycle

    func loadROM(at url: URL) throws {
        stop()
        state = .loading

        // Create emulator context
        guard let ctx = emulator_create() else {
            state = .stopped
            throw EmulatorError.failedToInitialize
        }
        context = ctx

        // Set save path
        let savePath = StorageService.saveFilePath(for: url.lastPathComponent)

        // Load ROM
        guard emulator_load_rom(ctx, url.path) else {
            emulator_destroy(ctx)
            context = nil
            state = .stopped
            throw EmulatorError.failedToLoadROM(url.lastPathComponent)
        }

        emulator_set_save_path(ctx, savePath.path)

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

        let worker = WorkerContext(pointer: ctx)
        let running = atomicIsRunning
        let speed = atomicSpeed
        let input = inputManager
        let audio = audioEngine
        let video = videoRenderer
        let exited = threadExitSemaphore
        // Do not retain the MainActor owner for the lifetime of the worker.
        emulationThread = Thread {
            defer { exited.signal() }
            Self.emulationLoop(worker: worker, running: running, speed: speed,
                               input: input, audio: audio, video: video)
        }
        emulationThread?.name = "com.gbaemulator.emulation"
        emulationThread?.qualityOfService = .userInteractive
        emulationThread?.start()
    }

    func pause() {
        guard state == .running else { return }
        atomicIsRunning.value = false
        joinEmulationThread()
        state = .paused
        audioEngine.pause()
    }

    func resume() {
        guard state == .paused else { return }
        start()
    }

    func stop() {
        atomicIsRunning.value = false
        state = .stopped
        audioEngine.stop()

        // Never destroy a context until its worker has acknowledged exit.
        joinEmulationThread()

        if let ctx = context {
            emulator_destroy(ctx)
            context = nil
        }
    }

    private func joinEmulationThread() {
        guard emulationThread != nil else { return }
        // Do not cancel a Thread that may not have entered its closure yet:
        // Foundation can skip the closure entirely, including its exit signal.
        // atomicIsRunning is already false; even a not-yet-started worker exits.
        threadExitSemaphore.wait()
        emulationThread = nil
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
        let wasRunning = state == .running
        if wasRunning { pause() }
        defer { if wasRunning { resume() } }
        guard let ctx = context else { return false }
        return emulator_save_state_to_file(ctx, path)
    }

    func loadState(from path: String) -> Bool {
        let wasRunning = state == .running
        if wasRunning { pause() }
        defer { if wasRunning { resume() } }
        guard let ctx = context else { return false }
        let loaded = emulator_load_state_from_file(ctx, path)
        if loaded, let buffer = emulator_get_video_buffer(ctx) {
            videoRenderer.updateFrame(buffer: buffer)
        }
        return loaded
    }

    // MARK: - Cheats

    func replaceCheats(_ cheats: [Cheat]) -> Bool {
        let wasRunning = state == .running
        if wasRunning { pause() }
        defer { if wasRunning { resume() } }
        guard let ctx = context else { return false }
        let strings = cheats.map { strdup($0.code) }
        defer { strings.forEach { free($0) } }
        guard strings.allSatisfy({ $0 != nil }) else { return false }
        let entries = zip(cheats, strings).map { cheat, string in
            EmulatorCheat(code: UnsafePointer(string), type: Int32(cheat.format.rawValue), enabled: cheat.isEnabled)
        }
        return entries.withUnsafeBufferPointer {
            emulator_replace_cheats(ctx, $0.baseAddress, $0.count)
        }
    }

    // MARK: - Game Info

    var gameTitle: String {
        guard let ctx = context else { return "" }
        let title = emulator_get_game_title(ctx)
        return title.map { String(cString: $0) } ?? ""
    }

    // MARK: - Screenshot

    func captureScreenshot() -> Data? {
        let wasRunning = state == .running
        if wasRunning { pause() }
        defer { if wasRunning { resume() } }
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
    nonisolated private static func emulationLoop(
        worker: WorkerContext, running: AtomicBool, speed: AtomicDouble,
        input: InputManager, audio: AudioEngine, video: VideoRenderer
    ) {
        let ctx = worker.pointer
        let frameTime = 1.0 / 59.7275
        var audioBuffer = [Int16](repeating: 0, count: 4096 * 2)

        while running.value && !Thread.current.isCancelled {
            let startTime = CACurrentMediaTime()

            // Poll input
            let keys = input.pollInput()
            emulator_set_keys(ctx, keys)

            // Run one frame
            emulator_run_frame(ctx)

            // Get video buffer and notify renderer (copies buffer internally)
            if let videoBuffer = emulator_get_video_buffer(ctx) {
                video.updateFrame(buffer: videoBuffer)
            }

            // Drain audio samples every frame to avoid blip_buf overflow
            let samplesAvailable = Int(emulator_get_audio_samples_available(ctx))
            if samplesAvailable > 0 {
                let samplesRead = emulator_read_audio(ctx, &audioBuffer, Int32(min(samplesAvailable, 4096)))
                if samplesRead > 0 {
                    audio.writeSamples(audioBuffer, count: Int(samplesRead))
                }
            }

            // Frame timing — sleep to maintain target FPS
            let currentSpeed = min(10.0, max(1.0, speed.value))
            let adjustedFrameTime = frameTime / currentSpeed
            let elapsed = CACurrentMediaTime() - startTime
            let sleepTime = adjustedFrameTime - elapsed
            if sleepTime > 0 {
                // Thread.sleep has sub-millisecond overshoot on iOS. Sleep for the
                // coarse portion, then spin only the final 0.5 ms so 2–10x targets
                // remain accurate without adding a full timer quantum per frame.
                // Foundation timers consistently overshoot by about 1 ms on
                // iOS/macOS. Reserve the final interval for a bounded spin; the
                // slightly larger reserve at 2x avoids timer quantization there.
                let spinReserve = currentSpeed <= 2.0 ? 0.0015 : 0.001
                if sleepTime > spinReserve {
                    Thread.sleep(forTimeInterval: sleepTime - spinReserve)
                }
                while running.value && !Thread.current.isCancelled &&
                        CACurrentMediaTime() - startTime < adjustedFrameTime {
                    // Intentionally empty: bounded to at most 0.5 ms.
                }
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
            return "模拟器核心初始化失败"
        case .failedToLoadROM(let name):
            return "无法载入游戏：\(name)"
        case .failedToSaveState:
            return "保存状态失败"
        case .failedToLoadState:
            return "读取状态失败"
        }
    }
}
