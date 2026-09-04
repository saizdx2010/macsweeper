import Foundation

/// Reports free / used space on the boot volume.
@MainActor
final class DiskSpaceService {
    struct Snapshot: Equatable {
        let freeBytes: Int64
        let totalBytes: Int64
        let usedBytes: Int64

        var usedFraction: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(usedBytes) / Double(totalBytes)
        }
    }

    func currentSnapshot() -> Snapshot? {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ])

        guard
            let importantUsage = values?.volumeAvailableCapacityForImportantUsage,
            let totalCapacity = values?.volumeTotalCapacity
        else {
            return nil
        }

        let free = Int64(importantUsage)
        let total = Int64(totalCapacity)
        guard total > 0 else { return nil }

        return Snapshot(
            freeBytes: free,
            totalBytes: total,
            usedBytes: max(0, total - free)
        )
    }
}

/// Observed free-space change between two volume readings — the honest
/// cross-check for a clean ("Finder now shows +2.6 GB").
enum FreeSpaceDelta {
    /// nil unless both readings exist (e.g. the volume query failed once).
    static func gainBytes(before: Int64?, after: Int64?) -> Int64? {
        guard let before, let after else { return nil }
        return after - before
    }
}
