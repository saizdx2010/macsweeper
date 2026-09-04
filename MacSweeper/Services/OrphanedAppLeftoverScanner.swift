import Foundation

/// Pure orphan-matching rules (unit-tested without disk I/O).
///
/// A leftover is only reported when the app it belongs to is provably gone:
/// either its reverse-DNS bundle ID no longer exists in an Applications root,
/// or (for vendor-style folder names) some already-orphaned bundle ID
/// corroborates the name. Anything ambiguous stays unreported.
enum OrphanedAppPolicy {
    static let savedStateSuffix = ".savedState"
    static let plistSuffix = ".plist"

    /// Extracts a reverse-DNS bundle ID from a file or folder name, stripping
    /// `.plist` / `.savedState` suffixes. Names like `com.tinyspeck.slackmacgap`
    /// qualify; `Slack`, `ByHost`, and `zoom.us Backups` do not.
    static func bundleID(fromFileName name: String) -> String? {
        var candidate = name
        if candidate.hasSuffix(savedStateSuffix) {
            candidate = String(candidate.dropLast(savedStateSuffix.count))
        } else if candidate.hasSuffix(plistSuffix) {
            candidate = String(candidate.dropLast(plistSuffix.count))
        }

        guard !candidate.isEmpty else { return nil }
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        guard candidate == candidate.lowercased() else { return nil }
        guard !candidate.contains(" "), !candidate.contains("/") else { return nil }
        return candidate
    }

    /// Apple's own data is never reported — macOS manages it.
    static func isAppleBundleID(_ id: String) -> Bool {
        id == "com.apple" || id.hasPrefix("com.apple.")
    }

    /// True when an installed app already uses this bundle ID.
    static func isInstalled(bundleID: String, installedBundleIDs: Set<String>) -> Bool {
        installedBundleIDs.contains(bundleID)
    }

    /// Guard for vendor-style folder names that serve several apps: keep the
    /// folder when an installed app's name matches it exactly or as a whole-word
    /// prefix ("Google" stays while "Google Chrome" is installed).
    static func nameMatchesInstalledApp(_ name: String, installedAppNames: Set<String>) -> Bool {
        let folded = name.lowercased()
        for installed in installedAppNames {
            if installed == folded { return true }
            if installed.hasPrefix(folded + " ") { return true }
            if folded.hasPrefix(installed + " ") { return true }
        }
        return false
    }

    /// Lowercased alphanumeric folding for loose name ↔ bundle ID matching.
    static func normalizedToken(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// A name-based folder ("Slack") is only reported when some orphaned bundle
    /// ID corroborates it: one of the ID's dotted segments is prefix-related to
    /// the name (com.tinyspeck.slackmacgap → "slackmacgap" starts with "slack").
    /// Folders like `MobileSync` match no orphan ID and are never reported;
    /// shared vendor folders like `Google` corroborate only when a Google-bundle
    /// orphan exists. The most specific (longest segment) match wins so grouping
    /// stays stable.
    static func corroboratingBundleID(
        name: String,
        orphanBundleIDs: Set<String>,
        minimumTokenLength: Int = 4
    ) -> String? {
        let token = normalizedToken(name)
        guard token.count >= minimumTokenLength else { return nil }

        var best: String?
        var bestSegmentLength = 0
        for bundleID in orphanBundleIDs.sorted() {
            for segment in bundleID.split(separator: ".") {
                let segmentToken = normalizedToken(String(segment))
                guard segmentToken.count >= minimumTokenLength else { continue }
                let related = segmentToken.hasPrefix(token) || token.hasPrefix(segmentToken)
                if related, segmentToken.count > bestSegmentLength {
                    best = bundleID
                    bestSegmentLength = segmentToken.count
                }
            }
        }
        return best
    }

    /// Short human label for a bundle ID with no folder-name evidence:
    /// `com.tinyspeck.slackmacgap` → "Slackmacgap".
    static func displayName(forBundleID id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        let folded = normalizedToken(last)
        guard let first = folded.first else { return id }
        return first.uppercased() + folded.dropFirst()
    }

    /// Containers hold sandboxed data that may belong to other accounts
    /// (e.g. after an account was removed); only user-owned ones are listed.
    static func isUserOwned(ownerAccountID: UInt64?, currentUserID: UInt32) -> Bool {
        guard let ownerAccountID else { return false }
        return ownerAccountID == UInt64(currentUserID)
    }
}

/// Finds files that installed apps left behind: for every bundle ID that no
/// longer exists in `/Applications` or `~/Applications`, reports its
/// Preferences plist, Caches, Application Support, Logs, Saved Application
/// State, and (user-owned) Containers paths under the home folder.
enum OrphanedAppLeftoverScanner {
    /// Library roots walked one level deep, keyed by home-relative location.
    enum LeftoverRoot: String, CaseIterable {
        case preferences = "Library/Preferences"
        case appSupport = "Library/Application Support"
        case caches = "Library/Caches"
        case logs = "Library/Logs"
        case savedState = "Library/Saved Application State"
        case containers = "Library/Containers"

        /// Roots whose children are always named `<bundleID>` (+ suffix).
        var isBundleIDKeyed: Bool {
            switch self {
            case .preferences, .savedState, .containers: return true
            case .appSupport, .caches, .logs: return false
            }
        }
    }

    /// Apps currently installed in `/Applications` and `~/Applications`.
    struct InstalledApps {
        let bundleIDs: Set<String>
        /// Lowercased bundle names without `.app`, e.g. "google chrome".
        let names: Set<String>

        static let none = InstalledApps(bundleIDs: [], names: [])
    }

    /// A leftover hit before size measurement.
    struct Candidate {
        let path: String
        let groupKey: String
        /// Folder-name evidence for the label, when the hit came from a
        /// human-named folder ("Slack"); nil for pure bundle-ID hits.
        let nameEvidence: String?
    }

    static func collectInstalledApps(
        fileManager: FileManager,
        homeDirectory: String
    ) -> InstalledApps {
        var bundleIDs = Set<String>()
        var names = Set<String>()

        for rootPath in ["/Applications", homeDirectory + "/Applications"] {
            let url = URL(fileURLWithPath: rootPath, isDirectory: true)
            let contents = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in contents where child.lastPathComponent.hasSuffix(".app") {
                if let id = Bundle(url: child)?.bundleIdentifier {
                    bundleIDs.insert(id)
                }
                let name = String(child.lastPathComponent.dropLast(".app".count))
                if !name.isEmpty {
                    names.insert(name.lowercased())
                }
            }
        }
        return InstalledApps(bundleIDs: bundleIDs, names: names)
    }

    static func measure(
        category: ScanCategory,
        fileManager: FileManager,
        homeDirectory: String,
        installedApps: InstalledApps? = nil,
        currentUserID: UInt32 = getuid(),
        deduper: inout DiskMeasurement.Deduper
    ) throws -> ScanResult? {
        let apps = installedApps ?? Self.collectInstalledApps(
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )

        // Pass 1 — bundle-ID-keyed hits also build the orphan-ID set that
        // pass 2 needs to corroborate human-named folders.
        var orphanBundleIDs = Set<String>()
        var idKeyed: [Candidate] = []
        var namedFolders: [(name: String, path: String)] = []

        for root in LeftoverRoot.allCases {
            for child in children(of: homeDirectory + "/" + root.rawValue, fileManager: fileManager) {
                try Task.checkCancellation()
                let name = child.lastPathComponent
                if let id = OrphanedAppPolicy.bundleID(fromFileName: name) {
                    guard !OrphanedAppPolicy.isAppleBundleID(id),
                          !OrphanedAppPolicy.isInstalled(bundleID: id, installedBundleIDs: apps.bundleIDs)
                    else { continue }
                    orphanBundleIDs.insert(id)
                    idKeyed.append(Candidate(path: child.path, groupKey: id, nameEvidence: nil))
                } else if !root.isBundleIDKeyed {
                    namedFolders.append((name, child.path))
                }
            }
        }

        // Pass 2 — human-named folders only when an orphaned bundle ID backs them.
        var candidates = idKeyed
        for folder in namedFolders {
            try Task.checkCancellation()
            guard !OrphanedAppPolicy.nameMatchesInstalledApp(folder.name, installedAppNames: apps.names)
            else { continue }
            guard let key = OrphanedAppPolicy.corroboratingBundleID(
                name: folder.name,
                orphanBundleIDs: orphanBundleIDs
            ) else { continue }
            candidates.append(Candidate(path: folder.path, groupKey: key, nameEvidence: folder.name))
        }

        // Safety gate + sizing. The trash allowlist is the same predicate the
        // clean step applies, so every reported path can actually be cleaned.
        var scannedPaths: [ScannedPath] = []
        for candidate in candidates {
            try Task.checkCancellation()
            guard isReportable(
                candidate.path,
                root: root(for: candidate.path, homeDirectory: homeDirectory),
                fileManager: fileManager,
                homeDirectory: homeDirectory,
                currentUserID: currentUserID
            ) else { continue }

            let bytes = try DiskMeasurement.measureAllocatedSize(
                at: URL(fileURLWithPath: candidate.path),
                fileManager: fileManager,
                deduper: &deduper
            )
            guard bytes > 0 else { continue }

            scannedPaths.append(
                ScannedPath(
                    path: candidate.path,
                    byteCount: bytes,
                    isSelected: category.risk.isSelectedByDefault,
                    contentModificationDate: contentModificationDate(at: candidate.path),
                    groupKey: candidate.groupKey,
                    groupLabel: candidate.nameEvidence
                )
            )
        }

        guard !scannedPaths.isEmpty else { return nil }

        // Promote the best available label per group (folder evidence beats a
        // prettified bundle ID) and apply it to every path in that group.
        let labels = Dictionary(
            grouping: scannedPaths,
            by: { $0.groupKey ?? "" }
        ).mapValues { paths -> String in
            paths.compactMap(\.groupLabel).first
                ?? OrphanedAppPolicy.displayName(forBundleID: paths[0].groupKey ?? "")
        }
        for index in scannedPaths.indices {
            scannedPaths[index].groupLabel = labels[scannedPaths[index].groupKey ?? ""]
        }

        return ScanResult(
            category: category,
            paths: scannedPaths.sorted { $0.byteCount > $1.byteCount },
            isSelected: category.risk.isSelectedByDefault
        )
    }

    // MARK: - Safety gate

    private static func isReportable(
        _ path: String,
        root: LeftoverRoot?,
        fileManager: FileManager,
        homeDirectory: String,
        currentUserID: UInt32
    ) -> Bool {
        guard PathSafetyPolicy.isAllowedToTrash(path, homeDirectory: homeDirectory) else { return false }
        guard !RunningAppSafety.isProtected(path) else { return false }

        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isSymbolicLink != true else { return false }

        if root == .containers {
            let owner = (try? fileManager.attributesOfItem(atPath: path))?[.ownerAccountID] as? NSNumber
            guard OrphanedAppPolicy.isUserOwned(
                ownerAccountID: owner?.uint64Value,
                currentUserID: currentUserID
            ) else { return false }
        }
        return true
    }

    // MARK: - Helpers

    /// The known root a path belongs to, or nil when it is outside all of them.
    private static func root(for path: String, homeDirectory: String) -> LeftoverRoot? {
        LeftoverRoot.allCases.first { root in
            let rootPath = homeDirectory + "/" + root.rawValue
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private static func children(of directoryPath: String, fileManager: FileManager) -> [URL] {
        let url = URL(fileURLWithPath: directoryPath, isDirectory: true)
        return (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func contentModificationDate(at path: String) -> Date? {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}

/// Groups leftover paths per orphaned app for the detail view
/// ("Uninstalled app leftovers → Slack — 3 paths · 412 MB").
enum LeftoverGrouping {
    struct Group: Identifiable {
        let key: String
        let label: String
        var paths: [ScannedPath]

        var id: String { key }
        var totalBytes: Int64 { paths.reduce(0) { $0 + $1.byteCount } }
        var selectedCount: Int { paths.filter(\.isSelected).count }
        var isFullySelected: Bool { selectedCount == paths.count }
    }

    /// Groups paths that carry a `groupKey`; unkeyed paths land in a trailing
    /// catch-all group. Order: biggest group total first, then by path size.
    static func groups(from paths: [ScannedPath]) -> [Group] {
        let keyed = paths.filter { $0.groupKey != nil }
        var buckets: [String: [ScannedPath]] = [:]
        for path in keyed {
            buckets[path.groupKey ?? "", default: []].append(path)
        }

        var groups = buckets.map { key, groupPaths -> Group in
            Group(
                key: key,
                label: groupPaths.compactMap(\.groupLabel).first
                    ?? OrphanedAppPolicy.displayName(forBundleID: key),
                paths: groupPaths.sorted { $0.byteCount > $1.byteCount }
            )
        }
        .sorted { $0.totalBytes > $1.totalBytes }

        let unkeyed = paths.filter { $0.groupKey == nil }.sorted { $0.byteCount > $1.byteCount }
        if !unkeyed.isEmpty {
            groups.append(Group(key: "__other__", label: "Other items", paths: unkeyed))
        }
        return groups
    }

    /// Applies the detail view's show-more limit across groups: returns whole
    /// groups until the limit is hit, then a partial final group.
    static func displayGroups(from groups: [Group], limit: Int) -> (groups: [Group], omittedRows: Int) {
        guard limit >= 0 else { return (groups, 0) }
        var shown: [Group] = []
        var used = 0
        var omitted = 0

        for group in groups {
            let remaining = limit - used
            if remaining <= 0 {
                omitted += group.paths.count
                continue
            }
            if group.paths.count <= remaining {
                shown.append(group)
                used += group.paths.count
            } else {
                shown.append(Group(key: group.key, label: group.label, paths: Array(group.paths.prefix(remaining))))
                omitted += group.paths.count - remaining
                used = limit
            }
        }
        return (shown, omitted)
    }
}
