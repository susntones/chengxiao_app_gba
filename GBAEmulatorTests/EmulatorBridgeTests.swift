import Foundation
import Testing
@testable import GBAEmulator

/// Original tiny ARM program generated at test time; no commercial ROM or BIOS.
struct EmulatorBridgeTests {
    private func fixture() -> Data {
        var bytes = [UInt8](repeating: 0, count: 1024)
        func word(_ value: UInt32, at offset: Int) {
            for i in 0..<4 { bytes[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
        }
        word(0xEA00002E, at: 0) // branch to 0xC0 (past cartridge header)
        bytes.replaceSubrange(0xA0..<0xAC, with: Array("PI GBA TEST ".utf8))
        bytes.replaceSubrange(0xAC..<0xB0, with: Array("TEST".utf8))
        bytes[0xB2] = 0x96
        let program: [UInt32] = [
            0xE3A00301, // mov r0, #0x04000000 (I/O)
            0xE3A01B01, // mov r1, #0x400
            0xE3811003, // orr r1, r1, #3 (mode 3, BG2)
            0xE1C010B0, // strh r1, [r0]
            0xE3A00406, // mov r0, #0x06000000 (VRAM)
            0xE3A0101F, // mov r1, #31 (red)
            0xE1C010B0, // strh r1, [r0]
            0xE3A0040E, // mov r0, #0x0E000000 (SRAM)
            0xE3A0105A, // mov r1, #0x5A
            0xE5C01000, // strb r1, [r0]
            0xEAFFFFFE  // b .
        ]
        for (i, instruction) in program.enumerated() { word(instruction, at: 0xC0 + i * 4) }
        bytes.replaceSubrange(0x180..<0x189, with: Array("SRAM_V113".utf8))
        return Data(bytes)
    }

    @Test func framesAudioStatesAndBatterySave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rom = directory.appendingPathComponent("test.gba")
        let save = directory.appendingPathComponent("test.sav")
        let state = directory.appendingPathComponent("test.state")
        try fixture().write(to: rom)
        let ctx = try #require(emulator_create())
        defer { emulator_destroy(ctx) }
        #expect(emulator_load_rom(ctx, rom.path))
        #expect(String(cString: emulator_get_game_code(ctx)) == "AGB-TEST")
        emulator_set_save_path(ctx, save.path)
        emulator_set_audio_sample_rate(ctx, 48000)
        for _ in 0..<120 { emulator_run_frame(ctx) }
        let video = try #require(emulator_get_video_buffer(ctx))
        #expect(video[0] & 0x00FFFFFF == 0x000000FF)
        let available = emulator_get_audio_samples_available(ctx)
        #expect(available > 700 && available < 900)
        var audio = [Int16](repeating: 0, count: 8192)
        #expect(emulator_read_audio(ctx, &audio, -1) == 0)
        #expect(emulator_read_audio(ctx, &audio, 10) == 10)
        #expect(emulator_get_audio_samples_available(ctx) == available - 10)
        #expect(emulator_read_audio(ctx, &audio, 4096) == available - 10)
        #expect(emulator_get_audio_samples_available(ctx) == 0)
        #expect(emulator_save_state_to_file(ctx, state.path))
        #expect(emulator_load_state_from_file(ctx, state.path))
        let size = emulator_get_state_size(ctx)
        var raw = [UInt8](repeating: 0, count: size)
        #expect(emulator_save_state_to_buffer(ctx, &raw, size))
        #expect(!emulator_save_state_to_buffer(ctx, &raw, size - 1))
        #expect(emulator_load_state_from_buffer(ctx, &raw, size))
        emulator_close_rom(ctx)
        let savedData = try Data(contentsOf: save)
        #expect(savedData.first == 0x5A)
        // A closed context can load another ROM without stale cheat/config pointers.
        #expect(emulator_load_rom(ctx, rom.path))
        emulator_set_save_path(ctx, save.path)
        emulator_run_frame(ctx)
    }

    @Test func invalidROMDoesNotPoisonContext() throws {
        let ctx = try #require(emulator_create())
        defer { emulator_destroy(ctx) }
        #expect(!emulator_load_rom(ctx, "/nonexistent/test.gba"))
        emulator_run_frame(ctx)
        #expect(emulator_get_state_size(ctx) == 0)
        #expect(!emulator_load_state_from_file(ctx, "/nonexistent/test.state"))
    }
}
