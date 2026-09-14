#include "EmulatorBridge.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

// Match the prebuilt core's feature-dependent struct layout (notably USE_DEBUGGERS).
#include <mgba/flags.h>
// mGBA headers
#include <mgba/core/core.h>
#include <mgba/core/log.h>
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
    char gameCode[9];
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

    emulator_close_rom(ctx);

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

    emulator_close_rom(ctx);

    // Detect platform and create core
    ctx->core = mCoreFind(romPath);
    if (!ctx->core) {
        fprintf(stderr, "Failed to find core for: %s\n", romPath);
        return false;
    }

    // Initialize core
    if (!ctx->core->init(ctx->core)) {
        // The mGBA init contract leaves the allocated core owned by the caller.
        free(ctx->core);
        ctx->core = NULL;
        return false;
    }
    mCoreInitConfig(ctx->core, "GBAEmulator");
    // Avoid synchronous stderr logging in release gameplay. ROM hacks may perform
    // unusual accesses every frame; formatting those diagnostics can otherwise
    // consume enough CPU to prevent high fast-forward multipliers.
    mCoreConfigSetIntValue(&ctx->core->config, "logLevel", mLOG_FATAL | mLOG_ERROR);
    ctx->core->opts.skipBios = true;

    // Set video buffer
    ctx->core->setVideoBuffer(ctx->core, ctx->videoBuffer, GBA_SCREEN_WIDTH);

    // Set audio buffer size
    ctx->core->setAudioBufferSize(ctx->core, AUDIO_BUFFER_SIZE);

    // Load ROM
    struct VFile* rom = VFileOpen(romPath, O_RDONLY);
    if (!rom) {
        fprintf(stderr, "Failed to open ROM: %s\n", romPath);
        emulator_close_rom(ctx);
        return false;
    }

    if (!ctx->core->loadROM(ctx->core, rom)) {
        fprintf(stderr, "Failed to load ROM: %s\n", romPath);
        rom->close(rom);
        emulator_close_rom(ctx);
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
        ctx->gameCode[8] = '\0';
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

    mCoreConfigDeinit(&ctx->core->config);
    ctx->core->deinit(ctx->core);
    ctx->core = NULL;
    ctx->cheatDevice = NULL; // borrowed; destroyed by core->deinit
    ctx->romLoaded = false;
    ctx->audioSamplesAvailable = 0;
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
    if (!ctx || !buffer || maxFrames <= 0) return 0;

    int toCopy = ctx->audioSamplesAvailable;
    if (toCopy > maxFrames) toCopy = maxFrames;

    memcpy(buffer, ctx->audioBuffer, toCopy * 2 * sizeof(int16_t));
    ctx->audioSamplesAvailable -= toCopy;
    memmove(ctx->audioBuffer, ctx->audioBuffer + toCopy * 2,
            ctx->audioSamplesAvailable * 2 * sizeof(int16_t));
    return toCopy;
}

void emulator_set_audio_sample_rate(EmulatorContext* ctx, double sampleRate) {
    if (!ctx || !ctx->core || !isfinite(sampleRate) || sampleRate <= 0) return;
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

    struct VFile* vf = VFileOpen(path, O_CREAT | O_TRUNC | O_RDWR);
    if (!vf) return false;

    // The per-game Cheat List is authoritative, not a historical save-state list.
    bool success = mCoreSaveStateNamed(ctx->core, vf, SAVESTATE_ALL & ~SAVESTATE_CHEATS);
    vf->close(vf);
    return success;
}

bool emulator_load_state_from_file(EmulatorContext* ctx, const char* path) {
    if (!ctx || !ctx->core || !path) return false;

    struct VFile* vf = VFileOpen(path, O_RDONLY);
    if (!vf) return false;

    bool success = mCoreLoadStateNamed(ctx->core, vf, SAVESTATE_ALL & ~SAVESTATE_CHEATS);
    vf->close(vf);
    return success;
}

size_t emulator_get_state_size(EmulatorContext* ctx) {
    if (!ctx || !ctx->core) return 0;
    return ctx->core->stateSize(ctx->core);
}

bool emulator_save_state_to_buffer(EmulatorContext* ctx, void* buffer, size_t size) {
    if (!ctx || !ctx->core || !buffer || size < ctx->core->stateSize(ctx->core)) return false;
    return ctx->core->saveState(ctx->core, buffer);
}

bool emulator_load_state_from_buffer(EmulatorContext* ctx, const void* buffer, size_t size) {
    if (!ctx || !ctx->core || !buffer || size < ctx->core->stateSize(ctx->core)) return false;
    return ctx->core->loadState(ctx->core, buffer);
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
        mCheatSetDeinit(set);
        return false;
    }

    mCheatAddSet(ctx->cheatDevice, set);
    set->enabled = true;
    return true;
}

void emulator_clear_cheats(EmulatorContext* ctx) {
    if (!ctx || !ctx->cheatDevice) return;
    while (mCheatSetsSize(&ctx->cheatDevice->cheats)) {
        struct mCheatSet* set = *mCheatSetsGetPointer(&ctx->cheatDevice->cheats, 0);
        set->enabled = false;
        mCheatRefresh(ctx->cheatDevice, set); // Restore ROM patches before freeing.
        mCheatRemoveSet(ctx->cheatDevice, set); // Remove master-code hooks.
        mCheatSetDeinit(set);
    }
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

bool emulator_replace_cheats(EmulatorContext* ctx, const EmulatorCheat* cheats, size_t count) {
    if (!ctx || !ctx->core || !ctx->romLoaded || (count && !cheats)) return false;
    if (!ctx->cheatDevice) ctx->cheatDevice = ctx->core->cheatDevice(ctx->core);
    if (!ctx->cheatDevice) return false;
    struct mCheatSet** sets = calloc(count ? count : 1, sizeof(*sets));
    if (!sets) return false;
    bool valid = true;
    for (size_t i = 0; i < count && valid; ++i) {
        if (!cheats[i].code || cheats[i].type < 0 || cheats[i].type > 4) { valid = false; break; }
        sets[i] = ctx->cheatDevice->createSet(ctx->cheatDevice, NULL);
        char* text = strdup(cheats[i].code);
        if (!sets[i] || !text) { free(text); valid = false; break; }
        size_t lines = 0;
        char* state = NULL;
        for (char* line = strtok_r(text, "\r\n", &state); line; line = strtok_r(NULL, "\r\n", &state)) {
            while (*line == ' ' || *line == '\t') ++line;
            size_t length = strlen(line);
            while (length && (line[length - 1] == ' ' || line[length - 1] == '\t')) line[--length] = 0;
            if (!length) continue;
            if (!mCheatAddLine(sets[i], line, cheats[i].type)) { valid = false; break; }
            ++lines;
        }
        free(text);
        if (!lines) valid = false;
        sets[i]->enabled = cheats[i].enabled;
    }
    if (valid) {
        emulator_clear_cheats(ctx);
        for (size_t i = 0; i < count; ++i) mCheatAddSet(ctx->cheatDevice, sets[i]);
    } else {
        for (size_t i = 0; i < count; ++i) if (sets[i]) mCheatSetDeinit(sets[i]);
    }
    free(sets);
    return valid;
}

// MARK: - Configuration

void emulator_set_skip_bios(EmulatorContext* ctx, bool skip) {
    if (!ctx || !ctx->core) return;

    ctx->core->opts.skipBios = skip;
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
