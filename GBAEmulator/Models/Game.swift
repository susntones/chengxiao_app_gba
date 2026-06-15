import Foundation
import SwiftData

@Model
final class Game {
    var title: String
    var romFileName: String
    var fileSize: Int64
    var coverArtPath: String?
    var lastPlayed: Date?
    var totalPlayTime: TimeInterval
    var dateAdded: Date
    var isFavorite: Bool

    init(
        title: String,
        romFileName: String,
        fileSize: Int64,
        coverArtPath: String? = nil,
        lastPlayed: Date? = nil,
        totalPlayTime: TimeInterval = 0,
        dateAdded: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.title = title
        self.romFileName = romFileName
        self.fileSize = fileSize
        self.coverArtPath = coverArtPath
        self.lastPlayed = lastPlayed
        self.totalPlayTime = totalPlayTime
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
    }

    var romURL: URL {
        StorageService.romsDirectory.appendingPathComponent(romFileName)
    }

    var coverArtURL: URL? {
        guard let path = coverArtPath else { return nil }
        return StorageService.coverArtDirectory.appendingPathComponent(path)
    }

    var formattedPlayTime: String {
        let hours = Int(totalPlayTime) / 3600
        let minutes = (Int(totalPlayTime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

extension Game: Identifiable {}
