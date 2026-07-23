import Foundation

/// Moves selected scan results to Trash (never permanent delete).
actor CleanupService {
    struct MovedItem: Equatable, Identifiable, Sendable {
        var id: String { originalPath }
        let categoryID: String
        let originalPath: String
        let trashURL: URL
        let byteCount: Int64
    }

    struct Failure: Equatable, Identifiable, Sendable {
        var id: String { path }
        let path: String
        let message: String
    }

    struct Outcome: Equatable, Sendable {
        let freedBytes: Int64
        let itemCount: Int
        let moved: [MovedItem]
        let failures: [Failure]
    }

    private let fileManager: FileManager
    private let homeDirectory: String

    /// Relative home paths that must never be trashed (and anything under them).
    private let protectedPrefixes: [String] = [
        "Documents",
        "Desktop",
        "Pictures",
        "Music",
        "Movies",
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Suggestions",
        "Library/Containers/com.apple.Safari",
        "Library/Safari",
        "Library/Accounts",
        "Library/Cookies",
    ]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.homeDirectory = NSHomeDirectory()
    }

    /// Moves each scanned path to Trash. Continues on per-path errors.
    func moveToTrash(_ results: [ScanResult]) async throws -> Outcome {
        var moved: [MovedItem] = []
        var failures: [Failure] = []

        let selected = results.filter { $0.isSelected && $0.category.risk != .manual }

        for result in selected {
            for scanned in result.paths {
                try Task.checkCancellation()

                let path = scanned.path
                guard isAllowedToTrash(path) else {
                    failures.append(
                        Failure(path: path, message: "Path is protected and cannot be cleaned.")
                    )
                    continue
                }

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                    failures.append(Failure(path: path, message: "Item no longer exists."))
                    continue
                }

                let url = URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue)
                do {
                    var resulting: NSURL?
                    try fileManager.trashItem(at: url, resultingItemURL: &resulting)
                    guard let trashURL = resulting as URL? else {
                        failures.append(Failure(path: path, message: "Moved, but Trash location is unknown."))
                        continue
                    }
                    moved.append(
                        MovedItem(
                            categoryID: result.category.id,
                            originalPath: path,
                            trashURL: trashURL,
                            byteCount: scanned.byteCount
                        )
                    )
                } catch {
                    failures.append(
                        Failure(path: path, message: error.localizedDescription)
                    )
                }
            }
        }

        let freed = moved.reduce(Int64(0)) { $0 + $1.byteCount }
        return Outcome(
            freedBytes: freed,
            itemCount: moved.count,
            moved: moved,
            failures: failures
        )
    }

    /// Restores items still in Trash back to their original paths (session undo).
    func restoreFromTrash(_ items: [MovedItem]) async throws -> Outcome {
        var restored: [MovedItem] = []
        var failures: [Failure] = []

        for item in items {
            try Task.checkCancellation()

            guard fileManager.fileExists(atPath: item.trashURL.path) else {
                failures.append(
                    Failure(path: item.originalPath, message: "No longer in Trash (emptied or restored elsewhere).")
                )
                continue
            }

            let destination = URL(fileURLWithPath: item.originalPath)
            let parent = destination.deletingLastPathComponent()

            do {
                if !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                if fileManager.fileExists(atPath: destination.path) {
                    failures.append(
                        Failure(path: item.originalPath, message: "Original path already exists.")
                    )
                    continue
                }
                try fileManager.moveItem(at: item.trashURL, to: destination)
                restored.append(item)
            } catch {
                failures.append(
                    Failure(path: item.originalPath, message: error.localizedDescription)
                )
            }
        }

        let bytes = restored.reduce(Int64(0)) { $0 + $1.byteCount }
        return Outcome(
            freedBytes: bytes,
            itemCount: restored.count,
            moved: restored,
            failures: failures
        )
    }

    // MARK: - Safety

    private func isAllowedToTrash(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasPrefix(homeDirectory + "/") else { return false }
        guard standardized != homeDirectory else { return false }

        let relative = String(standardized.dropFirst(homeDirectory.count + 1))
        // Never trash the entire Library folder.
        if relative == "Library" { return false }

        for prefix in protectedPrefixes {
            if relative == prefix || relative.hasPrefix(prefix + "/") {
                return false
            }
        }
        return true
    }
}
