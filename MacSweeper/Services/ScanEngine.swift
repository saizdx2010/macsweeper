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

    private let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
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
    nonisolated func scanStream() -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runScan(yieldingTo: continuation)
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
    func scan() async throws -> [ScanResult] {
        var results: [ScanResult] = []
        for try await event in scanStream() {
            if case .category(let result) = event {
                results.append(result)
            }
        }
        return results.sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - Scan loop

    private func runScan(
        yieldingTo continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        let categories = try loadCategories()
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
        var scannedPaths: [ScannedPath] = []
        // Hard links can appear under multiple paths; dedupe within a category.
        var seenHardLinks = Set<FileIdentity>()

        for pathString in category.paths {
            try Task.checkCancellation()

            let expanded = expandHome(pathString)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
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
