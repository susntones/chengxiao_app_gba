#ifndef EmulatorBridge_h
#define EmulatorBridge_h

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// GBA screen dimensions
#define GBA_SCREEN_WIDTH  240
#define GBA_SCREEN_HEIGHT 160

// GBA audio sample rate
#define GBA_AUDIO_SAMPLE_RATE 32768

// GBA button bitmask (matches mGBA key definitions)
typedef enum {
    GBA_KEY_A      = (1 << 0),
    GBA_KEY_B      = (1 << 1),
    GBA_KEY_SELECT = (1 << 2),
    GBA_KEY_START  = (1 << 3),
    GBA_KEY_RIGHT  = (1 << 4),
    GBA_KEY_LEFT   = (1 << 5),
    GBA_KEY_UP     = (1 << 6),
    GBA_KEY_DOWN   = (1 << 7),
    GBA_KEY_R      = (1 << 8),
    GBA_KEY_L      = (1 << 9)
} GBAKey;

// Opaque emulator handle
typedef struct EmulatorContext EmulatorContext;

// MARK: - Lifecycle

/// Create a new emulator context
EmulatorContext* emulator_create(void);

/// Destroy the emulator context and free all resources
void emulator_destroy(EmulatorContext* ctx);

// MARK: - ROM Management

/// Load a ROM file. Returns true on success.
bool emulator_load_rom(EmulatorContext* ctx, const char* romPath);

/// Load a BIOS file (optional). Returns true on success.
bool emulator_load_bios(EmulatorContext* ctx, const char* biosPath);

/// Set the save file path for battery saves
void emulator_set_save_path(EmulatorContext* ctx, const char* savePath);

/// Close the currently loaded ROM
void emulator_close_rom(EmulatorContext* ctx);

// MARK: - Emulation Control

/// Run one frame of emulation
void emulator_run_frame(EmulatorContext* ctx);

/// Reset the emulator (soft reset)
void emulator_reset(EmulatorContext* ctx);

// MARK: - Video

/// Get pointer to the video buffer (240x160 pixels, RGBA8888)
/// Buffer is valid until the next emulator_run_frame() call.
const uint32_t* emulator_get_video_buffer(EmulatorContext* ctx);

// MARK: - Audio

/// Get available audio samples count (stereo frames)
int emulator_get_audio_samples_available(EmulatorContext* ctx);

/// Read audio samples into the provided buffer.
/// Returns the number of stereo frames actually read.
/// Buffer should be at least (maxFrames * 2) int16_t elements.
int emulator_read_audio(EmulatorContext* ctx, int16_t* buffer, int maxFrames);

/// Set audio sample rate for resampling (default: 32768)
void emulator_set_audio_sample_rate(EmulatorContext* ctx, double sampleRate);

// MARK: - Input

/// Set the current button state (bitmask of GBAKey values)
void emulator_set_keys(EmulatorContext* ctx, uint16_t keyMask);

// MARK: - Save States

/// Save state to a file. Returns true on success.
bool emulator_save_state_to_file(EmulatorContext* ctx, const char* path);

/// Load state from a file. Returns true on success.
bool emulator_load_state_from_file(EmulatorContext* ctx, const char* path);

/// Get the size of a raw core state (no file-format metadata or battery save).
/// Memory state functions use this fixed-size format; file functions use SAVESTATE_ALL.
size_t emulator_get_state_size(EmulatorContext* ctx);

/// Save state to a memory buffer. Returns true on success.
bool emulator_save_state_to_buffer(EmulatorContext* ctx, void* buffer, size_t size);

/// Load state from a memory buffer. Returns true on success.
bool emulator_load_state_from_buffer(EmulatorContext* ctx, const void* buffer, size_t size);

// MARK: - Cheats

/// Add a GameShark cheat code. Returns true on success.
bool emulator_add_cheat(EmulatorContext* ctx, const char* code);

/// Remove all cheat codes
void emulator_clear_cheats(EmulatorContext* ctx);

/// Enable/disable a specific cheat by index
void emulator_set_cheat_enabled(EmulatorContext* ctx, int index, bool enabled);

// MARK: - Configuration

/// Set whether the emulator should skip BIOS intro
void emulator_set_skip_bios(EmulatorContext* ctx, bool skip);

/// Get the game title from ROM header (up to 12 chars)
const char* emulator_get_game_title(EmulatorContext* ctx);

/// Get the platform-prefixed game code (e.g. AGB-ABCD, up to 8 chars)
const char* emulator_get_game_code(EmulatorContext* ctx);

#ifdef __cplusplus
}
#endif

#endif /* EmulatorBridge_h */
