import Foundation

/// Blocks cleanup that would remove the running MacSweeper.app (e.g. Xcode DerivedData).
enum RunningAppSafety {
    static var bundlePath: String {
        (Bundle.main.bundlePath as NSString).standardizingPath
    }

    /// True if removing `path` would delete or corrupt the running app bundle.
    static func isProtected(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let bundle = bundlePath
        if standardized == bundle { return true }
        // Ancestor of the running app (e.g. DerivedData while debugging from Xcode).
        if bundle.hasPrefix(standardized + "/") { return true }
        // File/folder inside the running app bundle.
        if standardized.hasPrefix(bundle + "/") { return true }
        return false
    }
}

/// Moves selected scan results to Trash (never permanent delete, except Empty Trash
/// and items explicitly removed when `deleteImmediately` is requested).
actor CleanupService {
    struct MovedItem: Equatable, Identifiable, Sendable {
        var id: String { originalPath }
        let categoryID: String
        let categoryLabel: String?
        let originalPath: String
        let trashURL: URL
        let byteCount: Int64

        init(
            categoryID: String,
            categoryLabel: String? = nil,
            originalPath: String,
            trashURL: URL,
            byteCount: Int64
        ) {
            self.categoryID = categoryID
            self.categoryLabel = categoryLabel
            self.originalPath = originalPath
            self.trashURL = trashURL
            self.byteCount = byteCount
        }
    }

    struct Failure: Equatable, Identifiable, Sendable {
        var id: String { path }
        let path: String
        let message: String
    }

    /// Category-level progress while moving items to Trash.
    struct Progress: Equatable, Sendable {
        let label: String
        let current: Int
        let total: Int
    }

    struct Outcome: Equatable, Sendable {
        let freedBytes: Int64
        let itemCount: Int
        let moved: [MovedItem]
        let failures: [Failure]
        /// True when Trash contents were permanently deleted (no undo).
        let emptiedTrash: Bool
        /// True when just-cleaned items were permanently removed from Trash.
        var permanentlyDeleted: Bool = false

        static let empty = Outcome(
            freedBytes: 0,
            itemCount: 0,
            moved: [],
            failures: [],            emptiedTrash: false
        )
    }

    private let fileManager: FileManager
    private let homeDirectory: String

    init(fileManager: FileManager = .default, homeDirectory: String = NSHomeDirectory()) {
        self.fileManager = fileManager
        self.homeDirectory = (homeDirectory as NSString).standardizingPath
    }

    /// Moves paths to Trash and/or permanently empties Trash when selected.
    /// When `deleteImmediately` is true, just-cleaned items are permanently removed
    /// from Trash right after the move so space is freed immediately (no undo).
    /// - Parameter onProgress: Invoked on the cooperative task before each category starts.
    func moveToTrash(
        _ results: [ScanResult],
        deleteImmediately: Bool = false,
        onProgress: (@Sendable (Progress) async -> Void)? = nil
    ) async throws -> Outcome {
        var moved: [MovedItem] = []
        var failures: [Failure] = []
        var emptiedTrash = false
        var emptiedBytes: Int64 = 0
        var emptiedCount = 0

        let selected = results.compactMap { $0.selectingOnlyCheckedPaths() }
        let total = selected.count

        for (offset, result) in selected.enumerated() {
            try Task.checkCancellation()

            let progress = Progress(
                label: result.category.label,
                current: offset + 1,
                total: max(total, 1)
            )
            if let onProgress {
                await onProgress(progress)
            }

            if result.category.action == .emptyTrash {
                let emptyOutcome = try emptyTrashContents(byteHint: result.totalBytes)
                if emptyOutcome.emptiedTrash {
                    emptiedTrash = true
                }
                emptiedBytes += emptyOutcome.freedBytes
                emptiedCount += emptyOutcome.itemCount
                failures.append(contentsOf: emptyOutcome.failures)
                continue
            }

            for scanned in result.paths where scanned.isSelected {
                try Task.checkCancellation()

                let path = scanned.path
                if RunningAppSafety.isProtected(path) {
                    failures.append(
                        Failure(
                            path: path,
                            message: "Skipped — MacSweeper is running from this location. Quit the app or clean other DerivedData folders only."
                        )
                    )
                    continue
                }
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
                            categoryLabel: result.category.label,
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

        if deleteImmediately {
            permanentlyRemoveMoved(moved, failures: &failures)
        }

        let movedBytes = moved.reduce(Int64(0)) { $0 + $1.byteCount }
        return Outcome(
            freedBytes: movedBytes + emptiedBytes,
            itemCount: moved.count + emptiedCount,
            moved: moved,
            failures: failures,
            emptiedTrash: emptiedTrash,
            permanentlyDeleted: deleteImmediately && !moved.isEmpty
        )
    }

    /// Permanently removes just-cleaned items from Trash so their space is freed
    /// immediately. Items whose removal fails stay in Trash and remain restorable.
    private func permanentlyRemoveMoved(
        _ items: [MovedItem],
        failures: inout [Failure]
    ) {
        for item in items {
            do {
                try fileManager.removeItem(at: item.trashURL)
            } catch {
                failures.append(
                    Failure(
                        path: item.originalPath,
                        message: "Cleaned, but could not free the space yet: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    /// Permanently deletes items currently in `~/.Trash`.
    func emptyTrashContents(byteHint: Int64) throws -> Outcome {
        let trashPath = homeDirectory + "/.Trash"
        guard fileManager.fileExists(atPath: trashPath) else {
            return .empty
        }

        let trashURL = URL(fileURLWithPath: trashPath, isDirectory: true)
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            return Outcome(
                freedBytes: 0,
                itemCount: 0,
                moved: [],
                failures: [Failure(path: trashPath, message: error.localizedDescription)],
                emptiedTrash: false
            )
        }

        guard !contents.isEmpty else {
            return .empty
        }

        var failures: [Failure] = []
        var deleted = 0
        for item in contents {
            do {
                try fileManager.removeItem(at: item)
                deleted += 1
            } catch {
                failures.append(Failure(path: item.path, message: error.localizedDescription))
            }
        }

        guard deleted > 0 else {
            return Outcome(
                freedBytes: 0,
                itemCount: 0,
                moved: [],
                failures: failures,
                emptiedTrash: false
            )
        }

        // Full success: trust the scan total. Partial: apportion by deleted share.
        let freed: Int64
        if failures.isEmpty {
            freed = max(byteHint, 0)
        } else {
            freed = max(byteHint, 0) * Int64(deleted) / Int64(contents.count)
        }

        return Outcome(
            freedBytes: freed,
            itemCount: deleted,
            moved: [],
            failures: failures,
            emptiedTrash: true
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

            guard isAllowedToTrash(item.originalPath) else {
                failures.append(
                    Failure(path: item.originalPath, message: "Restore path is protected and cannot be written.")
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
            failures: failures,
            emptiedTrash: false
        )
    }

    // MARK: - Safety

    /// Whether a path may be moved to Trash (home-only allowlist + protected prefixes).
    func isAllowedToTrash(_ path: String) -> Bool {
        PathSafetyPolicy.isAllowedToTrash(path, homeDirectory: homeDirectory)
    }
}
