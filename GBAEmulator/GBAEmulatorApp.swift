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

    var body: some View {
        NavigationStack {
            LibraryView(selectedGame: $selectedGame)
                .fullScreenCover(item: $selectedGame) { game in
                    GamePlayView(game: game)
                }
        }
    }
}
