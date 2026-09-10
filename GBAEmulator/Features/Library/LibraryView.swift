import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Main game library view
struct LibraryView: View {
    @Binding var selectedGame: Game?
    @Binding var pendingImportURL: URL?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.lastPlayed, order: .reverse) private var games: [Game]

    @State private var searchText = ""
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var viewMode: ViewMode = .grid
    @State private var importError: String?

    enum ViewMode: String {
        case grid, list
    }

    // Filtered games
    private var filteredGames: [Game] {
        if searchText.isEmpty {
            return games
        }
        return games.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // Recently played (last 5)
    private var recentGames: [Game] {
        games.filter { $0.lastPlayed != nil }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        Group {
            if games.isEmpty {
                emptyLibraryView
            } else {
                libraryContent
            }
        }
        .navigationTitle("GBA 模拟器")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button {
                        viewMode = viewMode == .grid ? .list : .grid
                    } label: {
                        Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索游戏")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "gba")!],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            StorageService.createDirectoriesIfNeeded()
            importPendingURLIfNeeded()
        }
        .onChange(of: pendingImportURL) { _, _ in importPendingURLIfNeeded() }
    }

    // MARK: - Empty State

    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("暂无游戏")
                .font(.title2)
                .fontWeight(.semibold)

            Text("导入 GBA 游戏文件即可开始")
                .font(.body)
                .foregroundColor(.secondary)

            Button {
                showingImporter = true
            } label: {
                Label("导入游戏", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Recently Played Section
                if !recentGames.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(recentGames) { game in
                                    RecentGameCell(game: game)
                                        .onTapGesture { launchGame(game) }
                                }
                            }
                            .padding(.horizontal)
                        }
                    } header: {
                        Text("最近游玩")
                            .font(.headline)
                            .padding(.horizontal)
                    }
                }

                // All Games Section
                Section {
                    if viewMode == .grid {
                        gameGrid
                    } else {
                        gameList
                    }
                } header: {
                    HStack {
                        Text("全部游戏")
                            .font(.headline)
                        Spacer()
                        Text("\(filteredGames.count) 个游戏")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Grid View

    private var gameGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(filteredGames) { game in
                GameGridCell(game: game)
                    .onTapGesture { launchGame(game) }
                    .contextMenu { gameContextMenu(for: game) }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - List View

    private var gameList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredGames) { game in
                GameListCell(game: game)
                    .onTapGesture { launchGame(game) }
                    .contextMenu { gameContextMenu(for: game) }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func gameContextMenu(for game: Game) -> some View {
        Button {
            game.isFavorite.toggle()
        } label: {
            Label(
                game.isFavorite ? "取消收藏" : "添加收藏",
                systemImage: game.isFavorite ? "star.slash" : "star"
            )
        }

        Button(role: .destructive) {
            deleteGame(game)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func launchGame(_ game: Game) {
        game.lastPlayed = Date()
        try? modelContext.save()
        selectedGame = game
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                importROM(from: url)
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importPendingURLIfNeeded() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        if let game = importROM(from: url) {
            // Wait for SwiftData to assign a permanent identity before gameplay uses
            // that identity for save-state paths.
            do {
                try modelContext.save()
                launchGame(game)
            } catch {
                modelContext.delete(game)
                importError = "无法创建游戏：\(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func importROM(from url: URL) -> Game? {
        do {
            let (fileName, fileSize) = try StorageService.importROM(from: url)
            let title = (fileName as NSString).deletingPathExtension
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            let game = Game(
                title: title,
                romFileName: fileName,
                fileSize: fileSize
            )
            modelContext.insert(game)
            return game
        } catch {
            importError = error.localizedDescription
            return nil
        }
    }

    private func deleteGame(_ game: Game) {
        StorageService.deleteGame(
            romFileName: game.romFileName,
            gameID: game.persistentModelID.hashValue.description
        )
        modelContext.delete(game)
    }
}

// MARK: - Game Grid Cell

struct GameGridCell: View {
    let game: Game

    var body: some View {
        VStack(spacing: 6) {
            // Cover art or placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let coverURL = game.coverArtURL,
                   let uiImage = UIImage(contentsOfFile: coverURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Title
            Text(game.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Game List Cell

struct GameListCell: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            // Cover art thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.purple.opacity(0.2))

                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.purple)
            }
            .frame(width: 50, height: 50)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack {
                    Text(game.formattedFileSize)
                    if game.totalPlayTime > 0 {
                        Text("•")
                        Text(game.formattedPlayTime)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if game.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recent Game Cell

struct RecentGameCell: View {
    let game: Game

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.indigo.opacity(0.3))
                    .frame(width: 90, height: 90)

                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }

            Text(game.title)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 90)
        }
    }
}
