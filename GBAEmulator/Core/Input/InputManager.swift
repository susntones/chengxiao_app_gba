import Foundation
import GameController

/// GBA button bitmask matching mGBA key definitions
struct GBAButton: OptionSet, Sendable {
    let rawValue: UInt16

    static let a      = GBAButton(rawValue: 1 << 0)
    static let b      = GBAButton(rawValue: 1 << 1)
    static let select = GBAButton(rawValue: 1 << 2)
    static let start  = GBAButton(rawValue: 1 << 3)
    static let right  = GBAButton(rawValue: 1 << 4)
    static let left   = GBAButton(rawValue: 1 << 5)
    static let up     = GBAButton(rawValue: 1 << 6)
    static let down   = GBAButton(rawValue: 1 << 7)
    static let r      = GBAButton(rawValue: 1 << 8)
    static let l      = GBAButton(rawValue: 1 << 9)

    static let none: GBAButton = []
}

/// Unified input manager that merges touch and controller inputs
final class InputManager: ObservableObject, @unchecked Sendable {
    // MARK: - Published State
    @Published var isControllerConnected = false
    @Published private(set) var activeButtons: GBAButton = .none

    // MARK: - Input Sources
    private var touchButtons: GBAButton = .none
    private var controllerButtons: GBAButton = .none
    private let lock = NSLock()

    // MARK: - Controller Manager
    private var gameController: GCController?
    private var controllerObservers: [Any] = []

    init() {
        setupControllerObservers()
    }

    deinit {
        controllerObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Poll Input (called from emulation thread)

    func pollInput() -> UInt16 {
        lock.lock()
        let combined = touchButtons.union(controllerButtons)
        lock.unlock()
        return combined.rawValue
    }

    // MARK: - Touch Input (called from main thread)

    func setTouchButtons(_ buttons: GBAButton) {
        lock.lock()
        touchButtons = buttons
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeButtons = self.touchButtons.union(self.controllerButtons)
        }
    }

    func pressTouchButton(_ button: GBAButton) {
        lock.lock()
        touchButtons.insert(button)
        lock.unlock()
    }

    func releaseTouchButton(_ button: GBAButton) {
        lock.lock()
        touchButtons.remove(button)
        lock.unlock()
    }

    func releaseAllTouchButtons() {
        lock.lock()
        touchButtons = .none
        lock.unlock()
    }

    // MARK: - Controller Setup

    private func setupControllerObservers() {
        let connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.controllerConnected(controller)
        }

        let disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.controllerDisconnected()
        }

        controllerObservers = [connectObserver, disconnectObserver]

        // Check for already connected controllers
        if let controller = GCController.controllers().first {
            controllerConnected(controller)
        }
    }

    private func controllerConnected(_ controller: GCController) {
        gameController = controller
        isControllerConnected = true
        setupControllerHandlers(controller)
    }

    private func controllerDisconnected() {
        gameController = nil
        isControllerConnected = false
        lock.lock()
        controllerButtons = .none
        lock.unlock()
    }

    private func setupControllerHandlers(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            guard let self else { return }
            var buttons: GBAButton = .none

            // Face buttons
            if gamepad.buttonA.isPressed { buttons.insert(.a) }
            if gamepad.buttonB.isPressed { buttons.insert(.b) }
            if gamepad.buttonX.isPressed { buttons.insert(.a) } // X also maps to A
            if gamepad.buttonY.isPressed { buttons.insert(.b) } // Y also maps to B

            // Shoulders
            if gamepad.leftShoulder.isPressed { buttons.insert(.l) }
            if gamepad.rightShoulder.isPressed { buttons.insert(.r) }

            // D-pad
            if gamepad.dpad.up.isPressed { buttons.insert(.up) }
            if gamepad.dpad.down.isPressed { buttons.insert(.down) }
            if gamepad.dpad.left.isPressed { buttons.insert(.left) }
            if gamepad.dpad.right.isPressed { buttons.insert(.right) }

            // Left thumbstick as D-pad
            let deadzone: Float = 0.3
            if gamepad.leftThumbstick.xAxis.value > deadzone { buttons.insert(.right) }
            if gamepad.leftThumbstick.xAxis.value < -deadzone { buttons.insert(.left) }
            if gamepad.leftThumbstick.yAxis.value > deadzone { buttons.insert(.up) }
            if gamepad.leftThumbstick.yAxis.value < -deadzone { buttons.insert(.down) }

            // Menu buttons
            if gamepad.buttonMenu.isPressed { buttons.insert(.start) }
            if gamepad.buttonOptions?.isPressed == true { buttons.insert(.select) }

            self.lock.lock()
            self.controllerButtons = buttons
            self.lock.unlock()
        }
    }
}
