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
    /// `extraDevRoots` are absolute paths merged into `find_named_dirs` discovery roots.
    nonisolated func scanStream(
        includeDevMode: Bool = false,
        extraDevRoots: [String] = []
    ) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runScan(
                        includeDevMode: includeDevMode,
                        extraDevRoots: extraDevRoots,
                        yieldingTo: continuation
                    )
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
    func scan(includeDevMode: Bool = false, extraDevRoots: [String] = []) async throws -> [ScanResult] {
        var results: [ScanResult] = []
        for try await event in scanStream(includeDevMode: includeDevMode, extraDevRoots: extraDevRoots) {
            if case .category(let result) = event {
                results.append(result)
            }
        }
        return results.sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - Scan loop

    private func runScan(
        includeDevMode: Bool,
        extraDevRoots: [String],
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

            let result = try measureCategory(category, extraDevRoots: extraDevRoots)
            if let result {
                foundCount += 1
                continuation.yield(.category(result))
            }
            continuation.yield(.ruleFinished(current: index + 1, total: total))
        }

        continuation.yield(.finished(foundCount: foundCount))
        continuation.finish()
    }

    private func measureCategory(
        _ category: ScanCategory,
        extraDevRoots: [String]
    ) throws -> ScanResult? {
        if category.action == .emptyTrash {
            return try measureEmptyTrash(category)
        }

        if category.scan == .findNamedDirs {
            return try measureFindNamedDirs(category, extraDevRoots: extraDevRoots)
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

    private func makeScannedPath(
        path: String,
        byteCount: Int64,
        isSelected: Bool,
        modificationDate: Date? = nil
    ) -> ScannedPath {
        let date = modificationDate ?? contentModificationDate(at: path)
        return ScannedPath(
            path: path,
            byteCount: byteCount,
            isSelected: isSelected,
            contentModificationDate: date
        )
    }

    private func contentModificationDate(at path: String) -> Date? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private func measureFixedPaths(_ category: ScanCategory) throws -> ScanResult? {
        var scannedPaths: [ScannedPath] = []
        var deduper = DiskMeasurement.Deduper()

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
                    deduper: &deduper
                )
                continue
            }

            let url = URL(fileURLWithPath: expanded, isDirectory: isDirectory.boolValue)
            let bytes = try measureAllocatedSize(at: url, deduper: &deduper)
            guard bytes > 0 else { continue }

            scannedPaths.append(
                makeScannedPath(
                    path: expanded,
                    byteCount: bytes,
                    isSelected: category.risk.isSelectedByDefault
                )
            )
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
        deduper: inout DiskMeasurement.Deduper
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
                includingPropertiesForKeys: Array(DiskMeasurement.sizeKeys),
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
            let bytes = try measureAllocatedSize(at: url, deduper: &deduper)
            guard bytes > 0 else { continue }
            scannedPaths.append(
                makeScannedPath(path: url.path, byteCount: bytes, isSelected: false)
            )
        }
    }

    /// Manual + guide: appear when any configured path exists (size optional).
    private func measureManualGuide(_ category: ScanCategory) throws -> ScanResult? {
        var scannedPaths: [ScannedPath] = []
        var deduper = DiskMeasurement.Deduper()
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
            let bytes = try measureAllocatedSize(at: url, deduper: &deduper)
            if bytes > 0 {
                scannedPaths.append(
                    makeScannedPath(path: expanded, byteCount: bytes, isSelected: false)
                )
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
        var deduper = DiskMeasurement.Deduper()

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
                    includingPropertiesForKeys: Array(DiskMeasurement.sizeKeys),
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
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let bytes = try measureAllocatedSize(at: url, deduper: &deduper)
                guard bytes > 0 else { continue }
                scannedPaths.append(
                    makeScannedPath(
                        path: url.path,
                        byteCount: bytes,
                        isSelected: isSelected,
                        modificationDate: values?.contentModificationDate
                    )
                )
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

    private func measureFindNamedDirs(
        _ category: ScanCategory,
        extraDevRoots: [String]
    ) throws -> ScanResult? {
        let names = Set(category.findNames ?? [])
        guard !names.isEmpty else { return nil }

        let maxDepth = category.maxDepth ?? 6
        var foundURLs: [URL] = []
        var seenRoots = Set<String>()

        var rootPaths: [String] = category.paths.map(expandHome)
        for extra in extraDevRoots {
            let standardized = (extra as NSString).standardizingPath
            guard PathSafetyPolicy.isPathUnderHome(standardized, homeDirectory: homeDirectory) else { continue }
            rootPaths.append(standardized)
        }

        for rootPath in rootPaths {
            try Task.checkCancellation()
            let standardized = (rootPath as NSString).standardizingPath
            guard PathSafetyPolicy.isPathUnderHome(standardized, homeDirectory: homeDirectory) else { continue }
            guard seenRoots.insert(standardized).inserted else { continue }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }
            try collectNamedDirectories(
                root: URL(fileURLWithPath: standardized, isDirectory: true),
                names: names,
                maxDepth: maxDepth,
                into: &foundURLs
            )
        }

        guard !foundURLs.isEmpty else { return nil }

        var scannedPaths: [ScannedPath] = []
        var deduper = DiskMeasurement.Deduper()
        let selected = category.risk.isSelectedByDefault

        for url in foundURLs {
            try Task.checkCancellation()
            let bytes = try measureAllocatedSize(at: url, deduper: &deduper)
            guard bytes > 0 else { continue }
            scannedPaths.append(
                makeScannedPath(path: url.path, byteCount: bytes, isSelected: selected)
            )
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
                        guard PathSafetyPolicy.isPathUnderHome(resolved.path, homeDirectory: homeDirectory),
                              !PathSafetyPolicy.isProtectedDiscoveryPath(
                                resolved.path,
                                homeDirectory: homeDirectory
                              )
                        else {
                            continue
                        }
                        found.append(resolved)
                    } else {
                        guard !PathSafetyPolicy.isProtectedDiscoveryPath(
                            child.path,
                            homeDirectory: homeDirectory
                        ) else { continue }
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
        if PathSafetyPolicy.isProtectedDiscoveryPath(url.path, homeDirectory: homeDirectory) {
            return false
        }
        // Never walk into Library even under Desktop/project trees via symlink.
        let name = url.lastPathComponent
        if name == "Library" || name == "node_modules" || name == ".git" {
            return false
        }
        return true
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
        deduper: inout DiskMeasurement.Deduper
    ) throws -> Int64 {
        try DiskMeasurement.measureAllocatedSize(
            at: url,
            fileManager: fileManager,
            deduper: &deduper
        )
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
