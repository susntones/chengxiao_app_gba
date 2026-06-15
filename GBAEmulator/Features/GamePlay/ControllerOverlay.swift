import SwiftUI

/// On-screen touch controller overlay for GBA buttons
struct ControllerOverlay: View {
    @ObservedObject var inputManager: InputManager
    let settings = SettingsManager.shared

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let scale = settings.controlScale
            let opacity = settings.controlOpacity

            ZStack {
                if isLandscape {
                    landscapeLayout(size: geometry.size, scale: scale)
                } else {
                    portraitLayout(size: geometry.size, scale: scale)
                }
            }
            .opacity(opacity)
        }
    }

    // MARK: - Portrait Layout

    private func portraitLayout(size: CGSize, scale: Double) -> some View {
        VStack {
            Spacer()

            HStack {
                // D-Pad (bottom-left)
                DPadView(inputManager: inputManager)
                    .frame(width: 140 * scale, height: 140 * scale)
                    .padding(.leading, 20)

                Spacer()

                // A/B buttons (bottom-right)
                ABButtonsView(inputManager: inputManager)
                    .frame(width: 140 * scale, height: 140 * scale)
                    .padding(.trailing, 20)
            }
            .padding(.bottom, 20)

            // Start/Select + L/R
            HStack(spacing: 30) {
                ShoulderButton(label: "L", button: .l, inputManager: inputManager)
                SmallButton(label: "SELECT", button: .select, inputManager: inputManager)
                SmallButton(label: "START", button: .start, inputManager: inputManager)
                ShoulderButton(label: "R", button: .r, inputManager: inputManager)
            }
            .padding(.bottom, 30)
        }
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(size: CGSize, scale: Double) -> some View {
        HStack {
            // Left side: D-Pad + L
            VStack {
                ShoulderButton(label: "L", button: .l, inputManager: inputManager)
                    .padding(.top, 10)
                Spacer()
                DPadView(inputManager: inputManager)
                    .frame(width: 130 * scale, height: 130 * scale)
                Spacer()
                SmallButton(label: "SELECT", button: .select, inputManager: inputManager)
                    .padding(.bottom, 10)
            }
            .padding(.leading, 15)

            Spacer()

            // Right side: R + A/B + Start
            VStack {
                ShoulderButton(label: "R", button: .r, inputManager: inputManager)
                    .padding(.top, 10)
                Spacer()
                ABButtonsView(inputManager: inputManager)
                    .frame(width: 130 * scale, height: 130 * scale)
                Spacer()
                SmallButton(label: "START", button: .start, inputManager: inputManager)
                    .padding(.bottom, 10)
            }
            .padding(.trailing, 15)
        }
    }
}

// MARK: - D-Pad View

struct DPadView: View {
    let inputManager: InputManager
    @State private var activeDirection: GBAButton = .none

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let buttonSize = size / 3

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))

                // D-Pad cross shape
                VStack(spacing: 0) {
                    // Up
                    DPadButton(direction: .up, size: buttonSize, inputManager: inputManager)
                    HStack(spacing: 0) {
                        // Left
                        DPadButton(direction: .left, size: buttonSize, inputManager: inputManager)
                        // Center
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: buttonSize, height: buttonSize)
                        // Right
                        DPadButton(direction: .right, size: buttonSize, inputManager: inputManager)
                    }
                    // Down
                    DPadButton(direction: .down, size: buttonSize, inputManager: inputManager)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

struct DPadButton: View {
    let direction: GBAButton
    let size: CGFloat
    let inputManager: InputManager
    @State private var isPressed = false

    var body: some View {
        Rectangle()
            .fill(isPressed ? Color.gray.opacity(0.7) : Color.gray.opacity(0.4))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: arrowName)
                    .font(.system(size: size * 0.3))
                    .foregroundColor(.white)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            inputManager.pressTouchButton(direction)
                            HapticsService.shared.buttonPress()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        inputManager.releaseTouchButton(direction)
                    }
            )
    }

    private var arrowName: String {
        if direction == .up { return "chevron.up" }
        if direction == .down { return "chevron.down" }
        if direction == .left { return "chevron.left" }
        return "chevron.right"
    }
}

// MARK: - A/B Buttons

struct ABButtonsView: View {
    let inputManager: InputManager

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let buttonRadius = size * 0.28

            ZStack {
                // B button (left)
                ActionButton(
                    label: "B",
                    button: .b,
                    radius: buttonRadius,
                    color: .red,
                    inputManager: inputManager
                )
                .offset(x: -buttonRadius * 0.7, y: buttonRadius * 0.3)

                // A button (right)
                ActionButton(
                    label: "A",
                    button: .a,
                    radius: buttonRadius,
                    color: .blue,
                    inputManager: inputManager
                )
                .offset(x: buttonRadius * 0.7, y: -buttonRadius * 0.3)
            }
            .frame(width: size, height: size)
        }
    }
}

struct ActionButton: View {
    let label: String
    let button: GBAButton
    let radius: CGFloat
    let color: Color
    let inputManager: InputManager
    @State private var isPressed = false

    var body: some View {
        Circle()
            .fill(isPressed ? color.opacity(0.9) : color.opacity(0.6))
            .frame(width: radius * 2, height: radius * 2)
            .overlay(
                Text(label)
                    .font(.system(size: radius * 0.6, weight: .bold))
                    .foregroundColor(.white)
            )
            .shadow(color: color.opacity(0.3), radius: isPressed ? 2 : 5)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            inputManager.pressTouchButton(button)
                            HapticsService.shared.buttonPress()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        inputManager.releaseTouchButton(button)
                    }
            )
            .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Shoulder Buttons

struct ShoulderButton: View {
    let label: String
    let button: GBAButton
    let inputManager: InputManager
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isPressed ? Color.purple.opacity(0.8) : Color.purple.opacity(0.5))
            .frame(width: 55, height: 35)
            .overlay(
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            inputManager.pressTouchButton(button)
                            HapticsService.shared.buttonPress()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        inputManager.releaseTouchButton(button)
                    }
            )
    }
}

// MARK: - Small Buttons (Start/Select)

struct SmallButton: View {
    let label: String
    let button: GBAButton
    let inputManager: InputManager
    @State private var isPressed = false

    var body: some View {
        Capsule()
            .fill(isPressed ? Color.gray.opacity(0.7) : Color.gray.opacity(0.4))
            .frame(width: 60, height: 25)
            .overlay(
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            inputManager.pressTouchButton(button)
                            HapticsService.shared.buttonPress()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        inputManager.releaseTouchButton(button)
                    }
            )
    }
}
