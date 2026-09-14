import Foundation
import Testing
@testable import GBAEmulator

struct CheatTests {
    @Test func validationNormalizesMultilineCodes() throws {
        let cheat = try Cheat(name: "  无限生命  ", code: " 02000000:ff\r\n\n 02000001:01 \n", format: .raw).validated()
        #expect(cheat.name == "无限生命")
        #expect(cheat.code == "02000000:FF\n02000001:01")
        for code in ["", " \n ", "INVALID", "02000000:01\0junk", "02000000:012", "02000000:0123456789"] {
            #expect(throws: CheatError.self) { try Cheat(name: "Test", code: code).validated() }
        }
        #expect(throws: CheatError.self) { try Cheat(name: " ", code: "02000000:01").validated() }
    }

    @Test func explicitFormatsValidateLineWidths() throws {
        for (format, code) in [(Cheat.Format.codeBreaker, "82000000 0001"), (.gameShark, "01234567 89ABCDEF"), (.actionReplay, "0123456789ABCDEF"), (.raw, "02000000:01")] {
            #expect(try Cheat(name: "Test", code: code, format: format).validated().code == code)
        }
        #expect(throws: CheatError.self) {
            try Cheat(name: "Test", code: "01234567 89ABCDEF", format: .codeBreaker).validated()
        }
    }

    @Test func persistenceCRUDAndGameIsolation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = CheatStore(url: root.appendingPathComponent("a.gba.json"))
        let second = CheatStore(url: root.appendingPathComponent("b.gba.json"))
        #expect(try first.load().isEmpty)
        var entries = [Cheat(name: "Test", code: "02000000:01", format: .raw)]
        try first.save(entries)
        #expect(try first.load() == entries)
        #expect(try second.load().isEmpty)
        entries[0].isEnabled = false
        entries[0].name = "Edited"
        entries[0].code = "02000000:02"
        try first.save(entries)
        #expect(try first.load() == entries)
        try first.save([])
        #expect(try first.load().isEmpty)
        try Data("broken".utf8).write(to: first.url)
        #expect(throws: (any Error).self) { try first.load() }
        #expect(StorageService.cheatFilePath(for: "a.gba") != StorageService.cheatFilePath(for: "b.gba"))
    }
}
