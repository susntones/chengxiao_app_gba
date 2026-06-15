#include "EmulatorBridge.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// mGBA headers
#include <mgba/core/core.h>
#include <mgba/core/blip_buf.h>
#include <mgba/gba/core.h>
#include <mgba/core/serialize.h>
#include <mgba-util/vfs.h>
#include <mgba/internal/gba/gba.h>
#include <mgba/core/cheats.h>

// Audio buffer size (enough for several frames)
#define AUDIO_BUFFER_SIZE 4096

struct EmulatorContext {
    struct mCore* core;
    color_t* videoBuffer;
    int16_t* audioBuffer;
    int audioSamplesAvailable;
    struct mCheatDevice* cheatDevice;
    char gameTitle[13];
    char gameCode[5];
    bool romLoaded;
};

// MARK: - Lifecycle

EmulatorContext* emulator_create(void) {
    EmulatorContext* ctx = (EmulatorContext*)calloc(1, sizeof(EmulatorContext));
    if (!ctx) return NULL;

    // Allocate video buffer (240 * 160 * 4 bytes)
    ctx->videoBuffer = (color_t*)calloc(GBA_SCREEN_WIDTH * GBA_SCREEN_HEIGHT, sizeof(color_t));
    if (!ctx->videoBuffer) {
        free(ctx);
        return NULL;
    }

    // Allocate audio buffer
    ctx->audioBuffer = (int16_t*)calloc(AUDIO_BUFFER_SIZE * 2, sizeof(int16_t));
    if (!ctx->audioBuffer) {
        free(ctx->videoBuffer);
        free(ctx);
        return NULL;
    }

    ctx->romLoaded = false;
    return ctx;
}

void emulator_destroy(EmulatorContext* ctx) {
    if (!ctx) return;

    if (ctx->cheatDevice) {
        mCheatDeviceDestroy(ctx->cheatDevice);
        ctx->cheatDevice = NULL;
    }

    if (ctx->core) {
        ctx->core->deinit(ctx->core);
        ctx->core = NULL;
    }

    if (ctx->videoBuffer) {
        free(ctx->videoBuffer);
        ctx->videoBuffer = NULL;
    }

    if (ctx->audioBuffer) {
        free(ctx->audioBuffer);
        ctx->audioBuffer = NULL;
    }

    free(ctx);
}

// MARK: - ROM Management

bool emulator_load_rom(EmulatorContext* ctx, const char* romPath) {
    if (!ctx || !romPath) return false;

    // Close existing ROM if any
    if (ctx->core) {
        ctx->core->deinit(ctx->core);
        ctx->core = NULL;
    }

    // Detect platform and create core
    ctx->core = mCoreFind(romPath);
    if (!ctx->core) {
        fprintf(stderr, "Failed to find core for: %s\n", romPath);
        return false;
    }

    // Initialize core
    ctx->core->init(ctx->core);

    // Set video buffer
    ctx->core->setVideoBuffer(ctx->core, ctx->videoBuffer, GBA_SCREEN_WIDTH);

    // Set audio buffer size
    ctx->core->setAudioBufferSize(ctx->core, AUDIO_BUFFER_SIZE);

    // Load ROM
    struct VFile* rom = VFileOpen(romPath, O_RDONLY);
    if (!rom) {
        fprintf(stderr, "Failed to open ROM: %s\n", romPath);
        ctx->core->deinit(ctx->core);
        ctx->core = NULL;
        return false;
    }

    if (!ctx->core->loadROM(ctx->core, rom)) {
        fprintf(stderr, "Failed to load ROM: %s\n", romPath);
        rom->close(rom);
        ctx->core->deinit(ctx->core);
        ctx->core = NULL;
        return false;
    }

    // Reset to initialize
    ctx->core->reset(ctx->core);

    // Extract game info
    if (ctx->core->getGameTitle) {
        ctx->core->getGameTitle(ctx->core, ctx->gameTitle);
        ctx->gameTitle[12] = '\0';
    }
    if (ctx->core->getGameCode) {
        ctx->core->getGameCode(ctx->core, ctx->gameCode);
        ctx->gameCode[4] = '\0';
    }

    ctx->romLoaded = true;
    return true;
}

bool emulator_load_bios(EmulatorContext* ctx, const char* biosPath) {
    if (!ctx || !ctx->core || !biosPath) return false;

    struct VFile* bios = VFileOpen(biosPath, O_RDONLY);
    if (!bios) return false;

    ctx->core->loadBIOS(ctx->core, bios, 0);
    return true;
}

void emulator_set_save_path(EmulatorContext* ctx, const char* savePath) {
    if (!ctx || !ctx->core || !savePath) return;

    struct VFile* save = VFileOpen(savePath, O_CREAT | O_RDWR);
    if (save) {
        ctx->core->loadSave(ctx->core, save);
    }
}

void emulator_close_rom(EmulatorContext* ctx) {
    if (!ctx || !ctx->core) return;

    ctx->core->deinit(ctx->core);
    ctx->core = NULL;
    ctx->romLoaded = false;
}

// MARK: - Emulation Control

void emulator_run_frame(EmulatorContext* ctx) {
    if (!ctx || !ctx->core || !ctx->romLoaded) return;

    ctx->core->runFrame(ctx->core);

    // Collect audio samples
    struct blip_t* left = ctx->core->getAudioChannel(ctx->core, 0);
    struct blip_t* right = ctx->core->getAudioChannel(ctx->core, 1);

    int available = blip_samples_avail(left);
    if (available > AUDIO_BUFFER_SIZE) {
        available = AUDIO_BUFFER_SIZE;
    }

    // Interleave stereo samples
    blip_read_samples(left, ctx->audioBuffer, available, true);
    blip_read_samples(right, ctx->audioBuffer + 1, available, true);

    ctx->audioSamplesAvailable = available;
}

void emulator_reset(EmulatorContext* ctx) {
    if (!ctx || !ctx->core) return;
    ctx->core->reset(ctx->core);
}

// MARK: - Video

const uint32_t* emulator_get_video_buffer(EmulatorContext* ctx) {
    if (!ctx) return NULL;
    return (const uint32_t*)ctx->videoBuffer;
}

// MARK: - Audio

int emulator_get_audio_samples_available(EmulatorContext* ctx) {
    if (!ctx) return 0;
    return ctx->audioSamplesAvailable;
}

int emulator_read_audio(EmulatorContext* ctx, int16_t* buffer, int maxFrames) {
    if (!ctx || !buffer) return 0;

    int toCopy = ctx->audioSamplesAvailable;
    if (toCopy > maxFrames) toCopy = maxFrames;

    memcpy(buffer, ctx->audioBuffer, toCopy * 2 * sizeof(int16_t));
    return toCopy;
}

void emulator_set_audio_sample_rate(EmulatorContext* ctx, double sampleRate) {
    if (!ctx || !ctx->core) return;
    ctx->core->setAudioBufferSize(ctx->core, AUDIO_BUFFER_SIZE);
    // mGBA handles resampling internally via blip_buf
    // The output rate is set via blip_set_rates
    struct blip_t* left = ctx->core->getAudioChannel(ctx->core, 0);
    struct blip_t* right = ctx->core->getAudioChannel(ctx->core, 1);
    blip_set_rates(left, ctx->core->frequency(ctx->core), sampleRate);
    blip_set_rates(right, ctx->core->frequency(ctx->core), sampleRate);
}

// MARK: - Input

void emulator_set_keys(EmulatorContext* ctx, uint16_t keyMask) {
    if (!ctx || !ctx->core) return;
    ctx->core->setKeys(ctx->core, keyMask);
}

// MARK: - Save States

bool emulator_save_state_to_file(EmulatorContext* ctx, const char* path) {
    if (!ctx || !ctx->core || !path) return false;

    struct VFile* vf = VFileOpen(path, O_CREAT | O_TRUNC | O_WRONLY);
    if (!vf) return false;

    bool success = mCoreSaveStateNamed(ctx->core, vf, SAVESTATE_ALL);
    vf->close(vf);
    return success;
}

bool emulator_load_state_from_file(EmulatorContext* ctx, const char* path) {
    if (!ctx || !ctx->core || !path) return false;

    struct VFile* vf = VFileOpen(path, O_RDONLY);
    if (!vf) return false;

    bool success = mCoreLoadStateNamed(ctx->core, vf, SAVESTATE_ALL);
    vf->close(vf);
    return success;
}

size_t emulator_get_state_size(EmulatorContext* ctx) {
    if (!ctx || !ctx->core) return 0;
    return ctx->core->stateSize(ctx->core);
}

bool emulator_save_state_to_buffer(EmulatorContext* ctx, void* buffer, size_t size) {
    if (!ctx || !ctx->core || !buffer) return false;

    struct VFile* vf = VFileFromMemory(buffer, size);
    if (!vf) return false;

    bool success = mCoreSaveStateNamed(ctx->core, vf, SAVESTATE_ALL);
    vf->close(vf);
    return success;
}

bool emulator_load_state_from_buffer(EmulatorContext* ctx, const void* buffer, size_t size) {
    if (!ctx || !ctx->core || !buffer) return false;

    struct VFile* vf = VFileFromConstMemory(buffer, size);
    if (!vf) return false;

    bool success = mCoreLoadStateNamed(ctx->core, vf, SAVESTATE_ALL);
    vf->close(vf);
    return success;
}

// MARK: - Cheats

bool emulator_add_cheat(EmulatorContext* ctx, const char* code) {
    if (!ctx || !ctx->core || !code) return false;

    if (!ctx->cheatDevice) {
        ctx->cheatDevice = ctx->core->cheatDevice(ctx->core);
        if (!ctx->cheatDevice) return false;
    }

    struct mCheatSet* set = ctx->cheatDevice->createSet(ctx->cheatDevice, NULL);
    if (!set) return false;

    if (!mCheatAddLine(set, code, 0)) {
        set->deinit(set);
        return false;
    }

    mCheatAddSet(ctx->cheatDevice, set);
    set->enabled = true;
    return true;
}

void emulator_clear_cheats(EmulatorContext* ctx) {
    if (!ctx || !ctx->cheatDevice) return;
    mCheatDeviceClear(ctx->cheatDevice);
}

void emulator_set_cheat_enabled(EmulatorContext* ctx, int index, bool enabled) {
    if (!ctx || !ctx->cheatDevice) return;

    size_t count = mCheatSetsSize(&ctx->cheatDevice->cheats);
    if (index < 0 || (size_t)index >= count) return;

    struct mCheatSet* set = *mCheatSetsGetPointer(&ctx->cheatDevice->cheats, index);
    if (set) {
        set->enabled = enabled;
    }
}

// MARK: - Configuration

void emulator_set_skip_bios(EmulatorContext* ctx, bool skip) {
    if (!ctx || !ctx->core) return;

    struct mCoreOptions opts = {};
    mCoreConfigGetIntValue(&ctx->core->config, "skipBios", (int*)&opts.skipBios);
    opts.skipBios = skip;
    mCoreConfigSetIntValue(&ctx->core->config, "skipBios", skip ? 1 : 0);
}

const char* emulator_get_game_title(EmulatorContext* ctx) {
    if (!ctx) return "";
    return ctx->gameTitle;
}

const char* emulator_get_game_code(EmulatorContext* ctx) {
    if (!ctx) return "";
    return ctx->gameCode;
}
