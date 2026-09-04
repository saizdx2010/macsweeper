import AppKit
import CoreServices
import Foundation

/// Pure eligibility rules for the Unused apps rule (unit-tested without disk I/O).
enum UnusedAppEligibility {
    /// Apple system apps are never suggested; bundles without a readable
    /// identifier are skipped too (unknown provenance).
    static func isExcludedBundleID(_ bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return true }
        return bundleID.hasPrefix("com.apple.")
    }

    /// True when the app was last used before the cutoff. Apps with an unknown
    /// last-used date are never suggested (age cannot be verified).
    static func isUnused(lastUsed: Date?, now: Date, minAgeDays: Int) -> Bool {
        guard let lastUsed else { return false }
        return lastUsed < now.addingTimeInterval(-Double(minAgeDays) * 24 * 60 * 60)
    }
}

/// Measures app bundles under the rule's roots (e.g. /Applications, ~/Applications)
/// that have not been used for at least `min_age_days`.
enum UnusedAppScanner {
    /// Last-used date from Spotlight; falls back to the bundle's creation date so
    /// never-opened apps are judged from when they first appeared on disk.
    static func lastUsedDate(at url: URL) -> Date? {
        if let spotlightDate = NSMetadataItem(url: url)?
            .value(forAttribute: kMDItemLastUsedDate as String) as? Date {
            return spotlightDate
        }
        return creationFallbackDate(at: url)
    }

    /// Creation-date fallback (injectable in tests, where Spotlight's indexer
    /// stamps index time as last-used for files without usage history).
    static func creationFallbackDate(at url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate
    }

    static func measure(
        category: ScanCategory,
        fileManager: FileManager,
        homeDirectory: String,
        now: Date = Date(),
        runningBundlePaths: Set<String>? = nil,
        lastUsedDateProvider: (URL) -> Date? = { lastUsedDate(at: $0) }
    ) throws -> ScanResult? {
        let minAgeDays = max(category.minAgeDays ?? 30, 1)
        let running = runningBundlePaths ?? currentRunningBundlePaths()

        var scannedPaths: [ScannedPath] = []
        var deduper = DiskMeasurement.Deduper()

        for pathString in category.paths {
            try Task.checkCancellation()
            let rootPath = expandHome(pathString, homeDirectory: homeDirectory)
            var rootIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootPath, isDirectory: &rootIsDirectory),
                  rootIsDirectory.boolValue
            else { continue }

            let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            let contents: [URL]
            do {
                contents = try fileManager.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                continue
            }

            for child in contents {
                try Task.checkCancellation()
                let path = child.path
                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &childIsDirectory),
                      childIsDirectory.boolValue,
                      child.lastPathComponent.hasSuffix(".app")
                else { continue }
                // Same predicate the trash allowlist accepts — a scan hit can
                // always actually be cleaned.
                guard PathSafetyPolicy.isScannableApplicationBundle(path, homeDirectory: homeDirectory)
                else { continue }
                guard !RunningAppSafety.isProtected(path) else { continue }
                guard !running.contains((path as NSString).standardizingPath) else { continue }
                guard !UnusedAppEligibility.isExcludedBundleID(Bundle(url: child)?.bundleIdentifier)
                else { continue }

                let lastUsed = lastUsedDateProvider(child)
                guard UnusedAppEligibility.isUnused(
                    lastUsed: lastUsed,
                    now: now,
                    minAgeDays: minAgeDays
                ) else { continue }

                let bytes = try DiskMeasurement.measureAllocatedSize(
                    at: child,
                    fileManager: fileManager,
                    deduper: &deduper
                )
                guard bytes > 0 else { continue }

                scannedPaths.append(
                    ScannedPath(
                        path: path,
                        byteCount: bytes,
                        isSelected: category.risk.isSelectedByDefault,
                        contentModificationDate: lastUsed
                    )
                )
            }
        }

        guard !scannedPaths.isEmpty else { return nil }

        return ScanResult(
            category: category,
            paths: scannedPaths.sorted { $0.byteCount > $1.byteCount },
            isSelected: category.risk.isSelectedByDefault
        )
    }

    /// Bundle paths of currently running apps — a live app is in use even when
    /// Spotlight's last-used date has not caught up (long-running apps update it
    /// on quit).
    private static func currentRunningBundlePaths() -> Set<String> {
        if Thread.isMainThread {
            return Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
        }
        return DispatchQueue.main.sync {
            Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
        }
    }

    private static func expandHome(_ path: String, homeDirectory: String) -> String {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") {
            return homeDirectory + String(path.dropFirst(1))
        }
        return (path as NSString).expandingTildeInPath
    }
}
