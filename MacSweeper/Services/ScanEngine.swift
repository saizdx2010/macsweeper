import Foundation

/// Loads declarative cleanup rules and walks the filesystem for sizes.
actor ScanEngine {
    private let rulesURL: URL?
    private let fileManager: FileManager
    private let homeDirectory: String

    private let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
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

    /// Walks each rule path and returns categories with measurable reclaimable space.
    func scan() async throws -> [ScanResult] {
        let categories = try loadCategories()
        var results: [ScanResult] = []

        for category in categories {
            try Task.checkCancellation()

            var scannedPaths: [ScannedPath] = []
            for pathString in category.paths {
                try Task.checkCancellation()

                let expanded = expandHome(pathString)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
                    continue
                }

                let url = URL(fileURLWithPath: expanded, isDirectory: isDirectory.boolValue)
                let bytes = try measureAllocatedSize(at: url)
                guard bytes > 0 else { continue }

                // Store absolute paths so Phase 2 can move them to Trash.
                scannedPaths.append(
                    ScannedPath(path: expanded, byteCount: bytes)
                )
            }

            guard !scannedPaths.isEmpty else { continue }

            results.append(
                ScanResult(
                    category: category,
                    paths: scannedPaths.sorted { $0.byteCount > $1.byteCount },
                    isSelected: category.risk.isSelectedByDefault
                )
            )
        }

        return results.sorted { $0.totalBytes > $1.totalBytes }
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

    /// Sums allocated size via a naive recursive walk (APFS clone accuracy later).
    private func measureAllocatedSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: sizeKeys)

        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
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
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let fileValues = try fileURL.resourceValues(forKeys: sizeKeys)
            guard fileValues.isRegularFile == true else { continue }
            total += Int64(fileValues.totalFileAllocatedSize ?? fileValues.fileAllocatedSize ?? 0)
        }
        return total
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
