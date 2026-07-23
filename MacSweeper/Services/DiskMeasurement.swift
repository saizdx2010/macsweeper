import Foundation

/// Allocated-size measurement with hard-link deduplication (shared by scan + browse).
enum DiskMeasurement {
    static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .linkCountKey,
        .contentModificationDateKey,
    ]

    /// Allocated size with hard-link dedupe (counts each inode once within `seenHardLinks`).
    static func measureAllocatedSize(
        at url: URL,
        fileManager: FileManager = .default,
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
            // Check often so Cancel stays responsive on large trees (Library, etc.).
            if filesVisited.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let fileValues = try fileURL.resourceValues(forKeys: sizeKeys)
            guard fileValues.isRegularFile == true else { continue }
            total += allocatedBytes(forFileAt: fileURL, values: fileValues, seenHardLinks: &seenHardLinks)
        }
        return total
    }

    static func allocatedBytes(
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
struct FileIdentity: Hashable, Sendable {
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
