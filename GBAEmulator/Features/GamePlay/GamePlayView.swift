import SwiftUI

/// Main gameplay view - displays emulator output with controls overlay
struct GamePlayView: View {
    let game: Game
    @StateObject private var viewModel: GamePlayViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(game: Game) {
        self.game = game
        _viewModel = StateObject(wrappedValue: GamePlayViewModel(game: game))
    }

    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()

            // Game screen (Metal rendering)
            MetalView(renderer: viewModel.videoRenderer)
                .aspectRatio(240.0 / 160.0, contentMode: .fit)

            // Keep touch controls mounted for the entire gameplay session. On iOS,
            // GameController may transiently report the software keyboard or another
            // input source as a controller after tapping an overlay button. Removing
            // this view then destroys every button's gesture state and makes the
            // controls appear to vanish after fast-forward/pause.
            ControllerOverlay(inputManager: viewModel.inputManager)
                .allowsHitTesting(!viewModel.isPaused)

            // Fast forward indicator
            if viewModel.isFastForwarding {
                FastForwardIndicator(speed: viewModel.speedMultiplier)
            }

            // Pause menu overlay
            if viewModel.isPaused {
                PauseMenuView(
                    viewModel: viewModel,
                    onResume: { viewModel.resume() },
                    onQuit: {
                        viewModel.stop()
                        dismiss()
                    }
                )
            }

            // Pause button (top-right corner)
            if !viewModel.isPaused {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.pause()
                        } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(8)
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                        .accessibilityLabel("暂停")
                        .accessibilityIdentifier("pauseButton")
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
            }

            // Fast forward button (top-left corner)
            if !viewModel.isPaused {
                VStack {
                    HStack {
                        Button {
                            viewModel.toggleFastForward()
                        } label: {
                            Image(systemName: viewModel.isFastForwarding ? "forward.fill" : "forward")
                                .font(.title3)
                                .foregroundColor(viewModel.isFastForwarding ? .yellow : .white.opacity(0.7))
                                .padding(8)
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                        .accessibilityLabel(viewModel.isFastForwarding ? "关闭快进" : "开启快进")
                        .accessibilityIdentifier("fastForwardButton")
                        .padding(.leading, 16)
                        .padding(.top, 8)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.startGame()
        }
        .onDisappear { viewModel.stop() }
        .alert("无法运行游戏", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("返回游戏库") { dismiss() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                viewModel.autoSaveAndPause()
            case .inactive:
                viewModel.pause()
            case .active:
                // Don't auto-resume - let user tap resume
                break
            @unknown default:
                break
            }
        }
    }
}

// MARK: - GamePlay ViewModel

@MainActor
final class GamePlayViewModel: ObservableObject {
    // MARK: - Published State
    @Published var errorMessage: String?
    @Published var isPaused = false
    @Published var isFastForwarding = false
    @Published var speedMultiplier: Double = 1.0
    @Published var showingSaveStates = false
    @Published var saveStateMode: SaveStateMode = .save

    enum SaveStateMode {
        case save, load
    }

    // MARK: - Core Components
    let inputManager = InputManager()
    let audioEngine = AudioEngine()
    let videoRenderer: VideoRenderer
    private let emulatorCore: EmulatorCore
    private let saveStateManager: SaveStateManager
    let game: Game

    // MARK: - Play Time Tracking
    private var playStartTime: Date?

    init(game: Game) {
        self.game = game

        guard let renderer = VideoRenderer() else {
            fatalError("Metal is not available on this device. GBA Emulator requires a Metal-capable device.")
        }
        self.videoRenderer = renderer

        self.emulatorCore = EmulatorCore(
            inputManager: inputManager,
            audioEngine: audioEngine,
            videoRenderer: renderer
        )
        self.saveStateManager = SaveStateManager()
    }

    // MARK: - Game Lifecycle

    func startGame() {
        guard emulatorCore.state == .stopped else { return }
        do {
            try emulatorCore.loadROM(at: game.romURL)

            // Try to load auto-save if exists
            let autoSavePath = StorageService.autoSaveStatePath(
                for: game.persistentModelID.hashValue.description
            )
            if FileManager.default.fileExists(atPath: autoSavePath.path) {
                _ = emulatorCore.loadState(from: autoSavePath.path)
            }

            emulatorCore.start()
            playStartTime = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        guard !isPaused else { return }
        inputManager.releaseAllTouchButtons()
        isPaused = true
        emulatorCore.pause()
        updatePlayTime()
    }

    func resume() {
        isPaused = false
        emulatorCore.resume()
        playStartTime = Date()
    }

    func stop() {
        guard emulatorCore.state != .stopped else { return }
        pause()
        autoSave()
        emulatorCore.stop()
        updatePlayTime()
    }

    // MARK: - Fast Forward

    func toggleFastForward() {
        isFastForwarding.toggle()
        emulatorCore.setFastForward(isFastForwarding)
        speedMultiplier = isFastForwarding ? SettingsManager.shared.fastForwardSpeed.rawValue : 1.0
        audioEngine.setFastForwardMode(isFastForwarding)
    }

    // MARK: - Save States

    func saveState(slot: Int) {
        let gameID = game.persistentModelID.hashValue.description
        StorageService.createStatesDirectory(for: gameID)
        let path = StorageService.stateFilePath(for: gameID, slot: slot)

        if emulatorCore.saveState(to: path.path) {
            // Save thumbnail
            if let screenshotData = emulatorCore.captureScreenshot() {
                let thumbnailPath = StorageService.stateThumbnailPath(for: gameID, slot: slot)
                try? screenshotData.write(to: thumbnailPath)
            }

            // Save metadata
            let metadata = SaveStateMetadata(
                slot: slot,
                date: Date(),
                isLocked: false,
                isAutoSave: false
            )
            let metadataPath = StorageService.stateMetadataPath(for: gameID, slot: slot)
            if let data = try? JSONEncoder().encode(metadata) {
                try? data.write(to: metadataPath)
            }

            HapticsService.shared.saveState()
        }
    }

    func loadState(slot: Int) {
        let gameID = game.persistentModelID.hashValue.description
        let path = StorageService.stateFilePath(for: gameID, slot: slot)

        if emulatorCore.loadState(from: path.path) {
            resume()
        }
    }

    func autoSave() {
        guard SettingsManager.shared.autoSaveEnabled else { return }
        let gameID = game.persistentModelID.hashValue.description
        StorageService.createStatesDirectory(for: gameID)
        let path = StorageService.autoSaveStatePath(for: gameID)
        _ = emulatorCore.saveState(to: path.path)

        // Save auto-save thumbnail
        if let screenshotData = emulatorCore.captureScreenshot() {
            let thumbnailPath = StorageService.autoSaveThumbnailPath(for: gameID)
            try? screenshotData.write(to: thumbnailPath)
        }
    }

    func autoSaveAndPause() {
        pause()
        autoSave()
    }

    // MARK: - Save State Info

    func getSaveStates() -> [SaveStateInfo] {
        let gameID = game.persistentModelID.hashValue.description
        var states: [SaveStateInfo] = []

        for slot in 0..<10 {
            let statePath = StorageService.stateFilePath(for: gameID, slot: slot)
            let thumbnailPath = StorageService.stateThumbnailPath(for: gameID, slot: slot)
            let metadataPath = StorageService.stateMetadataPath(for: gameID, slot: slot)

            if FileManager.default.fileExists(atPath: statePath.path) {
                var metadata: SaveStateMetadata?
                if let data = try? Data(contentsOf: metadataPath) {
                    metadata = try? JSONDecoder().decode(SaveStateMetadata.self, from: data)
                }

                states.append(SaveStateInfo(
                    slot: slot,
                    exists: true,
                    date: metadata?.date,
                    thumbnailURL: thumbnailPath,
                    isLocked: metadata?.isLocked ?? false
                ))
            } else {
                states.append(SaveStateInfo(slot: slot, exists: false))
            }
        }

        return states
    }

    // MARK: - Play Time

    private func updatePlayTime() {
        guard let startTime = playStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        game.totalPlayTime += elapsed
        playStartTime = nil
    }
}

// MARK: - Save State Models

struct SaveStateMetadata: Codable {
    let slot: Int
    let date: Date
    let isLocked: Bool
    let isAutoSave: Bool
}

struct SaveStateInfo: Identifiable {
    let slot: Int
    let exists: Bool
    var date: Date?
    var thumbnailURL: URL?
    var isLocked: Bool = false

    var id: Int { slot }
}
