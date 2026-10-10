import Foundation

/// Pure rules for build artifacts of inactive projects (unit-tested without disk I/O).
enum StaleProjectPolicy {
    /// Files whose presence marks a directory as a project root.
    static let projectMarkers: [String] = [
        ".git", "package.json", "pyproject.toml", "build.gradle", "build.gradle.kts", "Cargo.toml",
    ]

    /// Names too generic to trust without a marker directly in the parent.
    static let ambiguousArtifactNames: Set<String> = ["build", "dist"]

    static let defaultArtifactNames: [String] = [
        ".next", "dist", "build", ".turbo", ".parcel-cache", "__pycache__",
        ".tox", ".pytest_cache", ".mypy_cache", ".gradle",
    ]

    static let defaultMinAgeDays = 90

    /// Directories the walk never enters.
    static func isNeverDescended(_ name: String) -> Bool {
        name == "node_modules" || name == "Library" || name == ".git" || name == ".Trash"
    }

    /// Whether `name` counts as an artifact given which markers the parent holds.
    /// `build` / `dist` need a marker right in the parent; the rest only need to
    /// live inside some project (checked by the caller).
    static func isArtifactCandidate(name: String, parentHasMarker: Bool, names: Set<String>) -> Bool {
        guard names.contains(name) else { return false }
        return ambiguousArtifactNames.contains(name) ? parentHasMarker : true
    }

    /// Most recent sign of life: last git activity or any top-level file edit.
    static func lastActivity(gitActivity: Date?, topLevelFileDates: [Date]) -> Date? {
        (topLevelFileDates + [gitActivity].compactMap { $0 }).max()
    }

    /// Unknown activity is never stale — inactivity cannot be proven.
    static func isStale(lastActivity: Date?, now: Date, minAgeDays: Int) -> Bool {
        guard let lastActivity else { return false }
        return now.timeIntervalSince(lastActivity) >= TimeInterval(minAgeDays) * 86_400
    }
}

/// Finds regenerable build output (.next, dist, __pycache__, …) inside Dev scan
/// roots, but only for projects untouched for `min_age_days` (default 90).
enum StaleProjectArtifactScanner {
    static func measure(
        category: ScanCategory,
        roots: [String],
        fileManager: FileManager,
        homeDirectory: String,
        now: Date = Date(),
        deduper: inout DiskMeasurement.Deduper
    ) throws -> ScanResult? {
        let names = Set(category.findNames ?? StaleProjectPolicy.defaultArtifactNames)
        let maxDepth = category.maxDepth ?? 6
        let minAge = category.minAgeDays ?? StaleProjectPolicy.defaultMinAgeDays

        var markerCache: [String: Bool] = [:]
        var staleCache: [String: Bool] = [:]
        var found: [URL] = []
        var seenRoots = Set<String>()

        func hasMarker(_ dir: String) -> Bool {
            if let cached = markerCache[dir] { return cached }
            let result = StaleProjectPolicy.projectMarkers.contains {
                fileManager.fileExists(atPath: dir + "/" + $0)
            }
            markerCache[dir] = result
            return result
        }

        func isStaleProject(_ dir: String) -> Bool {
            if let cached = staleCache[dir] { return cached }
            let activity = projectActivity(at: dir, fileManager: fileManager)
            let result = StaleProjectPolicy.isStale(lastActivity: activity, now: now, minAgeDays: minAge)
            staleCache[dir] = result
            return result
        }

        /// Nearest ancestor (at or below the scan root) holding a project marker.
        func projectDirectory(containing parent: String, root: String) -> String? {
            var current = parent
            while true {
                if hasMarker(current) { return current }
                if current == root || current.count <= root.count { return nil }
                current = (current as NSString).deletingLastPathComponent
            }
        }

        for rawRoot in roots {
            try Task.checkCancellation()
            let root = (rawRoot as NSString).standardizingPath
            guard PathSafetyPolicy.isPathUnderHome(root, homeDirectory: homeDirectory),
                  seenRoots.insert(root).inserted
            else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue
            else { continue }

            var stack: [(path: String, depth: Int)] = [(root, 0)]
            var visited = 0
            while let current = stack.popLast() {
                visited += 1
                if visited.isMultiple(of: 64) { try Task.checkCancellation() }

                let contents = (try? fileManager.contentsOfDirectory(
                    at: URL(fileURLWithPath: current.path, isDirectory: true),
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                )) ?? []

                for child in contents {
                    let name = child.lastPathComponent
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

                    if names.contains(name) {
                        let parentHasMarker = hasMarker(current.path)
                        if StaleProjectPolicy.isArtifactCandidate(
                            name: name,
                            parentHasMarker: parentHasMarker,
                            names: names
                        ), !PathSafetyPolicy.isProtectedDiscoveryPath(child.path, homeDirectory: homeDirectory),
                           let project = projectDirectory(containing: current.path, root: root),
                           isStaleProject(project) {
                            found.append(child)
                        }
                        // Never descend into artifact-named dirs.
                        continue
                    }

                    if name.hasPrefix(".") || StaleProjectPolicy.isNeverDescended(name) { continue }
                    if current.depth < maxDepth,
                       !PathSafetyPolicy.isProtectedDiscoveryPath(child.path, homeDirectory: homeDirectory) {
                        stack.append((child.path, current.depth + 1))
                    }
                }
            }
        }

        var scannedPaths: [ScannedPath] = []
        for url in found {
            try Task.checkCancellation()
            guard PathSafetyPolicy.isAllowedToTrash(url.path, homeDirectory: homeDirectory),
                  !RunningAppSafety.isProtected(url.path)
            else { continue }
            let bytes = try DiskMeasurement.measureAllocatedSize(
                at: url,
                fileManager: fileManager,
                deduper: &deduper
            )
            guard bytes > 0 else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            scannedPaths.append(
                ScannedPath(
                    path: url.path,
                    byteCount: bytes,
                    isSelected: category.risk.isSelectedByDefault,
                    contentModificationDate: values?.contentModificationDate
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

    /// Newest of the git reflog / HEAD mtime and the top-level files' mtimes
    /// (so uncommitted edits still count as activity). No shelling out.
    static func projectActivity(at dir: String, fileManager: FileManager) -> Date? {
        func mtime(_ path: String) -> Date? {
            (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        }
        let git = mtime(dir + "/.git/logs/HEAD") ?? mtime(dir + "/.git/HEAD")

        let entries = (try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: dir, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: []
        )) ?? []
        var fileDates: [Date] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            if values?.isRegularFile == true, let date = values?.contentModificationDate {
                fileDates.append(date)
            }
        }
        return StaleProjectPolicy.lastActivity(gitActivity: git, topLevelFileDates: fileDates)
    }
}
