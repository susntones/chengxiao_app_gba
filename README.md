# GBA Emulator for iOS

A native iOS Game Boy Advance emulator built with **SwiftUI** and **mGBA** core, inspired by [Delta Emulator](https://faq.deltaemulator.com/).

## Features

- **Accurate GBA Emulation** — Powered by mGBA, one of the most accurate GBA emulators
- **Modern iOS UI** — SwiftUI-based interface with grid/list library view
- **Save States** — 10 manual save slots + auto-save with thumbnails
- **On-Screen Controls** — D-pad, A/B/L/R/Start/Select with haptic feedback
- **External Controllers** — MFi, PS4/PS5, Xbox controller support
- **Fast Forward** — 2x/4x/8x speed with one-tap toggle
- **Metal Rendering** — 60fps GPU-accelerated display with scaling filters
- **Low-Latency Audio** — AVAudioEngine with ring buffer audio pipeline

## Requirements

- **iOS 16.0+**
- **Xcode 15.0+**
- **Swift 5.9+**
- CMake 3.20+ (for mGBA compilation)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Quick Start

### 1. Install Dependencies

```bash
brew install cmake xcodegen
```

### 2. Generate Xcode Project

```bash
git clone <this-repo>
cd gba
xcodegen generate
```

### 3. Build mGBA

```bash
chmod +x GBAEmulator/mGBA/build-ios.sh
./GBAEmulator/mGBA/build-ios.sh
```

This will:
- Clone mGBA v0.10.3 source
- Cross-compile for iOS arm64
- Place `libmgba.a` in `GBAEmulator/mGBA/lib/`
- Copy headers to `GBAEmulator/mGBA/include/`

### 4. Open in Xcode

```bash
open GBAEmulator.xcodeproj
```

Select your development team, then build and run on device.

> **Note**: The emulator requires Metal, so it must run on a physical device (not Simulator).

## Usage

1. **Import ROMs**: Tap `+` in the library to import `.gba` files from the Files app
2. **Play**: Tap a game to start playing
3. **Pause**: Tap the pause button (top-right) for save states, fast forward, etc.
4. **Save/Load**: Use the pause menu to manage save states
5. **Fast Forward**: Tap the speed button (top-left) or use pause menu

## Project Structure

```
GBAEmulator/
├── GBAEmulatorApp.swift          # App entry point
├── Core/
│   ├── Emulator/
│   │   ├── EmulatorBridge.h/c    # C bridge to mGBA
│   │   ├── EmulatorCore.swift    # Swift emulator wrapper
│   │   ├── VideoRenderer.swift   # Metal rendering pipeline
│   │   ├── AudioEngine.swift     # AVAudioEngine audio output
│   │   ├── RingBuffer.swift      # Lock-free audio ring buffer
│   │   ├── Shaders.metal         # Vertex/fragment shaders
│   │   └── MetalView.swift       # SwiftUI Metal view
│   ├── Input/
│   │   └── InputManager.swift    # Unified touch + controller input
│   └── SaveState/
│       └── SaveStateManager.swift
├── Features/
│   ├── Library/
│   │   └── LibraryView.swift     # Game library grid/list
│   ├── GamePlay/
│   │   ├── GamePlayView.swift    # Main gameplay screen
│   │   ├── PauseMenuView.swift   # Pause overlay
│   │   └── ControllerOverlay.swift # Touch controls
│   └── Settings/
│       └── SettingsView.swift
├── Models/
│   ├── Game.swift                # SwiftData model
│   └── AppSettings.swift         # Settings definitions
├── Services/
│   ├── StorageService.swift      # File management
│   └── HapticsService.swift      # Haptic feedback
└── mGBA/
    ├── build-ios.sh              # mGBA compilation script
    ├── lib/                      # Compiled static library
    └── include/                  # mGBA headers
```

## Architecture

- **MVVM** pattern with SwiftUI
- **Metal** for GPU-accelerated frame rendering
- **AVAudioEngine** with SPSC ring buffer for low-latency audio
- **SwiftData** for game metadata persistence
- **GCController** framework for external controller support
- Dedicated emulation thread with CADisplayLink sync

## Legal

- This app does **not** include any game ROMs or proprietary BIOS files
- Users must provide their own legally obtained ROM files
- mGBA is licensed under [MPL 2.0](https://www.mozilla.org/en-US/MPL/2.0/)
- Game Boy Advance is a trademark of Nintendo Co., Ltd.

## Credits

- [mGBA](https://mgba.io/) by Jeffrey Pfau — Emulation core
- Inspired by [Delta Emulator](https://faq.deltaemulator.com/) by Riley Testut

## License

MIT License (app shell) + MPL 2.0 (mGBA core)
