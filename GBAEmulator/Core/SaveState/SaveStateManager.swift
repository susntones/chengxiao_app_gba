import Foundation

/// Manages save and load operations for emulator states
final class SaveStateManager {
    let maxSlots = 10

    /// List all save states for a game
    func listStates(for gameID: String) -> [SaveStateSlot] {
        var slots: [SaveStateSlot] = []

        for i in 0..<maxSlots {
            let statePath = StorageService.stateFilePath(for: gameID, slot: i)
            let metadataPath = StorageService.stateMetadataPath(for: gameID, slot: i)
            let thumbnailPath = StorageService.stateThumbnailPath(for: gameID, slot: i)

            if FileManager.default.fileExists(atPath: statePath.path) {
                var metadata: SaveStateMetadata?
                if let data = try? Data(contentsOf: metadataPath) {
                    metadata = try? JSONDecoder().decode(SaveStateMetadata.self, from: data)
                }

                slots.append(SaveStateSlot(
                    slot: i,
                    isEmpty: false,
                    date: metadata?.date ?? fileModificationDate(at: statePath),
                    thumbnailPath: thumbnailPath.path,
                    isLocked: metadata?.isLocked ?? false,
                    isAutoSave: metadata?.isAutoSave ?? false
                ))
            } else {
                slots.append(SaveStateSlot(slot: i, isEmpty: true))
            }
        }

        return slots
    }

    /// Delete a save state
    func deleteState(for gameID: String, slot: Int) {
        let statePath = StorageService.stateFilePath(for: gameID, slot: slot)
        let metadataPath = StorageService.stateMetadataPath(for: gameID, slot: slot)
        let thumbnailPath = StorageService.stateThumbnailPath(for: gameID, slot: slot)

        try? FileManager.default.removeItem(at: statePath)
        try? FileManager.default.removeItem(at: metadataPath)
        try? FileManager.default.removeItem(at: thumbnailPath)
    }

    /// Toggle lock on a save state
    func toggleLock(for gameID: String, slot: Int) {
        let metadataPath = StorageService.stateMetadataPath(for: gameID, slot: slot)

        guard let data = try? Data(contentsOf: metadataPath),
              var metadata = try? JSONDecoder().decode(SaveStateMetadata.self, from: data) else {
            return
        }

        let updatedMetadata = SaveStateMetadata(
            slot: metadata.slot,
            date: metadata.date,
            isLocked: !metadata.isLocked,
            isAutoSave: metadata.isAutoSave
        )

        if let encoded = try? JSONEncoder().encode(updatedMetadata) {
            try? encoded.write(to: metadataPath)
        }
    }

    // MARK: - Helpers

    private func fileModificationDate(at url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}

// MARK: - Save State Slot Model

struct SaveStateSlot: Identifiable {
    let slot: Int
    let isEmpty: Bool
    var date: Date?
    var thumbnailPath: String?
    var isLocked: Bool = false
    var isAutoSave: Bool = false

    var id: Int { slot }

    var displayName: String {
        if isAutoSave { return "Auto Save" }
        return "Slot \(slot)"
    }
}
