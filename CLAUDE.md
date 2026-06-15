# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Native iOS Game Boy Advance emulator built with SwiftUI on top of the mGBA core. The Swift app shell wraps a C/C++ emulation core via a hand-written C bridge, drives a Metal rendering pipeline at 60 FPS, and feeds audio through an AVAudioEngine ring-buffer pipeline.

## Project Generation & Build

The Xcode project is generated from `project.yml` via XcodeGen — never edit `GBAEmulator.xcodeproj/project.pbxproj` by hand; regenerate instead.

```bash
# Install build tools
brew install cmake xcodegen

# Regenerate Xcode project after editing project.yml or adding/removing files
xcodegen generate

# Build mGBA static library (one-time, also auto-runs as preBuildScript when libmgba.a is missing)
./GBAEmulator/mGBA/build-ios.sh

# Open in Xcode
open GBAEmulator.xcodeproj
```

`build-ios.sh` clones mGBA v0.10.3 into `GBAEmulator/mGBA/mgba-src/`, cross-compiles for iOS arm64 with most subsystems off (Qt/SDL/GL/PNG/FFmpeg disabled), and installs `libmgba.a` + headers into `GBAEmulator/mGBA/{lib,include}`.

## Tests

Tests use the Swift Testing framework (`import Testing`, `@Test`, `#expect`) — not XCTest.

```bash
# Run all unit tests (requires a real device or Metal-capable simulator scheme)
xcodebuild test -project GBAEmulator.xcodeproj -scheme GBAEmulator \
    -destination 'platform=iOS,name=<your-device>'

# Run a single test
xcodebuild test -project GBAEmulator.xcodeproj -scheme GBAEmulator \
    -destination 'platform=iOS,name=<your-device>' \
    -only-testing:GBAEmulatorTests/RingBufferTests/writeAndRead
```

Note: the emulator itself requires Metal and **must run on a physical device**, but logic-only unit tests (e.g., `RingBufferTests`) run fine in the simulator.

## Architecture — The Big Picture

The hot path is **Swift → C bridge → mGBA core → Metal/Audio**, with three threads cooperating:

1. **Main (UI) thread** — SwiftUI views, settings, lifecycle.
2. **Emulation thread** (`com.gbaemulator.emulation`, `.userInteractive` QoS) — owned by `EmulatorCore`. Runs `emulator_run_frame()` in a tight loop, polls input, pushes frames to `VideoRenderer`, pushes audio samples to `AudioEngine`'s ring buffer, then sleeps to maintain 59.7275 Hz (GBA native).
3. **Audio render thread** (CoreAudio-owned, inside `AVAudioSourceNode` callback) — pulls Int16 stereo samples from `RingBuffer`, fills silence on underrun.

### C ↔ Swift Bridge

- `GBAEmulator/Core/Emulator/EmulatorBridge.{h,c}` — opaque `EmulatorContext*` C API around mGBA. Hides all mGBA types from Swift.
- `GBAEmulator-Bridging-Header.h` — exposed via `SWIFT_OBJC_BRIDGING_HEADER` in `project.yml`.
- mGBA writes RGBA8888 directly into a context-owned 240×160 video buffer. The pointer returned by `emulator_get_video_buffer()` is invalidated on the next `emulator_run_frame()` call — `VideoRenderer.updateFrame` must `memcpy` into its own owned buffer before unlocking.
- mGBA audio uses `blip_buf` channels at 32768 Hz; the bridge resamples to the device sample rate via `blip_set_rates` (called once in `emulator_set_audio_sample_rate`).
- Save states use `mCoreSaveStateNamed` / `mCoreLoadStateNamed` with `SAVESTATE_ALL` flags; both file and in-memory variants are exposed.

### Thread-Safety Model

- `EmulatorCore` is `@MainActor` for published state, but the emulation thread accesses two atomics (`AtomicBool isRunning`, `AtomicDouble speed`) wrapped with `os_unfair_lock` — these are the **only** Swift state read from the emulation thread.
- `InputManager` merges touch + controller buttons under an `NSLock`; `pollInput()` is called from the emulation thread.
- `RingBuffer` (audio) is SPSC under `NSLock` — writer is the emulation thread, reader is the CoreAudio callback. Capacity is in *stereo frames* (interleaved Int16 pairs).
- `VideoRenderer.updateFrame` copies the entire 240×160 buffer (~150 KB) under `bufferLock` to decouple emulation from MTKView's draw cadence.
- Stop sequence is critical: `atomicIsRunning.value = false` → `Thread.cancel()` → `threadExitSemaphore.wait` → only **then** `emulator_destroy(ctx)`. Skipping the wait will free the context while the emulation thread still touches it.

### Rendering

- `VideoRenderer` owns the Metal device, pipeline state, sampler, and texture. Uploads via `texture.replace(...)` from `MTKViewDelegate.draw(in:)`.
- Aspect-ratio + scaling mode (fit / fill / integer) are passed to the vertex shader (`Shaders.metal`) per draw via `setVertexBytes` — there is no CPU-side resize logic.
- `MetalView` is a thin `UIViewRepresentable` wrapping `MTKView`; the renderer is owned by `GamePlayViewModel` and survives view rebuilds.

### Persistence

- `Game` is a `@Model` (SwiftData). `ContentView` injects `ModelContainer(for: Game.self)` once at app launch.
- File layout under `Documents/`: `ROMs/`, `Saves/` (battery `.sav`), `States/<gameID>/slot{0..9}.{state,png,json}` + `auto.{state,png}`, `CoverArt/`. All paths are funneled through `StorageService` — never construct paths directly.
- `gameID` is `game.persistentModelID.hashValue.description`. Don't change this without a migration; it's used as the directory name for save states.
- Settings live in `UserDefaults` via the `@Observable` `SettingsManager.shared`.

### Lifecycle hooks worth knowing

- `GamePlayView.onChange(of: scenePhase)`:
  - `.background` → `autoSaveAndPause()` (writes `auto.state` if auto-save is enabled).
  - `.inactive` → `pause()`.
  - `.active` → **does not auto-resume** — user must tap resume.
- `EmulatorCore.pause()` waits up to 100 ms for the emulation thread to exit before returning.
- `setFastForward` adjusts `atomicSpeed`; `AudioEngine.setFastForwardMode(true)` mutes audio to avoid chipmunk effect.

## Conventions Specific to This Repo

- **Adding source files**: drop them in the appropriate `GBAEmulator/{Core,Features,Models,Services}/...` folder, then run `xcodegen generate`. The XcodeGen target uses `path: GBAEmulator` with a glob, so any new `.swift`/`.c`/`.metal` file under that tree is picked up automatically.
- **Excluded from compilation**: `GBAEmulator/mGBA/src/**` is excluded in `project.yml` (the mgba-src clone lives there). Only the prebuilt `libmgba.a` and the headers under `mGBA/include/` are linked.
- **mGBA headers**: `HEADER_SEARCH_PATHS` is `$(PROJECT_DIR)/GBAEmulator/mGBA/include`. Include them as `#include <mgba/...>`, not relative paths.
- **Metal**: requires a real device. Avoid forcing simulator builds for runtime testing — `VideoRenderer.init?` returns nil when `MTLCreateSystemDefaultDevice()` fails, and `GamePlayViewModel` will `fatalError` on that.
- **Bundle IDs** are set per target in `project.yml` (`com.gbaemulator.app` / `.tests` / `.uitests`).
- **Don't commit** ROM files (`.gba`/`.gbc`/`.gb`/`.sav`/`.state`) — `.gitignore` already blocks them.

## Commit Message Style

The user's global instructions specify Conventional-Commit style: `type(scope): 中文描述` with types from `feat|fix|refactor|docs|test|chore|perf|ci`. Description in Chinese, ≤72 chars; body explains *why*.

## Things to Watch Out For

- The `EmulatorContext*` round-trip uses `OpaquePointer` ↔ `UnsafeMutableRawPointer.assumingMemoryBound(to: EmulatorContext.self)`. Don't try to import `EmulatorContext` as a Swift type — the C struct is intentionally opaque in the header.
- `RingBuffer.write` reserves 1 slot (`capacity - 1`) to distinguish full vs. empty — see the `bufferOverflow` test (writes 100 into a 64-cap buffer → returns 63).
- `audioBuffer` in the C bridge is `AUDIO_BUFFER_SIZE * 2` Int16s (stereo interleaved). `audioSamplesAvailable` counts **stereo frames**, not individual samples.
- mGBA's `runFrame` produces a variable number of audio samples per frame; the loop must drain them every frame or `blip_buf` will overflow silently.
- Setting fast-forward via `atomicSpeed` only changes the emulation-loop sleep — mGBA still runs at native speed; the loop just runs more frames per wall-clock second.
