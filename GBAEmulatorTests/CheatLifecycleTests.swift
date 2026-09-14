import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import GBAEmulator

@MainActor
struct CheatLifecycleTests {
    @Test func menuEditsPersistAcrossGameSessions() async throws {
        let container = try ModelContainer(for: Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let game = Game(title: "Cheat Test", romFileName: UUID().uuidString + ".gba", fileSize: 1024)
        container.mainContext.insert(game)
        try container.mainContext.save()
        StorageService.createDirectoriesIfNeeded()
        try EmulatorBridgeTests().fixture().write(to: game.romURL)
        let store = CheatStore(url: StorageService.cheatFilePath(for: game.romFileName))
        let autoSave = SettingsManager.shared.autoSaveEnabled
        SettingsManager.shared.autoSaveEnabled = false
        defer {
            SettingsManager.shared.autoSaveEnabled = autoSave
            StorageService.deleteGame(romFileName: game.romFileName, gameID: game.persistentModelID.hashValue.description)
        }
        let model = GamePlayViewModel(game: game)
        model.startGame()
        defer { model.stop() }
        #expect(model.errorMessage == nil)
        model.pause()
        // Exercise pause before a newly spawned worker has necessarily entered its closure.
        for _ in 0..<20 {
            model.resume()
            model.pause()
            #expect(model.isPaused)
        }
        var cheat = Cheat(name: "Green", code: "06000000:03E0", format: .raw)
        try model.updateCheats([cheat])
        #expect(model.cheats == [cheat])
        #expect(try store.load() == [cheat])
        #expect(model.isPaused)

        cheat.isEnabled = false
        cheat.name = "Edited"
        try model.updateCheats([cheat])
        model.stop()
        let reopened = GamePlayViewModel(game: game)
        reopened.startGame()
        defer { reopened.stop() }
        reopened.pause()
        #expect(reopened.cheats == [cheat])
        #expect(reopened.cheatError == nil)
        #expect(throws: CheatError.self) {
            try reopened.updateCheats([Cheat(name: "Bad", code: "INVALID")])
        }
        #expect(reopened.cheats == [cheat])
        #expect(try store.load() == [cheat])

        // An unwritable destination must roll back core changes and preserve the list.
        try FileManager.default.removeItem(at: store.url)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try reopened.updateCheats([]) }
        #expect(reopened.cheats == [cheat])
        try FileManager.default.removeItem(at: store.url)
        try reopened.updateCheats([])
        #expect(reopened.cheats.isEmpty)
        #expect(try store.load().isEmpty)
        reopened.stop()

        // Exercise actual SwiftUI construction/layout in both compact landscape and portrait.
        for size in [CGSize(width: 844, height: 390), CGSize(width: 390, height: 844)] {
            let host = UIHostingController(rootView: PauseMenuView(viewModel: model, onResume: {}, onQuit: {}))
            let list = UIHostingController(rootView: CheatListView(viewModel: model))
            for (index, controller) in [host as UIViewController, list as UIViewController].enumerated() {
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                #expect(!controller.view.subviews.isEmpty)
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("cheat-ui-\(Int(size.width))-\(index).png")
                try image.pngData()?.write(to: path)
                window.isHidden = true
            }
        }
    }
}
