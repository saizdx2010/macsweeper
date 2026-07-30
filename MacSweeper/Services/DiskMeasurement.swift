import Darwin
import Foundation

/// Allocated-size measurement with hard-link and APFS clone deduplication
/// (shared by scan + browse).
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

    /// Tracks inodes and APFS clone IDs already counted in the current walk.
    struct Deduper: Sendable {
        var seenHardLinks = Set<FileIdentity>()
        var seenCloneIDs = Set<CloneIdentity>()
    }

    /// Allocated size with hard-link + APFS clone dedupe (counts shared storage once).
    static func measureAllocatedSize(
        at url: URL,
        fileManager: FileManager = .default,
        seenHardLinks: inout Set<FileIdentity>
    ) throws -> Int64 {
        var deduper = Deduper(seenHardLinks: seenHardLinks)
        let total = try measureAllocatedSize(at: url, fileManager: fileManager, deduper: &deduper)
        seenHardLinks = deduper.seenHardLinks
        return total
    }

    static func measureAllocatedSize(
        at url: URL,
        fileManager: FileManager = .default,
        deduper: inout Deduper
    ) throws -> Int64 {
        let values = try url.resourceValues(forKeys: sizeKeys)

        if values.isDirectory != true {
            return allocatedBytes(forFileAt: url, values: values, deduper: &deduper)
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
            total += allocatedBytes(forFileAt: fileURL, values: fileValues, deduper: &deduper)
        }
        return total
    }

    static func allocatedBytes(
        forFileAt url: URL,
        values: URLResourceValues,
        seenHardLinks: inout Set<FileIdentity>
    ) -> Int64 {
        var deduper = Deduper(seenHardLinks: seenHardLinks)
        let bytes = allocatedBytes(forFileAt: url, values: values, deduper: &deduper)
        seenHardLinks = deduper.seenHardLinks
        return bytes
    }

    static func allocatedBytes(
        forFileAt url: URL,
        values: URLResourceValues,
        deduper: inout Deduper
    ) -> Int64 {
        if let identity = FileIdentity(url: url),
           let linkCount = values.linkCount,
           linkCount > 1 {
            if deduper.seenHardLinks.contains(identity) {
                return 0
            }
            deduper.seenHardLinks.insert(identity)
        }

        // APFS pure clones share a clone ID — count allocated blocks once per stream.
        if let identity = FileIdentity(url: url),
           let cloneID = APFSCloneInfo.cloneID(at: url),
           cloneID != 0 {
            let clone = CloneIdentity(device: identity.device, cloneID: cloneID)
            if deduper.seenCloneIDs.contains(clone) {
                return 0
            }
            deduper.seenCloneIDs.insert(clone)
        }

        if let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
            return Int64(allocated)
        }
        // Fallback: st_blocks is in 512-byte units (closer to reclaimable / sparse size-on-disk).
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

/// Volume-scoped APFS clone-id for shared-block deduplication.
struct CloneIdentity: Hashable, Sendable {
    let device: UInt64
    let cloneID: UInt64
}

/// Reads ATTR_CMNEXT_CLONEID via getattrlist (FSOPT_ATTR_CMN_EXTENDED).
enum APFSCloneInfo {
    static func cloneID(at url: URL) -> UInt64? {
        var attrList = attrlist(
            bitmapcount: u_short(ATTR_BIT_MAP_COUNT),
            reserved: 0,
            commonattr: 0,
            volattr: 0,
            dirattr: 0,
            fileattr: 0,
            forkattr: attrgroup_t(ATTR_CMNEXT_CLONEID)
        )

        // u_int32_t length + u_int64_t cloneID (+ alignment slack)
        var buffer = [UInt8](repeating: 0, count: 32)
        let result = buffer.withUnsafeMutableBytes { rawBuffer -> Int32 in
            guard let base = rawBuffer.baseAddress else { return -1 }
            return getattrlist(
                url.path,
                &attrList,
                base,
                rawBuffer.count,
                UInt32(FSOPT_ATTR_CMN_EXTENDED)
            )
        }
        guard result == 0 else { return nil }

        return buffer.withUnsafeBytes { rawBuffer -> UInt64? in
            guard rawBuffer.count >= MemoryLayout<UInt32>.size + MemoryLayout<UInt64>.size else {
                return nil
            }
            // Packed: length (UInt32), then attributes in bit order (cloneID).
            let cloneID = rawBuffer.loadUnaligned(
                fromByteOffset: MemoryLayout<UInt32>.size,
                as: UInt64.self
            )
            return cloneID
        }
    }
}
