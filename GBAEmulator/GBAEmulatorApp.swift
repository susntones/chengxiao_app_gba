import SwiftUI
import SwiftData

@main
struct GBAEmulatorApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Game.self)
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}

struct ContentView: View {
    @State private var selectedGame: Game?
    @State private var pendingImportURL: URL?

    var body: some View {
        NavigationStack {
            LibraryView(selectedGame: $selectedGame, pendingImportURL: $pendingImportURL)
                .fullScreenCover(item: $selectedGame) { game in
                    GamePlayView(game: game)
                }
        }
        .onOpenURL { url in
            guard StorageService.isSupported(url: url) else { return }
            pendingImportURL = url
        }
    }
}
