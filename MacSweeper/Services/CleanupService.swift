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

/// Moves selected scan results to Trash (never permanent delete, except Empty Trash).
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
        /// True when Trash contents were permanently deleted (no undo).
        let emptiedTrash: Bool

        static let empty = Outcome(
            freedBytes: 0,
            itemCount: 0,
            moved: [],
            failures: [],
            emptiedTrash: false
        )
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
        // Credential / secrets roots
        ".ssh",
        ".gnupg",
        ".aws",
        ".config",
        ".kube",
        ".docker",
        // Sensitive Library data
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Suggestions",
        "Library/Containers/com.apple.Safari",
        "Library/Safari",
        "Library/Accounts",
        "Library/Cookies",
        "Library/IdentityServices",
        "Library/Calendars",
        "Library/Reminders",
        "Library/Shortcuts",
        "Library/PersonalizationPortrait",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CallHistoryTransactions",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/1Password",
        "Library/Application Support/com.1password.1password",
        "Library/Application Support/Bitwarden",
        "Library/Application Support/com.bitwarden.desktop",
        // Browser profile credential stores (caches live under different rule paths)
        "Library/Application Support/Google/Chrome/Default/Login Data",
        "Library/Application Support/Google/Chrome/Default/Cookies",
        "Library/Application Support/Google/Chrome/Default/Web Data",
        "Library/Application Support/Microsoft Edge/Default/Login Data",
        "Library/Application Support/Microsoft Edge/Default/Cookies",
        "Library/Application Support/Microsoft Edge/Default/Web Data",
        "Library/Application Support/BraveSoftware/Brave-Browser/Default/Login Data",
        "Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies",
        "Library/Application Support/BraveSoftware/Brave-Browser/Default/Web Data",
        "Library/Application Support/Firefox/Profiles",
    ]

    /// Dev-mode discovery targets allowed under otherwise-protected roots (Documents/Desktop).
    private let allowedDevCleanupDirectoryNames: Set<String> = [
        "node_modules",
        ".venv",
        "venv",
        "target",
        ".gradle",
        "Pods",
    ]

    init(fileManager: FileManager = .default, homeDirectory: String = NSHomeDirectory()) {
        self.fileManager = fileManager
        self.homeDirectory = (homeDirectory as NSString).standardizingPath
    }

    /// Moves paths to Trash and/or permanently empties Trash when selected.
    func moveToTrash(_ results: [ScanResult]) async throws -> Outcome {
        var moved: [MovedItem] = []
        var failures: [Failure] = []
        var emptiedTrash = false
        var emptiedBytes: Int64 = 0
        var emptiedCount = 0

        let selected = results.compactMap { $0.selectingOnlyCheckedPaths() }

        for result in selected {
            try Task.checkCancellation()

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

        let movedBytes = moved.reduce(Int64(0)) { $0 + $1.byteCount }
        return Outcome(
            freedBytes: movedBytes + emptiedBytes,
            itemCount: moved.count + emptiedCount,
            moved: moved,
            failures: failures,
            emptiedTrash: emptiedTrash
        )
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
        // Resolve symlinks so a link under an allowed folder cannot escape into a protected root.
        let standardized = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: homeDirectory).resolvingSymlinksInPath().path
        guard standardized.hasPrefix(home + "/") || standardized == home + "/.Trash" else {
            // Allow ~/.Trash itself only for empty-trash action (handled separately).
            return false
        }
        guard standardized != home else { return false }

        // Never move the Trash folder itself via trashItem.
        if standardized == home + "/.Trash" { return false }

        let relative = String(standardized.dropFirst(home.count + 1))
        if relative == "Library" { return false }

        let lastComponent = (relative as NSString).lastPathComponent
        let isDevCleanupDir = allowedDevCleanupDirectoryNames.contains(lastComponent)

        for prefix in protectedPrefixes {
            if relative == prefix || relative.hasPrefix(prefix + "/") {
                // Allow only named Dev cleanup dirs under Documents / Desktop project roots.
                if isDevCleanupDir, prefix == "Documents" || prefix == "Desktop" {
                    return true
                }
                return false
            }
        }
        return true
    }
}
