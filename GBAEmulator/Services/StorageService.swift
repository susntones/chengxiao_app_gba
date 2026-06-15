import Foundation

/// Manages file system paths and directory creation for the app
enum StorageService {
    // MARK: - Base Directories

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var romsDirectory: URL {
        documentsDirectory.appendingPathComponent("ROMs", isDirectory: true)
    }

    static var savesDirectory: URL {
        documentsDirectory.appendingPathComponent("Saves", isDirectory: true)
    }

    static var statesDirectory: URL {
        documentsDirectory.appendingPathComponent("States", isDirectory: true)
    }

    static var coverArtDirectory: URL {
        documentsDirectory.appendingPathComponent("CoverArt", isDirectory: true)
    }

    // MARK: - Game-Specific Paths

    static func saveFilePath(for romFileName: String) -> URL {
        let baseName = (romFileName as NSString).deletingPathExtension
        return savesDirectory.appendingPathComponent("\(baseName).sav")
    }

    static func statesDirectory(for gameID: String) -> URL {
        statesDirectory.appendingPathComponent(gameID, isDirectory: true)
    }

    static func stateFilePath(for gameID: String, slot: Int) -> URL {
        statesDirectory(for: gameID).appendingPathComponent("slot\(slot).state")
    }

    static func stateThumbnailPath(for gameID: String, slot: Int) -> URL {
        statesDirectory(for: gameID).appendingPathComponent("slot\(slot).png")
    }

    static func stateMetadataPath(for gameID: String, slot: Int) -> URL {
        statesDirectory(for: gameID).appendingPathComponent("slot\(slot).json")
    }

    static func autoSaveStatePath(for gameID: String) -> URL {
        statesDirectory(for: gameID).appendingPathComponent("auto.state")
    }

    static func autoSaveThumbnailPath(for gameID: String) -> URL {
        statesDirectory(for: gameID).appendingPathComponent("auto.png")
    }

    // MARK: - Directory Setup

    static func createDirectoriesIfNeeded() {
        let directories = [
            romsDirectory,
            savesDirectory,
            statesDirectory,
            coverArtDirectory
        ]

        let fileManager = FileManager.default
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    static func createStatesDirectory(for gameID: String) {
        let directory = statesDirectory(for: gameID)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - File Operations

    static func importROM(from sourceURL: URL) throws -> (fileName: String, fileSize: Int64) {
        createDirectoriesIfNeeded()

        let fileName = sourceURL.lastPathComponent
        let destinationURL = romsDirectory.appendingPathComponent(fileName)

        // Handle duplicate names
        var finalURL = destinationURL
        var counter = 1
        while FileManager.default.fileExists(atPath: finalURL.path) {
            let baseName = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            finalURL = romsDirectory.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            counter += 1
        }

        // Copy file (security-scoped access for Files app imports)
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        try FileManager.default.copyItem(at: sourceURL, to: finalURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        return (finalURL.lastPathComponent, fileSize)
    }

    static func deleteGame(romFileName: String, gameID: String) {
        let fileManager = FileManager.default

        // Delete ROM
        let romURL = romsDirectory.appendingPathComponent(romFileName)
        try? fileManager.removeItem(at: romURL)

        // Delete save file
        let saveURL = saveFilePath(for: romFileName)
        try? fileManager.removeItem(at: saveURL)

        // Delete states directory
        let statesDir = statesDirectory(for: gameID)
        try? fileManager.removeItem(at: statesDir)
    }

    // MARK: - Supported Extensions

    static let supportedExtensions: Set<String> = ["gba", "gbc", "gb", "zip"]

    static func isSupported(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
