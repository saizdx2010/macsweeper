import Foundation

/// Loads declarative cleanup rules and walks the filesystem for sizes.
actor ScanEngine {
    enum Progress: Sendable {
        case started(ruleCount: Int)
        /// Emitted after each rule is measured (whether or not it produced a result).
        case ruleFinished(current: Int, total: Int)
        case category(ScanResult)
        case finished(foundCount: Int)
    }

    private let rulesURL: URL?
    private let fileManager: FileManager
    private let homeDirectory: String

    /// Relative home prefixes never entered during discovery walks.
    private let discoverySkipPrefixes: [String] = [
        "Library",
        "Documents",
        "Pictures",
        "Music",
        "Movies",
        ".Trash",
    ]

    private let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .linkCountKey,
    ]

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.rulesURL = bundle.url(forResource: "cleanup-rules", withExtension: "json")
        self.fileManager = fileManager
        self.homeDirectory = NSHomeDirectory()
    }

    /// Loads rules from the app bundle.
    func loadCategories() throws -> [ScanCategory] {
        guard let rulesURL else {
            throw ScanEngineError.rulesNotFound
        }
        let data = try Data(contentsOf: rulesURL)
        return try JSONDecoder().decode([ScanCategory].self, from: data)
    }

    /// Streams category results as they are measured. Cancel the consuming task to stop.
    /// When `includeDevMode` is false, rules with `group == "dev"` are skipped.
    nonisolated func scanStream(includeDevMode: Bool = false) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runScan(includeDevMode: includeDevMode, yieldingTo: continuation)
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Convenience: collect all results (still cancelable via Task).
    func scan(includeDevMode: Bool = false) async throws -> [ScanResult] {
        var results: [ScanResult] = []
        for try await event in scanStream(includeDevMode: includeDevMode) {
            if case .category(let result) = event {
                results.append(result)
            }
        }
        return results.sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - Scan loop

    private func runScan(
        includeDevMode: Bool,
        yieldingTo continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        let allCategories = try loadCategories()
        let categories = includeDevMode
            ? allCategories
            : allCategories.filter { !$0.isDevGroup }

        continuation.yield(.started(ruleCount: categories.count))

        var foundCount = 0
        let total = categories.count
        for (index, category) in categories.enumerated() {
            try Task.checkCancellation()

            let result = try measureCategory(category)
            if let result {
                foundCount += 1
                continuation.yield(.category(result))
            }
            continuation.yield(.ruleFinished(current: index + 1, total: total))
        }

        continuation.yield(.finished(foundCount: foundCount))
        continuation.finish()
    }

    private func measureCategory(_ category: ScanCategory) throws -> ScanResult? {
        if category.action == .emptyTrash {
            return try measureEmptyTrash(category)
        }

        if category.scan == .findNamedDirs {
            return try measureFindNamedDirs(category)
        }

        if category.scan == .listChildren {
            return try measureListChildren(category)
        }

        // Manual guidance: show when a marker path exists, even at 0 measured bytes.
        if category.risk == .manual, category.guideCommand != nil {
            return try measureManualGuide(category)
        }

        return try measureFixedPaths(category)
    }

    private func measureFixedPaths(_ category: ScanCategory) throws -> ScanResult? {
        var scannedPaths: [ScannedPath] = []
        var seenHardLinks = Set<FileIdentity>()

        for pathString in category.paths {
            try Task.checkCancellation()

            let expanded = expandHome(pathString)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
                continue
            }

            // Don't measure (or later trash) a folder that contains this running app —
            // e.g. ~/Library/Developer/Xcode/DerivedData while debugging from Xcode.
            if RunningAppSafety.isProtected(expanded) {
                try appendMeasuredChildren(
                    of: expanded,
                    into: &scannedPaths,
                    seenHardLinks: &seenHardLinks
                )
                continue
            }

            let url = URL(fileURLWithPath: expanded, isDirectory: isDirectory.boolValue)
            let bytes = try measureAllocatedSize(at: url, seenHardLinks: &seenHardLinks)
            guard bytes > 0 else { continue }

            scannedPaths.append(ScannedPath(path: expanded, byteCount: bytes))
        }

        guard !scannedPaths.isEmpty else { return nil }

        return ScanResult(
            category: category,
            paths: scannedPaths.sorted { $0.byteCount > $1.byteCount },
            isSelected: category.risk.isSelectedByDefault
        )
    }

    /// Measures immediate children, skipping any path that contains the running app.
    private func appendMeasuredChildren(
        of directoryPath: String,
        into scannedPaths: inout [ScannedPath],
        seenHardLinks: inout Set<FileIdentity>
    ) throws {
        let standardized = (directoryPath as NSString).standardizingPath
        if standardized == RunningAppSafety.bundlePath {
            return
        }

        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(sizeKeys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            return
        }

        for child in children {
            try Task.checkCancellation()
            if RunningAppSafety.isProtected(child.path) {
                continue
            }
            var childIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDirectory) else {
                continue
            }
            let url = URL(fileURLWithPath: child.path, isDirectory: childIsDirectory.boolValue)
            let bytes = try measureAllocatedSize(at: url, seenHardLinks: &seenHardLinks)
            guard bytes > 0 else { continue }
            scannedPaths.append(ScannedPath(path: url.path, byteCount: bytes))
        }
    }

    /// Manual + guide: appear when any configured path exists (size optional).
    private func measureManualGuide(_ category: ScanCategory) throws -> ScanResult? {
        var scannedPaths: [ScannedPath] = []
        var seenHardLinks = Set<FileIdentity>()
        var anyExists = false

        for pathString in category.paths {
            try Task.checkCancellation()

            let expanded = expandHome(pathString)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
                continue
            }
            anyExists = true

            // Homebrew cleanup guide: presence only (avoid double-counting cache size).
            if category.id == "homebrew_cleanup" {
                continue
            }

            let url = URL(fileURLWithPath: expanded, isDirectory: isDirectory.boolValue)
            let bytes = try measureAllocatedSize(at: url, seenHardLinks: &seenHardLinks)
            if bytes > 0 {
                scannedPaths.append(ScannedPath(path: expanded, byteCount: bytes))
            }
        }

        guard anyExists else { return nil }

        return ScanResult(
            category: category,
            paths: scannedPaths.sorted { $0.byteCount > $1.byteCount },
            isSelected: false
        )
    }

    /// Lists top-level Trash entries so item counts match what Empty Trash deletes.
    private func measureEmptyTrash(_ category: ScanCategory) throws -> ScanResult? {
        try measureListedChildren(
            category,
            directoryOptions: [],
            isSelected: category.risk.isSelectedByDefault
        )
    }

    /// Lists immediate children of configured folders (Downloads, Mail downloads, etc.).
    private func measureListChildren(_ category: ScanCategory) throws -> ScanResult? {
        try measureListedChildren(
            category,
            directoryOptions: [.skipsHiddenFiles],
            isSelected: category.risk.isSelectedByDefault
        )
    }

    /// Measures each immediate child of the configured directories.
    private func measureListedChildren(
        _ category: ScanCategory,
        directoryOptions: FileManager.DirectoryEnumerationOptions,
        isSelected: Bool
    ) throws -> ScanResult? {
        var scannedPaths: [ScannedPath] = []
        var seenHardLinks = Set<FileIdentity>()

        for pathString in category.paths {
            try Task.checkCancellation()

            let directoryPath = expandHome(pathString)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }

            let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
            let contents: [URL]
            do {
                contents = try fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: Array(sizeKeys),
                    options: directoryOptions
                )
            } catch {
                continue
            }

            for itemURL in contents {
                try Task.checkCancellation()
                if RunningAppSafety.isProtected(itemURL.path) {
                    continue
                }
                var itemIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &itemIsDirectory) else {
                    continue
                }
                let url = URL(
                    fileURLWithPath: itemURL.path,
                    isDirectory: itemIsDirectory.boolValue
                )
                let bytes = try measureAllocatedSize(at: url, seenHardLinks: &seenHardLinks)
                guard bytes > 0 else { continue }
                scannedPaths.append(ScannedPath(path: url.path, byteCount: bytes))
            }
        }

        guard !scannedPaths.isEmpty else { return nil }

        return ScanResult(
            category: category,
            paths: scannedPaths.sorted { $0.byteCount > $1.byteCount },
            isSelected: isSelected
        )
    }

    // MARK: - Discovery

    private func measureFindNamedDirs(_ category: ScanCategory) throws -> ScanResult? {
        let names = Set(category.findNames ?? [])
        guard !names.isEmpty else { return nil }

        let maxDepth = category.maxDepth ?? 6
        var foundURLs: [URL] = []

        for pathString in category.paths {
            try Task.checkCancellation()
            let rootPath = expandHome(pathString)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }
            try collectNamedDirectories(
                root: URL(fileURLWithPath: rootPath, isDirectory: true),
                names: names,
                maxDepth: maxDepth,
                into: &foundURLs
            )
        }

        guard !foundURLs.isEmpty else { return nil }

        var scannedPaths: [ScannedPath] = []
        var seenHardLinks = Set<FileIdentity>()

        for url in foundURLs {
            try Task.checkCancellation()
            let bytes = try measureAllocatedSize(at: url, seenHardLinks: &seenHardLinks)
            guard bytes > 0 else { continue }
            scannedPaths.append(ScannedPath(path: url.path, byteCount: bytes))
        }

        guard !scannedPaths.isEmpty else { return nil }

        return ScanResult(
            category: category,
            paths: scannedPaths.sorted { $0.byteCount > $1.byteCount },
            isSelected: category.risk.isSelectedByDefault
        )
    }

    private func collectNamedDirectories(
        root: URL,
        names: Set<String>,
        maxDepth: Int,
        into found: inout [URL]
    ) throws {
        var stack: [(url: URL, depth: Int)] = [(root, 0)]
        var visited = 0

        while let current = stack.popLast() {
            visited += 1
            if visited.isMultiple(of: 64) {
                try Task.checkCancellation()
            }

            let contents: [URL]
            do {
                contents = try fileManager.contentsOfDirectory(
                    at: current.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .nameKey],
                    options: []
                )
            } catch {
                continue
            }

            for child in contents {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .nameKey])
                let isSymlink = values?.isSymbolicLink == true
                let name = values?.name ?? child.lastPathComponent

                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDirectory),
                      childIsDirectory.boolValue
                else {
                    continue
                }

                if names.contains(name) {
                    if isSymlink {
                        let resolved = child.resolvingSymlinksInPath()
                        guard isPathUnderHome(resolved.path), !isProtectedDiscoveryPath(resolved.path) else {
                            continue
                        }
                        found.append(resolved)
                    } else {
                        guard !isProtectedDiscoveryPath(child.path) else { continue }
                        found.append(child)
                    }
                    // Do not descend into matched dirs (no nested node_modules).
                    continue
                }

                // Skip other hidden dirs (keep walking non-hidden; allow seeking .venv via names).
                if name.hasPrefix(".") { continue }
                if isSymlink { continue }
                if current.depth < maxDepth, shouldDescend(into: child) {
                    stack.append((child, current.depth + 1))
                }
            }
        }
    }

    private func shouldDescend(into url: URL) -> Bool {
        if isProtectedDiscoveryPath(url.path) { return false }
        // Never walk into Library even under Desktop/project trees via symlink.
        let name = url.lastPathComponent
        if name == "Library" || name == "node_modules" || name == ".git" {
            return false
        }
        return true
    }

    private func isPathUnderHome(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        return standardized == homeDirectory || standardized.hasPrefix(homeDirectory + "/")
    }

    private func isProtectedDiscoveryPath(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        guard isPathUnderHome(standardized) else { return true }
        guard standardized != homeDirectory else { return true }

        let relative = String(standardized.dropFirst(homeDirectory.count + 1))
        for prefix in discoverySkipPrefixes {
            if relative == prefix || relative.hasPrefix(prefix + "/") {
                // Allow Documents/GitHub specifically (it's a configured root).
                if prefix == "Documents", relative == "Documents/GitHub" || relative.hasPrefix("Documents/GitHub/") {
                    return false
                }
                return true
            }
        }
        return false
    }

    // MARK: - Path helpers

    private func expandHome(_ path: String) -> String {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory + String(path.dropFirst(1))
        }
        return (path as NSString).expandingTildeInPath
    }

    // MARK: - Size measurement

    /// Allocated size with hard-link dedupe (counts each inode once per category).
    private func measureAllocatedSize(
        at url: URL,
        seenHardLinks: inout Set<FileIdentity>
    ) throws -> Int64 {
        let values = try url.resourceValues(forKeys: sizeKeys)

        if values.isDirectory != true {
            return allocatedBytes(forFileAt: url, values: values, seenHardLinks: &seenHardLinks)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        var filesVisited = 0
        for case let fileURL as URL in enumerator {
            filesVisited += 1
            if filesVisited.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let fileValues = try fileURL.resourceValues(forKeys: sizeKeys)
            guard fileValues.isRegularFile == true else { continue }
            total += allocatedBytes(forFileAt: fileURL, values: fileValues, seenHardLinks: &seenHardLinks)
        }
        return total
    }

    private func allocatedBytes(
        forFileAt url: URL,
        values: URLResourceValues,
        seenHardLinks: inout Set<FileIdentity>
    ) -> Int64 {
        if let identity = FileIdentity(url: url),
           let linkCount = values.linkCount,
           linkCount > 1 {
            if seenHardLinks.contains(identity) {
                return 0
            }
            seenHardLinks.insert(identity)
        }

        if let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
            return Int64(allocated)
        }
        // Fallback: st_blocks is in 512-byte units (closer to reclaimable space).
        if let identity = FileIdentity(url: url) {
            return identity.blockBytes
        }
        return Int64(values.fileSize ?? 0)
    }
}

/// Volume device + inode identity for hard-link deduplication.
private struct FileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
    let blockBytes: Int64

    init?(url: URL) {
        var status = stat()
        let result = lstat(url.path, &status)
        guard result == 0 else { return nil }
        device = UInt64(status.st_dev)
        inode = UInt64(status.st_ino)
        blockBytes = Int64(status.st_blocks) * 512
    }
}

enum ScanEngineError: LocalizedError {
    case rulesNotFound

    var errorDescription: String? {
        switch self {
        case .rulesNotFound:
            return "cleanup-rules.json was not found in the app bundle."
        }
    }
}
